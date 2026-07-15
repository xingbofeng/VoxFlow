using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public interface IPreparedFileTranscriptionMedia : IAsyncDisposable
{
    long DurationMs { get; }

    IFileTranscriptionWindowSource WindowSource { get; }
}

public interface IFileTranscriptionMediaPreparer
{
    ValueTask<IPreparedFileTranscriptionMedia> PrepareAsync(
        FileTranscriptionJob job,
        CancellationToken cancellationToken);
}

public class FileTranscriptionMediaPreparationException(
    FileTranscriptionErrorCode errorCode)
    : Exception($"File transcription media preparation failed ({errorCode}).")
{
    public FileTranscriptionErrorCode ErrorCode { get; } = errorCode;
}

public sealed class FileTranscriptionJobExecutor : IFileTranscriptionJobExecutor
{
    private readonly IFileTranscriptionJobRepository jobs;
    private readonly IFileTranscriptionSegmentRepository segments;
    private readonly FileTranscriptionSourceGuard sourceGuard;
    private readonly IFileTranscriptionMediaPreparer mediaPreparer;
    private readonly IFileTranscriptionWorker worker;
    private readonly IFileTranscriptionRunGate runGate;
    private readonly TimeProvider timeProvider;

    public FileTranscriptionJobExecutor(
        IFileTranscriptionJobRepository jobs,
        IFileTranscriptionSegmentRepository segments,
        IFileSourceAvailabilityProbe sourceProbe,
        IFileTranscriptionMediaPreparer mediaPreparer,
        IFileTranscriptionWorker worker,
        IFileTranscriptionRunGate runGate,
        TimeProvider timeProvider)
    {
        this.jobs = jobs ?? throw new ArgumentNullException(nameof(jobs));
        this.segments = segments ?? throw new ArgumentNullException(nameof(segments));
        sourceGuard = new FileTranscriptionSourceGuard(
            sourceProbe ?? throw new ArgumentNullException(nameof(sourceProbe)));
        this.mediaPreparer = mediaPreparer
            ?? throw new ArgumentNullException(nameof(mediaPreparer));
        this.worker = worker ?? throw new ArgumentNullException(nameof(worker));
        this.runGate = runGate ?? throw new ArgumentNullException(nameof(runGate));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public async Task ExecuteAsync(
        string jobId,
        Guid runId,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        if (runId == Guid.Empty)
        {
            throw new ArgumentException("A run ID is required.", nameof(runId));
        }
        var job = jobs.Get(jobId);
        if (job is null || !runGate.IsCurrent(jobId, runId))
        {
            return;
        }

        var source = await sourceGuard.CheckAsync(job, cancellationToken)
            .ConfigureAwait(false);
        if (!source.IsAvailable)
        {
            PersistFailure(job, runId, source.ErrorCode!.Value);
            return;
        }

        job = WithRunningState(job, durationMs: job.DurationMs);
        if (!runGate.TryApply(jobId, runId, () => jobs.Update(job)))
        {
            return;
        }

        try
        {
            await using var prepared = await mediaPreparer
                .PrepareAsync(job, cancellationToken)
                .ConfigureAwait(false);
            var windowCount = FileTranscriptionWindow
                .CreateForDuration(prepared.DurationMs)
                .Count;
            job = WithRunningState(job, prepared.DurationMs, windowCount);
            if (!runGate.TryApply(jobId, runId, () => jobs.Update(job)))
            {
                return;
            }

            var sink = new PersistingSegmentSink(
                jobs,
                segments,
                runGate,
                jobId,
                runId,
                windowCount,
                timeProvider);
            var pipeline = new FileTranscriptionPipeline(
                worker,
                prepared.WindowSource,
                sink);
            var existing = segments.ListByJob(jobId);
            var result = await pipeline.RunAsync(
                jobId,
                job.Provider,
                job.Language,
                prepared.DurationMs,
                existing,
                cancellationToken).ConfigureAwait(false);
            var completed = FileTranscriptionJobResultAggregator.Aggregate(
                job,
                result.Segments,
                result.FinalText,
                Now(job));
            _ = runGate.TryApply(jobId, runId, () => jobs.Update(completed));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (FileTranscriptionMediaPreparationException exception)
        {
            PersistFailure(job, runId, exception.ErrorCode);
        }
        catch
        {
            PersistFailure(job, runId, FileTranscriptionErrorCode.ProviderFailure);
        }
    }

    private void PersistFailure(
        FileTranscriptionJob job,
        Guid runId,
        FileTranscriptionErrorCode errorCode)
    {
        var failed = new FileTranscriptionJob(
            job.Id,
            job.SourcePath,
            job.DisplayName,
            job.Provider,
            job.Language,
            job.CreatedAtUnixMs,
            FileTranscriptionJobStatus.Failed,
            job.DurationMs,
            job.Progress,
            job.RawText,
            job.FinalText,
            errorCode,
            job.ProviderMode,
            job.SegmentCount,
            job.SegmentCompleted,
            job.PartialFailureSummary,
            job.TranslationStatus,
            job.TranslatedText,
            job.TranslationTargetLanguage,
            job.TranslationErrorCode,
            job.TranslationUpdatedAtUnixMs,
            Now(job),
            job.CompletedAtUnixMs);
        _ = runGate.TryApply(job.Id, runId, () => jobs.Update(failed));
    }

    private FileTranscriptionJob WithRunningState(
        FileTranscriptionJob job,
        long? durationMs,
        int? segmentCount = null) => new(
            job.Id,
            job.SourcePath,
            job.DisplayName,
            job.Provider,
            job.Language,
            job.CreatedAtUnixMs,
            FileTranscriptionJobStatus.Running,
            durationMs,
            job.Progress,
            job.RawText,
            job.FinalText,
            errorCode: null,
            job.ProviderMode,
            segmentCount ?? job.SegmentCount,
            Math.Min(job.SegmentCompleted, segmentCount ?? job.SegmentCount),
            job.PartialFailureSummary,
            job.TranslationStatus,
            job.TranslatedText,
            job.TranslationTargetLanguage,
            job.TranslationErrorCode,
            job.TranslationUpdatedAtUnixMs,
            Now(job),
            completedAtUnixMs: null);

    private long Now(FileTranscriptionJob job) => Math.Max(
        job.UpdatedAtUnixMs,
        timeProvider.GetUtcNow().ToUnixTimeMilliseconds());

    private sealed class PersistingSegmentSink(
        IFileTranscriptionJobRepository jobs,
        IFileTranscriptionSegmentRepository segments,
        IFileTranscriptionRunGate runGate,
        string jobId,
        Guid runId,
        int totalCount,
        TimeProvider timeProvider) : IFileTranscriptionSegmentSink
    {
        public ValueTask PublishAsync(
            FileTranscriptionSegment segment,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _ = runGate.TryApply(jobId, runId, () =>
            {
                segments.Upsert(segment);
                var all = segments.ListByJob(jobId);
                var successful = all.Count(item =>
                    item.Status == FileTranscriptionSegmentStatus.Completed);
                var processed = all.Count(item => item.Status is
                    FileTranscriptionSegmentStatus.Completed
                    or FileTranscriptionSegmentStatus.Failed);
                var current = jobs.Get(jobId);
                if (current is null)
                {
                    return;
                }
                var updatedAt = Math.Max(
                    current.UpdatedAtUnixMs,
                    timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
                jobs.Update(new FileTranscriptionJob(
                    current.Id,
                    current.SourcePath,
                    current.DisplayName,
                    current.Provider,
                    current.Language,
                    current.CreatedAtUnixMs,
                    current.Status,
                    current.DurationMs,
                    totalCount == 0 ? 0 : (double)processed / totalCount,
                    current.RawText,
                    current.FinalText,
                    current.ErrorCode,
                    current.ProviderMode,
                    totalCount,
                    successful,
                    current.PartialFailureSummary,
                    current.TranslationStatus,
                    current.TranslatedText,
                    current.TranslationTargetLanguage,
                    current.TranslationErrorCode,
                    current.TranslationUpdatedAtUnixMs,
                    updatedAt,
                    current.CompletedAtUnixMs));
            });
            return ValueTask.CompletedTask;
        }
    }
}
