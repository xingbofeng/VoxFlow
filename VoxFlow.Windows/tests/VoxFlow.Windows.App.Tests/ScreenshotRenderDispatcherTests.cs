using VoxFlow.Windows.App.Screenshot;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class ScreenshotRenderDispatcherTests
{
    [Fact]
    public async Task Render_work_runs_on_a_dedicated_sta_without_blocking_the_ui_continuation()
    {
        await StaWpfTestHost.RunAsync(async context =>
        {
            Assert.Equal(ApartmentState.STA, context.ApartmentState);
            var uiThreadId = Environment.CurrentManagedThreadId;
            using var dispatcher = new ScreenshotStaRenderDispatcher();
            using var release = new ManualResetEventSlim();
            var started = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var workerThreadId = 0;
            var workerApartment = ApartmentState.Unknown;

            var pending = dispatcher.InvokeAsync(() =>
            {
                workerThreadId = Environment.CurrentManagedThreadId;
                workerApartment = Thread.CurrentThread.GetApartmentState();
                started.TrySetResult();
                release.Wait(TimeSpan.FromSeconds(5));
                return 42;
            });

            await started.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Assert.Equal(uiThreadId, Environment.CurrentManagedThreadId);
            Assert.False(pending.IsCompleted);
            Assert.NotEqual(uiThreadId, workerThreadId);
            Assert.Equal(ApartmentState.STA, workerApartment);

            release.Set();
            Assert.Equal(42, await pending.WaitAsync(TimeSpan.FromSeconds(2)));
        });
    }

    [Fact]
    public async Task Cancelled_queued_render_is_not_executed_or_published()
    {
        using var dispatcher = new ScreenshotStaRenderDispatcher();
        using var release = new ManualResetEventSlim();
        var started = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var first = dispatcher.InvokeAsync(() =>
        {
            started.TrySetResult();
            release.Wait(TimeSpan.FromSeconds(5));
            return true;
        });
        await started.Task.WaitAsync(TimeSpan.FromSeconds(2));

        using var cancellation = new CancellationTokenSource();
        var secondExecuted = false;
        var second = dispatcher.InvokeAsync(() =>
        {
            secondExecuted = true;
            return true;
        }, cancellation.Token);

        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await second.WaitAsync(TimeSpan.FromSeconds(2)));
        release.Set();
        Assert.True(await first.WaitAsync(TimeSpan.FromSeconds(2)));
        Assert.True(await dispatcher.InvokeAsync(() => true).WaitAsync(TimeSpan.FromSeconds(2)));
        Assert.False(secondExecuted);
    }
}
