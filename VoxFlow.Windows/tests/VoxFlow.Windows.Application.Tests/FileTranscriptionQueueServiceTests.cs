using System.Threading.Channels;
using VoxFlow.Windows.Application.FileTranscription;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionQueueServiceTests
{
    [Fact]
    public async Task Multiple_jobs_run_globally_one_at_a_time_in_enqueue_order()
    {
        var executor = new ControllableExecutor();
        await using var queue = new FileTranscriptionQueueService(executor);

        Assert.True(queue.TryEnqueue("job-1"));
        Assert.True(queue.TryEnqueue("job-2"));
        Assert.True(queue.TryEnqueue("job-3"));

        Assert.Equal("job-1", await executor.NextStartedAsync());
        Assert.True(queue.IsCurrent("job-1", executor.RunIds[0]));
        Assert.False(queue.IsCurrent("job-1", Guid.NewGuid()));
        Assert.Equal(1, executor.MaximumConcurrentCount);
        executor.ReleaseOne();
        Assert.Equal("job-2", await executor.NextStartedAsync());
        Assert.Equal(1, executor.MaximumConcurrentCount);
        executor.ReleaseOne();
        Assert.Equal("job-3", await executor.NextStartedAsync());
        executor.ReleaseOne();
        await queue.WhenIdleAsync().WaitAsync(TimeSpan.FromSeconds(1));

        Assert.Equal(["job-1", "job-2", "job-3"], executor.StartOrder);
        Assert.Equal(1, executor.MaximumConcurrentCount);
        Assert.False(queue.IsCurrent("job-3", executor.RunIds[2]));
    }

    [Fact]
    public async Task Repeated_start_click_does_not_create_a_second_run_or_session()
    {
        var executor = new ControllableExecutor();
        await using var queue = new FileTranscriptionQueueService(executor);

        Assert.True(queue.TryEnqueue("job-1"));
        Assert.False(queue.TryEnqueue("job-1"));
        Assert.Equal("job-1", await executor.NextStartedAsync());
        Assert.False(queue.TryEnqueue("job-1"));
        executor.ReleaseOne();
        await queue.WhenIdleAsync().WaitAsync(TimeSpan.FromSeconds(1));

        Assert.Single(executor.StartOrder);
        Assert.Single(executor.RunIds);
        Assert.NotEqual(Guid.Empty, executor.RunIds[0]);
    }

    [Fact]
    public async Task Cancel_invalidates_the_run_before_late_callbacks_can_mutate_state()
    {
        var executor = new ControllableExecutor();
        await using var queue = new FileTranscriptionQueueService(executor);
        Assert.True(queue.TryEnqueue("job-1"));
        Assert.Equal("job-1", await executor.NextStartedAsync());
        var runId = executor.RunIds[0];
        var mutations = new FileTranscriptionRunMutationGate(queue, "job-1", runId);
        var applied = new List<string>();

        Assert.True(mutations.TryApply(() => applied.Add("current")));
        Assert.True(queue.Cancel("job-1"));
        Assert.False(queue.IsCurrent("job-1", runId));
        Assert.False(mutations.TryApply(() => applied.Add("late-segment")));
        Assert.False(mutations.TryApply(() => applied.Add("late-progress")));
        Assert.False(mutations.TryApply(() => applied.Add("late-final")));
        await queue.WhenIdleAsync().WaitAsync(TimeSpan.FromSeconds(1));

        Assert.Equal(["current"], applied);
    }

    private sealed class ControllableExecutor : IFileTranscriptionJobExecutor
    {
        private readonly Channel<string> started = Channel.CreateUnbounded<string>();
        private readonly SemaphoreSlim releases = new(0);
        private int activeCount;

        public List<string> StartOrder { get; } = [];
        public List<Guid> RunIds { get; } = [];
        public int MaximumConcurrentCount { get; private set; }

        public async Task ExecuteAsync(
            string jobId,
            Guid runId,
            CancellationToken cancellationToken)
        {
            var active = Interlocked.Increment(ref activeCount);
            MaximumConcurrentCount = Math.Max(MaximumConcurrentCount, active);
            StartOrder.Add(jobId);
            RunIds.Add(runId);
            await started.Writer.WriteAsync(jobId, cancellationToken);
            try
            {
                await releases.WaitAsync(cancellationToken);
            }
            finally
            {
                Interlocked.Decrement(ref activeCount);
            }
        }

        public async Task<string> NextStartedAsync() =>
            await started.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));

        public void ReleaseOne() => releases.Release();
    }
}
