using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionJobExecutorTests
{
    [Fact]
    public async Task Executor_prepares_media_runs_pipeline_persists_segments_and_disposes_temporary_media()
    {
        var jobs = new ExecutorJobRepository(Job());
        var segments = new ExecutorSegmentRepository();
        var prepared = new FakePreparedMedia(durationMs: 1_000);
        var executor = new FileTranscriptionJobExecutor(
            jobs,
            segments,
            new AvailableSourceProbe(),
            new FakeMediaPreparer(prepared),
            new FixedWorker("final text"),
            new AlwaysCurrentRunGate(),
            new FixedTimeProvider(10));

        await executor.ExecuteAsync("job-1", Guid.NewGuid(), CancellationToken.None);

        Assert.True(prepared.Disposed);
        var job = jobs.Get("job-1")!;
        Assert.Equal(FileTranscriptionJobStatus.Completed, job.Status);
        Assert.Equal("final text", job.FinalText);
        Assert.Equal(1, job.SegmentCount);
        Assert.Equal(1, job.SegmentCompleted);
        var segment = Assert.Single(segments.ListByJob("job-1"));
        Assert.Equal(FileTranscriptionSegmentStatus.Completed, segment.Status);
        Assert.Equal(AsrProviderId.TencentCloud, segment.Provider);
    }

    [Fact]
    public async Task Cancellation_disposes_task_media_and_window_without_marking_a_new_failure()
    {
        var jobs = new ExecutorJobRepository(Job());
        var segments = new ExecutorSegmentRepository();
        var prepared = new FakePreparedMedia(durationMs: 1_000);
        var worker = new BlockingWorker();
        var executor = new FileTranscriptionJobExecutor(
            jobs,
            segments,
            new AvailableSourceProbe(),
            new FakeMediaPreparer(prepared),
            worker,
            new AlwaysCurrentRunGate(),
            new FixedTimeProvider(10));
        using var cancellation = new CancellationTokenSource();
        var task = executor.ExecuteAsync("job-1", Guid.NewGuid(), cancellation.Token);
        await worker.Started.Task.WaitAsync(TimeSpan.FromSeconds(1));

        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => task);
        Assert.True(prepared.Disposed);
        Assert.True(prepared.WindowSource.LeaseDisposed);
        Assert.NotEqual(FileTranscriptionJobStatus.Failed, jobs.Get("job-1")!.Status);
    }

    [Fact]
    public async Task Media_failure_is_persisted_with_a_safe_error_code_and_no_provider_call()
    {
        var jobs = new ExecutorJobRepository(Job());
        var worker = new FixedWorker("must not run");
        var executor = new FileTranscriptionJobExecutor(
            jobs,
            new ExecutorSegmentRepository(),
            new AvailableSourceProbe(),
            new ThrowingMediaPreparer(FileTranscriptionErrorCode.NoAudioTrack),
            worker,
            new AlwaysCurrentRunGate(),
            new FixedTimeProvider(10));

        await executor.ExecuteAsync("job-1", Guid.NewGuid(), CancellationToken.None);

        Assert.Equal(0, worker.CallCount);
        var job = jobs.Get("job-1")!;
        Assert.Equal(FileTranscriptionJobStatus.Failed, job.Status);
        Assert.Equal(FileTranscriptionErrorCode.NoAudioTrack, job.ErrorCode);
    }

    private static FileTranscriptionJob Job() => new(
        "job-1",
        @"C:\Recordings\meeting.wav",
        "meeting.wav",
        AsrProviderId.TencentCloud,
        RecognitionLanguage.ChineseMandarin,
        1);

    private sealed class FakePreparedMedia(long durationMs) : IPreparedFileTranscriptionMedia
    {
        public long DurationMs { get; } = durationMs;
        public FakeWindowSource WindowSource { get; } = new();
        IFileTranscriptionWindowSource IPreparedFileTranscriptionMedia.WindowSource => WindowSource;
        public bool Disposed { get; private set; }
        public ValueTask DisposeAsync()
        {
            Disposed = true;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeMediaPreparer(FakePreparedMedia prepared)
        : IFileTranscriptionMediaPreparer
    {
        public ValueTask<IPreparedFileTranscriptionMedia> PrepareAsync(
            FileTranscriptionJob job,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult<IPreparedFileTranscriptionMedia>(prepared);
    }

    private sealed class ThrowingMediaPreparer(FileTranscriptionErrorCode errorCode)
        : IFileTranscriptionMediaPreparer
    {
        public ValueTask<IPreparedFileTranscriptionMedia> PrepareAsync(
            FileTranscriptionJob job,
            CancellationToken cancellationToken) =>
            ValueTask.FromException<IPreparedFileTranscriptionMedia>(
                new FileTranscriptionMediaPreparationException(errorCode));
    }

    private sealed class FakeWindowSource : IFileTranscriptionWindowSource
    {
        public bool LeaseDisposed { get; private set; }

        public ValueTask<IFileTranscriptionWindowLease> CreateAsync(
            FileTranscriptionWindow window,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult<IFileTranscriptionWindowLease>(new Lease(this));

        private sealed class Lease(FakeWindowSource owner) : IFileTranscriptionWindowLease
        {
            public string AudioPath => "segment.wav";
            public ValueTask DisposeAsync()
            {
                owner.LeaseDisposed = true;
                return ValueTask.CompletedTask;
            }
        }
    }

    private sealed class FixedWorker(string text) : IFileTranscriptionWorker
    {
        public int CallCount { get; private set; }
        public ValueTask<FileTranscriptionWorkerResult> TranscribeAsync(
            FileTranscriptionSegmentRequest request,
            CancellationToken cancellationToken)
        {
            CallCount++;
            return ValueTask.FromResult(new FileTranscriptionWorkerResult(text));
        }
    }

    private sealed class BlockingWorker : IFileTranscriptionWorker
    {
        public TaskCompletionSource Started { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public async ValueTask<FileTranscriptionWorkerResult> TranscribeAsync(
            FileTranscriptionSegmentRequest request,
            CancellationToken cancellationToken)
        {
            Started.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return new FileTranscriptionWorkerResult("unreachable");
        }
    }

    private sealed class AvailableSourceProbe : IFileSourceAvailabilityProbe
    {
        public ValueTask<FileSourceAvailability> InspectAsync(
            string sourcePath,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(FileSourceAvailability.Available);
    }

    private sealed class AlwaysCurrentRunGate : IFileTranscriptionRunGate
    {
        public bool IsCurrent(string jobId, Guid runId) => true;
        public bool TryApply(string jobId, Guid runId, Action mutation)
        {
            mutation();
            return true;
        }
    }

    private sealed class ExecutorJobRepository(FileTranscriptionJob initial)
        : IFileTranscriptionJobRepository
    {
        private FileTranscriptionJob job = initial;
        public void Create(FileTranscriptionJob job) => throw new NotSupportedException();
        public FileTranscriptionJob? Get(string id) => id == job.Id ? job : null;
        public IReadOnlyList<FileTranscriptionJob> List() => [job];
        public bool Update(FileTranscriptionJob value) { job = value; return true; }
        public bool Delete(string id) => throw new NotSupportedException();
        public int MarkRunningAsInterrupted() => throw new NotSupportedException();
    }

    private sealed class ExecutorSegmentRepository : IFileTranscriptionSegmentRepository
    {
        private readonly Dictionary<int, FileTranscriptionSegment> segments = [];
        public void Upsert(FileTranscriptionSegment segment) => segments[segment.Index] = segment;
        public IReadOnlyList<FileTranscriptionSegment> ListByJob(string jobId) =>
            segments.Values.Where(segment => segment.JobId == jobId).OrderBy(segment => segment.Index).ToArray();
        public int DeleteByJob(string jobId) => throw new NotSupportedException();
        public int MarkRunningAsInterrupted() => throw new NotSupportedException();
    }

    private sealed class FixedTimeProvider(long unixMilliseconds) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() =>
            DateTimeOffset.FromUnixTimeMilliseconds(unixMilliseconds);
    }
}
