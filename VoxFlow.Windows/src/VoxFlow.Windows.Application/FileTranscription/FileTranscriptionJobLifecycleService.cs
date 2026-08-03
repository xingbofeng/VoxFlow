using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public sealed record FileTranscriptionRecoveryResult(int JobCount, int SegmentCount);

public static class FileTranscriptionJobResultAggregator
{
    public static FileTranscriptionJob Aggregate(
        FileTranscriptionJob job,
        IReadOnlyCollection<FileTranscriptionSegment> segments,
        string finalText,
        long updatedAtUnixMs)
    {
        ArgumentNullException.ThrowIfNull(job);
        ArgumentNullException.ThrowIfNull(segments);
        ArgumentNullException.ThrowIfNull(finalText);
        if (updatedAtUnixMs < job.CreatedAtUnixMs)
        {
            throw new ArgumentOutOfRangeException(nameof(updatedAtUnixMs));
        }
        if (segments.Any(segment => segment.JobId != job.Id))
        {
            throw new ArgumentException("All segments must belong to the job.", nameof(segments));
        }

        var completed = segments.Count(segment =>
            segment.Status == FileTranscriptionSegmentStatus.Completed);
        var failed = segments.Count - completed;
        var status = completed == segments.Count && completed > 0
            ? FileTranscriptionJobStatus.Completed
            : completed > 0
                ? FileTranscriptionJobStatus.PartiallyFailed
                : FileTranscriptionJobStatus.Failed;
        var effectiveText = completed > 0 ? finalText.Trim() : null;
        if (completed > 0 && string.IsNullOrWhiteSpace(effectiveText))
        {
            throw new ArgumentException(
                "Successful segments require aggregate text.",
                nameof(finalText));
        }
        FileTranscriptionErrorCode? errorCode = status == FileTranscriptionJobStatus.Failed
            ? segments.Select(segment => segment.ErrorCode).FirstOrDefault(code => code is not null)
                ?? FileTranscriptionErrorCode.ProviderFailure
            : null;

        return new FileTranscriptionJob(
            job.Id,
            job.SourcePath,
            job.DisplayName,
            job.Provider,
            job.Language,
            job.CreatedAtUnixMs,
            status,
            job.DurationMs,
            progress: 1,
            rawText: effectiveText,
            finalText: effectiveText,
            errorCode: errorCode,
            providerMode: job.ProviderMode,
            segmentCount: segments.Count,
            segmentCompleted: completed,
            partialFailureSummary: failed > 0 && completed > 0
                ? $"completed={completed};failed={failed}"
                : null,
            translationStatus: FileTranscriptionTranslationStatus.NotRequested,
            updatedAtUnixMs: updatedAtUnixMs,
            completedAtUnixMs: updatedAtUnixMs);
    }
}

public sealed class FileTranscriptionRunMutationGate
{
    private readonly IFileTranscriptionRunGate runGate;
    private readonly string jobId;
    private readonly Guid runId;

    public FileTranscriptionRunMutationGate(
        IFileTranscriptionRunGate runGate,
        string jobId,
        Guid runId)
    {
        this.runGate = runGate ?? throw new ArgumentNullException(nameof(runGate));
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        if (runId == Guid.Empty)
        {
            throw new ArgumentException("A run ID is required.", nameof(runId));
        }
        this.jobId = jobId;
        this.runId = runId;
    }

    public bool TryApply(Action mutation) =>
        runGate.TryApply(jobId, runId, mutation);
}

public sealed class FileTranscriptionJobLifecycleService
{
    private readonly IFileTranscriptionJobRepository jobs;
    private readonly IFileTranscriptionSegmentRepository segments;
    private readonly FileTranscriptionQueueService queue;
    private readonly TimeProvider timeProvider;

    public FileTranscriptionJobLifecycleService(
        IFileTranscriptionJobRepository jobs,
        IFileTranscriptionSegmentRepository segments,
        FileTranscriptionQueueService queue,
        TimeProvider timeProvider)
    {
        this.jobs = jobs ?? throw new ArgumentNullException(nameof(jobs));
        this.segments = segments ?? throw new ArgumentNullException(nameof(segments));
        this.queue = queue ?? throw new ArgumentNullException(nameof(queue));
        this.timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public bool Cancel(string jobId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        _ = queue.Cancel(jobId);
        var job = jobs.Get(jobId);
        return job is not null && jobs.Update(Copy(
            job,
            FileTranscriptionJobStatus.Cancelled,
            UpdatedAt(job)));
    }

    public FileTranscriptionRecoveryResult RecoverInterruptedWork() => new(
        jobs.MarkRunningAsInterrupted(),
        segments.MarkRunningAsInterrupted());

    public bool Continue(string jobId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        var job = jobs.Get(jobId);
        if (job is null
            || job.Status is not (FileTranscriptionJobStatus.Interrupted
                or FileTranscriptionJobStatus.PartiallyFailed))
        {
            return false;
        }

        var queued = new FileTranscriptionJob(
            job.Id,
            job.SourcePath,
            job.DisplayName,
            job.Provider,
            job.Language,
            job.CreatedAtUnixMs,
            status: FileTranscriptionJobStatus.Queued,
            durationMs: job.DurationMs,
            progress: job.Progress,
            rawText: job.RawText,
            finalText: job.FinalText,
            providerMode: job.ProviderMode,
            segmentCount: job.SegmentCount,
            segmentCompleted: job.SegmentCompleted,
            updatedAtUnixMs: UpdatedAt(job));
        return jobs.Update(queued) && queue.TryEnqueue(jobId);
    }

    public bool Delete(string jobId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        _ = queue.Cancel(jobId);
        _ = segments.DeleteByJob(jobId);
        return jobs.Delete(jobId);
    }

    public bool RetryFromBeginning(string jobId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        _ = queue.Cancel(jobId);
        var job = jobs.Get(jobId);
        if (job is null)
        {
            return false;
        }

        _ = segments.DeleteByJob(jobId);
        var reset = new FileTranscriptionJob(
            job.Id,
            job.SourcePath,
            job.DisplayName,
            job.Provider,
            job.Language,
            job.CreatedAtUnixMs,
            status: FileTranscriptionJobStatus.Queued,
            providerMode: job.ProviderMode,
            updatedAtUnixMs: UpdatedAt(job));
        if (!jobs.Update(reset))
        {
            return false;
        }

        return queue.TryEnqueue(jobId);
    }

    private long UpdatedAt(FileTranscriptionJob job) => Math.Max(
        job.UpdatedAtUnixMs,
        timeProvider.GetUtcNow().ToUnixTimeMilliseconds());

    private static FileTranscriptionJob Copy(
        FileTranscriptionJob job,
        FileTranscriptionJobStatus status,
        long updatedAtUnixMs) => new(
            job.Id,
            job.SourcePath,
            job.DisplayName,
            job.Provider,
            job.Language,
            job.CreatedAtUnixMs,
            status,
            job.DurationMs,
            job.Progress,
            job.RawText,
            job.FinalText,
            job.ErrorCode,
            job.ProviderMode,
            job.SegmentCount,
            job.SegmentCompleted,
            job.PartialFailureSummary,
            job.TranslationStatus,
            job.TranslatedText,
            job.TranslationTargetLanguage,
            job.TranslationErrorCode,
            job.TranslationUpdatedAtUnixMs,
            updatedAtUnixMs,
            job.CompletedAtUnixMs);
}
