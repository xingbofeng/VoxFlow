using VoxFlow.Windows.Application.SelectionTransform;

namespace VoxFlow.Windows.Application.Tests.SelectionTransform;

public sealed class SelectionTransformStateMachineTests
{
    [Fact]
    public void Started_partial_and_final_emit_one_authoritative_completed_event()
    {
        var machine = new SelectionTransformStateMachine(Guid.Parse("11111111-1111-1111-1111-111111111111"));

        Assert.IsType<SelectionTransformStarted>(machine.Start());
        Assert.IsType<SelectionTransformPartial>(machine.ApplySnapshot(machine.Generation, "译"));
        Assert.IsType<SelectionTransformPartial>(machine.ApplySnapshot(machine.Generation, "译文"));
        var completed = Assert.IsType<SelectionTransformCompleted>(machine.Complete(machine.Generation, "最终译文"));

        Assert.Equal("最终译文", completed.Text);
        Assert.Null(machine.Complete(machine.Generation, "重复 final"));
        Assert.Equal(SelectionTransformState.Completed, machine.State);
    }

    [Fact]
    public void Old_generation_and_late_chunks_are_dropped()
    {
        var machine = new SelectionTransformStateMachine(Guid.Parse("22222222-2222-2222-2222-222222222222"));
        machine.Start();

        Assert.Null(machine.ApplySnapshot(Guid.NewGuid(), "late"));
        machine.Cancel(machine.Generation);
        Assert.Null(machine.ApplySnapshot(machine.Generation, "late after cancel"));
        Assert.Equal(string.Empty, machine.LatestText);
        Assert.Equal(SelectionTransformState.Cancelled, machine.State);
    }

    [Fact]
    public void Cancellation_and_failure_preserve_only_the_nonempty_partial()
    {
        var cancelled = new SelectionTransformStateMachine(Guid.NewGuid());
        cancelled.Start();
        cancelled.ApplySnapshot(cancelled.Generation, "partial");
        var cancelledEvent = Assert.IsType<SelectionTransformCancelled>(cancelled.Cancel(cancelled.Generation));
        Assert.Equal("partial", cancelledEvent.PartialText);
        Assert.Equal(SelectionTransformState.PartiallyCompleted, cancelled.State);

        var failed = new SelectionTransformStateMachine(Guid.NewGuid());
        failed.Start();
        var failedEvent = Assert.IsType<SelectionTransformFailed>(failed.Fail(failed.Generation, "safe error"));
        Assert.Equal(string.Empty, failedEvent.PartialText);
        Assert.Equal(SelectionTransformState.Failed, failed.State);
    }
}
