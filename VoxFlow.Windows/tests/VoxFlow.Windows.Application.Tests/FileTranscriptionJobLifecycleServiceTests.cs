using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionJobLifecycleServiceTests
{
    [Fact]
    public async Task Cancel_preserves_completed_segments_and_text_but_marks_the_job_cancelled()
    {
        var fixture = new Fixture(CreateJob(FileTranscriptionJobStatus.Running));
        fixture.Segments.Upsert(CompletedSegment());

        Assert.True(fixture.Lifecycle.Cancel("job-1"));

        var job = fixture.Jobs.Get("job-1")!;
        Assert.Equal(FileTranscriptionJobStatus.Cancelled, job.Status);
        Assert.Equal("existing text", job.FinalText);
        Assert.Single(fixture.Segments.ListByJob("job-1"));
        await fixture.DisposeAsync();
    }

    [Fact]
    public async Task Delete_invalidates_the_run_and_removes_job_and_segments()
    {
        var fixture = new Fixture(CreateJob(FileTranscriptionJobStatus.Queued));
        fixture.Segments.Upsert(CompletedSegment());
        Assert.True(fixture.Queue.TryEnqueue("job-1"));
        Assert.Equal("job-1", await fixture.Executor.NextStartedAsync());
        var runId = fixture.Executor.RunIds[0];

        Assert.True(fixture.Lifecycle.Delete("job-1"));

        Assert.False(fixture.Queue.IsCurrent("job-1", runId));
        Assert.Null(fixture.Jobs.Get("job-1"));
        Assert.Empty(fixture.Segments.ListByJob("job-1"));
        await fixture.DisposeAsync();
    }

    [Fact]
    public async Task Retry_from_beginning_clears_results_and_segments_then_creates_a_new_run()
    {
        var fixture = new Fixture(CreateJob(FileTranscriptionJobStatus.PartiallyFailed));
        fixture.Segments.Upsert(CompletedSegment());

        Assert.True(fixture.Lifecycle.RetryFromBeginning("job-1"));
        Assert.Equal("job-1", await fixture.Executor.NextStartedAsync());

        var job = fixture.Jobs.Get("job-1")!;
        Assert.Equal(FileTranscriptionJobStatus.Queued, job.Status);
        Assert.Equal(0, job.Progress);
        Assert.Null(job.RawText);
        Assert.Null(job.FinalText);
        Assert.Null(job.ErrorCode);
        Assert.Equal(FileTranscriptionTranslationStatus.NotRequested, job.TranslationStatus);
        Assert.Null(job.TranslatedText);
        Assert.Empty(fixture.Segments.ListByJob("job-1"));
        Assert.NotEqual(Guid.Empty, fixture.Executor.RunIds[0]);
        fixture.Executor.ReleaseOne();
        await fixture.DisposeAsync();
    }

    [Fact]
    public async Task Startup_recovery_interrupts_running_work_and_continue_preserves_completed_segments()
    {
        var fixture = new Fixture(CreateJob(FileTranscriptionJobStatus.Running));
        fixture.Segments.Upsert(CompletedSegment());
        fixture.Segments.Upsert(new FileTranscriptionSegment(
            "job-1",
            1,
            28_500,
            58_500,
            FileTranscriptionSegmentStatus.Running,
            AsrProviderId.TencentCloud));

        var recovered = fixture.Lifecycle.RecoverInterruptedWork();

        Assert.Equal(1, recovered.JobCount);
        Assert.Equal(1, recovered.SegmentCount);
        Assert.Equal(FileTranscriptionJobStatus.Interrupted, fixture.Jobs.Get("job-1")!.Status);
        Assert.Equal(
            [FileTranscriptionSegmentStatus.Completed, FileTranscriptionSegmentStatus.Interrupted],
            fixture.Segments.ListByJob("job-1").Select(segment => segment.Status));

        Assert.True(fixture.Lifecycle.Continue("job-1"));
        Assert.Equal("job-1", await fixture.Executor.NextStartedAsync());
        Assert.Equal(2, fixture.Segments.ListByJob("job-1").Count);
        fixture.Executor.ReleaseOne();
        await fixture.DisposeAsync();
    }

    [Fact]
    public void Aggregator_reports_partial_failure_without_losing_successful_text()
    {
        var job = CreateJob(FileTranscriptionJobStatus.Running);
        var segments = new[]
        {
            CompletedSegment(),
            new FileTranscriptionSegment(
                "job-1",
                1,
                28_500,
                58_500,
                FileTranscriptionSegmentStatus.Failed,
                AsrProviderId.TencentCloud,
                retryCount: 2,
                fallbackReason: SegmentFallbackReason.RetryAfterProviderError,
                errorCode: FileTranscriptionErrorCode.ProviderNetworkFailure),
        };

        var result = FileTranscriptionJobResultAggregator.Aggregate(
            job,
            segments,
            "successful text",
            updatedAtUnixMs: 3);

        Assert.Equal(FileTranscriptionJobStatus.PartiallyFailed, result.Status);
        Assert.Equal("successful text", result.FinalText);
        Assert.Equal(2, result.SegmentCount);
        Assert.Equal(1, result.SegmentCompleted);
        Assert.NotNull(result.PartialFailureSummary);
        Assert.Equal(1, result.Progress);
    }

    private static FileTranscriptionJob CreateJob(FileTranscriptionJobStatus status) => new(
        "job-1",
        @"C:\Recordings\meeting.wav",
        "meeting.wav",
        AsrProviderId.TencentCloud,
        RecognitionLanguage.ChineseMandarin,
        1,
        status: status,
        progress: 0.5,
        rawText: "raw",
        finalText: "existing text",
        errorCode: status == FileTranscriptionJobStatus.PartiallyFailed
            ? FileTranscriptionErrorCode.ProviderFailure
            : null,
        segmentCount: 2,
        segmentCompleted: 1,
        partialFailureSummary: status == FileTranscriptionJobStatus.PartiallyFailed
            ? "one failed"
            : null,
        translationStatus: FileTranscriptionTranslationStatus.Completed,
        translatedText: "translated",
        translationTargetLanguage: "en",
        translationUpdatedAtUnixMs: 2,
        updatedAtUnixMs: 2);

    private static FileTranscriptionSegment CompletedSegment() => new(
        "job-1",
        0,
        0,
        30_000,
        FileTranscriptionSegmentStatus.Completed,
        AsrProviderId.TencentCloud,
        "existing text");

    private sealed class Fixture : IAsyncDisposable
    {
        public Fixture(FileTranscriptionJob job)
        {
            Jobs.Create(job);
            Queue = new FileTranscriptionQueueService(Executor);
            Lifecycle = new FileTranscriptionJobLifecycleService(
                Jobs,
                Segments,
                Queue,
                TimeProvider.System);
        }

        public InMemoryJobRepository Jobs { get; } = new();
        public InMemorySegmentRepository Segments { get; } = new();
        public LifecycleExecutor Executor { get; } = new();
        public FileTranscriptionQueueService Queue { get; }
        public FileTranscriptionJobLifecycleService Lifecycle { get; }

        public async ValueTask DisposeAsync()
        {
            Executor.ReleaseOne();
            await Queue.DisposeAsync();
        }
    }

    private sealed class LifecycleExecutor : IFileTranscriptionJobExecutor
    {
        private readonly System.Threading.Channels.Channel<string> started =
            System.Threading.Channels.Channel.CreateUnbounded<string>();
        private readonly SemaphoreSlim releases = new(0);

        public List<Guid> RunIds { get; } = [];

        public async Task ExecuteAsync(
            string jobId,
            Guid runId,
            CancellationToken cancellationToken)
        {
            RunIds.Add(runId);
            await started.Writer.WriteAsync(jobId, cancellationToken);
            await releases.WaitAsync(cancellationToken);
        }

        public async Task<string> NextStartedAsync() =>
            await started.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));

        public void ReleaseOne() => releases.Release();
    }

    private sealed class InMemoryJobRepository : IFileTranscriptionJobRepository
    {
        private readonly Dictionary<string, FileTranscriptionJob> jobs = new(StringComparer.Ordinal);

        public void Create(FileTranscriptionJob job) => jobs.Add(job.Id, job);
        public FileTranscriptionJob? Get(string id) => jobs.GetValueOrDefault(id);
        public IReadOnlyList<FileTranscriptionJob> List() => jobs.Values.ToArray();
        public bool Update(FileTranscriptionJob job)
        {
            if (!jobs.ContainsKey(job.Id)) return false;
            jobs[job.Id] = job;
            return true;
        }
        public bool Delete(string id) => jobs.Remove(id);
        public int MarkRunningAsInterrupted()
        {
            var running = jobs.Values
                .Where(job => job.Status == FileTranscriptionJobStatus.Running)
                .ToArray();
            foreach (var job in running)
            {
                jobs[job.Id] = new FileTranscriptionJob(
                    job.Id,
                    job.SourcePath,
                    job.DisplayName,
                    job.Provider,
                    job.Language,
                    job.CreatedAtUnixMs,
                    status: FileTranscriptionJobStatus.Interrupted,
                    durationMs: job.DurationMs,
                    progress: job.Progress,
                    rawText: job.RawText,
                    finalText: job.FinalText,
                    errorCode: job.ErrorCode,
                    providerMode: job.ProviderMode,
                    segmentCount: job.SegmentCount,
                    segmentCompleted: job.SegmentCompleted,
                    partialFailureSummary: job.PartialFailureSummary,
                    translationStatus: job.TranslationStatus,
                    translatedText: job.TranslatedText,
                    translationTargetLanguage: job.TranslationTargetLanguage,
                    translationErrorCode: job.TranslationErrorCode,
                    translationUpdatedAtUnixMs: job.TranslationUpdatedAtUnixMs,
                    updatedAtUnixMs: job.UpdatedAtUnixMs,
                    completedAtUnixMs: job.CompletedAtUnixMs);
            }
            return running.Length;
        }
    }

    private sealed class InMemorySegmentRepository : IFileTranscriptionSegmentRepository
    {
        private readonly Dictionary<(string JobId, int Index), FileTranscriptionSegment> segments = [];

        public void Upsert(FileTranscriptionSegment segment) =>
            segments[(segment.JobId, segment.Index)] = segment;
        public IReadOnlyList<FileTranscriptionSegment> ListByJob(string jobId) =>
            segments.Values.Where(segment => segment.JobId == jobId).OrderBy(segment => segment.Index).ToArray();
        public int DeleteByJob(string jobId)
        {
            var keys = segments.Keys.Where(key => key.JobId == jobId).ToArray();
            foreach (var key in keys) segments.Remove(key);
            return keys.Length;
        }
        public int MarkRunningAsInterrupted()
        {
            var keys = segments
                .Where(pair => pair.Value.Status == FileTranscriptionSegmentStatus.Running)
                .Select(pair => pair.Key)
                .ToArray();
            foreach (var key in keys)
            {
                var segment = segments[key];
                segments[key] = new FileTranscriptionSegment(
                    segment.JobId,
                    segment.Index,
                    segment.StartMs,
                    segment.EndMs,
                    FileTranscriptionSegmentStatus.Interrupted,
                    segment.Provider,
                    segment.Text,
                    segment.RetryCount,
                    segment.ProviderMode,
                    segment.FallbackReason,
                    segment.ErrorCode);
            }
            return keys.Length;
        }
    }
}
