using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class InteractiveWorkflowCoordinatorTests
{
    [Fact]
    public void Acquiring_an_interactive_workflow_returns_a_current_lease()
    {
        var coordinator = new InteractiveWorkflowCoordinator();

        var lease = coordinator.TryAcquire(InteractiveWorkflowKind.Dictation);

        Assert.NotNull(lease);
        Assert.NotEqual(Guid.Empty, lease.Id);
        Assert.NotEqual(Guid.Empty, lease.Generation);
        Assert.Equal(InteractiveWorkflowKind.Dictation, lease.Kind);
        Assert.False(lease.CancellationToken.IsCancellationRequested);
        Assert.True(coordinator.IsCurrent(lease));
    }

    [Fact]
    public void A_second_interactive_workflow_is_rejected_without_replacing_the_current_lease()
    {
        var coordinator = new InteractiveWorkflowCoordinator();
        var current = Assert.IsType<InteractiveWorkflowLease>(
            coordinator.TryAcquire(InteractiveWorkflowKind.SelectionTranslation));

        var rejected = coordinator.TryAcquire(InteractiveWorkflowKind.AgentCompose);

        Assert.Null(rejected);
        Assert.True(coordinator.IsCurrent(current));
        Assert.False(current.CancellationToken.IsCancellationRequested);
    }

    [Fact]
    public void Screenshot_uses_the_same_foreground_lease_without_creating_a_workflow_task()
    {
        var coordinator = new InteractiveWorkflowCoordinator();
        var screenshot = Assert.IsType<InteractiveWorkflowLease>(
            coordinator.TryAcquire(InteractiveWorkflowKind.Screenshot));

        Assert.Equal(InteractiveWorkflowKind.Screenshot, screenshot.Kind);
        Assert.Null(coordinator.TryAcquire(InteractiveWorkflowKind.Dictation));
        Assert.True(coordinator.Complete(screenshot));
        Assert.NotNull(coordinator.TryAcquire(InteractiveWorkflowKind.AgentCompose));
    }

    [Fact]
    public void Cancelling_a_lease_signals_its_token_and_rejects_late_events()
    {
        var coordinator = new InteractiveWorkflowCoordinator();
        var lease = Assert.IsType<InteractiveWorkflowLease>(
            coordinator.TryAcquire(InteractiveWorkflowKind.SelectionSummary));
        var mutationCount = 0;

        Assert.True(coordinator.Cancel(lease));

        Assert.True(lease.CancellationToken.IsCancellationRequested);
        Assert.False(coordinator.IsCurrent(lease));
        Assert.False(coordinator.TryApply(lease, () => mutationCount++));
        Assert.Equal(0, mutationCount);
    }

    [Fact]
    public void A_stale_lease_cannot_cancel_the_next_generation()
    {
        var coordinator = new InteractiveWorkflowCoordinator();
        var stale = Assert.IsType<InteractiveWorkflowLease>(
            coordinator.TryAcquire(InteractiveWorkflowKind.Dictation));
        Assert.True(coordinator.Cancel(stale));
        var current = Assert.IsType<InteractiveWorkflowLease>(
            coordinator.TryAcquire(InteractiveWorkflowKind.AgentCompose));

        Assert.NotEqual(stale.Id, current.Id);
        Assert.NotEqual(stale.Generation, current.Generation);
        Assert.False(coordinator.Cancel(stale));
        Assert.True(coordinator.IsCurrent(current));
        Assert.False(current.CancellationToken.IsCancellationRequested);
    }

    [Fact]
    public void Completing_a_lease_invalidates_generation_without_cancelling_successful_work()
    {
        var coordinator = new InteractiveWorkflowCoordinator();
        var lease = Assert.IsType<InteractiveWorkflowLease>(
            coordinator.TryAcquire(InteractiveWorkflowKind.SelectionTranslation));

        Assert.True(coordinator.Complete(lease));

        Assert.False(lease.CancellationToken.IsCancellationRequested);
        Assert.False(coordinator.IsCurrent(lease));
        Assert.False(coordinator.TryApply(
            lease,
            () => throw new InvalidOperationException("a completed generation is terminal")));
    }

    [Fact]
    public async Task Starting_an_interactive_workflow_does_not_preempt_running_file_transcription()
    {
        var executor = new BlockingFileTranscriptionExecutor();
        await using var fileQueue = new FileTranscriptionQueueService(executor);
        var coordinator = new InteractiveWorkflowCoordinator();
        Assert.True(fileQueue.TryEnqueue("background-job"));
        var running = await executor.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));

        var lease = coordinator.TryAcquire(InteractiveWorkflowKind.AgentCompose);

        Assert.NotNull(lease);
        Assert.True(fileQueue.IsCurrent("background-job", running.RunId));
        Assert.False(running.CancellationToken.IsCancellationRequested);

        executor.Release();
        await fileQueue.WhenIdleAsync().WaitAsync(TimeSpan.FromSeconds(2));
    }

    [Fact]
    public void Repeating_selection_cancels_old_generation_persists_partial_then_starts_new()
    {
        var coordinator = new InteractiveWorkflowCoordinator();
        var oldLease = Assert.IsType<InteractiveWorkflowLease>(
            coordinator.TryAcquire(InteractiveWorkflowKind.SelectionTranslation));
        var events = new List<string>();

        var result = coordinator.StartOrReplaceSelection(
            InteractiveWorkflowKind.SelectionSummary,
            providerAllowsFileConcurrency: true,
            cancelledLease =>
            {
                Assert.True(cancelledLease.CancellationToken.IsCancellationRequested);
                Assert.False(coordinator.IsCurrent(cancelledLease));
                events.Add("partial-saved");
            });

        Assert.Equal(InteractiveWorkflowStartStatus.ReplacedSelection, result.Status);
        Assert.NotNull(result.Lease);
        Assert.Equal(InteractiveWorkflowKind.SelectionSummary, result.Lease.Kind);
        Assert.NotEqual(oldLease.Generation, result.Lease.Generation);
        Assert.Equal(["partial-saved"], events);
        Assert.False(coordinator.TryApply(oldLease, () => events.Add("late-event")));
        Assert.Equal(["partial-saved"], events);
    }

    [Fact]
    public void Voice_lease_or_nonconcurrent_file_provider_returns_specific_busy_feedback()
    {
        var coordinator = new InteractiveWorkflowCoordinator();
        var voice = Assert.IsType<InteractiveWorkflowLease>(
            coordinator.TryAcquire(InteractiveWorkflowKind.AgentCompose));

        var voiceBusy = coordinator.StartOrReplaceSelection(
            InteractiveWorkflowKind.SelectionTranslation,
            providerAllowsFileConcurrency: true,
            _ => throw new InvalidOperationException("voice work is never replaced"));
        Assert.Equal(InteractiveWorkflowStartStatus.InteractiveBusy, voiceBusy.Status);
        Assert.True(coordinator.IsCurrent(voice));

        Assert.True(coordinator.Complete(voice));
        var fileBusy = coordinator.StartOrReplaceSelection(
            InteractiveWorkflowKind.SelectionTranslation,
            providerAllowsFileConcurrency: false,
            _ => throw new InvalidOperationException("no selection is active"));
        Assert.Equal(InteractiveWorkflowStartStatus.FileProviderBusy, fileBusy.Status);
        Assert.Null(fileBusy.Lease);
    }

    private sealed class BlockingFileTranscriptionExecutor
        : IFileTranscriptionJobExecutor
    {
        private readonly TaskCompletionSource release = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource<RunningFileTranscription> Started { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public async Task ExecuteAsync(
            string jobId,
            Guid runId,
            CancellationToken cancellationToken)
        {
            Started.TrySetResult(new RunningFileTranscription(
                runId,
                cancellationToken));
            await release.Task.WaitAsync(cancellationToken);
        }

        public void Release() => release.TrySetResult();
    }

    private sealed record RunningFileTranscription(
        Guid RunId,
        CancellationToken CancellationToken);
}
