using VoxFlow.Windows.Application.Sessions;

namespace VoxFlow.Windows.Application.Tests;

public sealed class SessionGenerationGateTests
{
    [Fact]
    public async Task Partial_final_and_error_callbacks_are_dropped_after_cancel()
    {
        var gate = new SessionGenerationGate();
        var generation = await gate.BeginAsync();
        List<string> accepted = [];

        Assert.True(await gate.CancelAsync(generation));

        Assert.False(await DispatchAsync(gate, generation, () => accepted.Add("partial")));
        Assert.False(await DispatchAsync(gate, generation, () => accepted.Add("final")));
        Assert.False(await DispatchAsync(gate, generation, () => accepted.Add("error")));
        Assert.Empty(accepted);
        Assert.False(gate.IsCurrent(generation));
    }

    [Fact]
    public async Task Beginning_a_new_generation_supersedes_the_previous_session()
    {
        var gate = new SessionGenerationGate();
        var first = await gate.BeginAsync();
        var second = await gate.BeginAsync();
        var accepted = 0;

        Assert.NotEqual(first, second);
        Assert.False(await DispatchAsync(gate, first, () => accepted++));
        Assert.True(await DispatchAsync(gate, second, () => accepted++));
        Assert.Equal(1, accepted);
    }

    [Fact]
    public async Task Completing_a_generation_rejects_all_later_callbacks()
    {
        var gate = new SessionGenerationGate();
        var generation = await gate.BeginAsync();

        Assert.True(await gate.CompleteAsync(generation));
        Assert.False(await DispatchAsync(gate, generation, () =>
            throw new InvalidOperationException("must not run")));
        Assert.False(await gate.CompleteAsync(generation));
    }

    [Fact]
    public async Task Stale_cancel_cannot_invalidate_the_current_generation()
    {
        var gate = new SessionGenerationGate();
        var stale = await gate.BeginAsync();
        var current = await gate.BeginAsync();
        var dispatched = false;

        Assert.False(await gate.CancelAsync(stale));
        Assert.True(gate.IsCurrent(current));
        Assert.True(await DispatchAsync(gate, current, () => dispatched = true));
        Assert.True(dispatched);
    }

    [Fact]
    public async Task Cancel_completes_only_after_an_already_accepted_callback_finishes()
    {
        var gate = new SessionGenerationGate();
        var generation = await gate.BeginAsync();
        var callbackStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseCallback = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var callbackMutatedState = false;

        var dispatch = gate.TryDispatchAsync(
            generation,
            async _ =>
            {
                callbackStarted.SetResult();
                await releaseCallback.Task;
                callbackMutatedState = true;
            }).AsTask();
        await callbackStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));

        var cancellation = gate.CancelAsync(generation).AsTask();
        Assert.False(cancellation.IsCompleted);

        releaseCallback.SetResult();

        Assert.True(await dispatch);
        Assert.True(await cancellation);
        Assert.True(callbackMutatedState);
        Assert.False(gate.IsCurrent(generation));
        Assert.False(await DispatchAsync(gate, generation, () =>
            throw new InvalidOperationException("cancelled generation must be dropped")));
    }

    private static ValueTask<bool> DispatchAsync(
        SessionGenerationGate gate,
        Guid generation,
        Action callback) => gate.TryDispatchAsync(
            generation,
            _ =>
            {
                callback();
                return ValueTask.CompletedTask;
            });
}
