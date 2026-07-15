using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class LowLevelKeyboardEventDispatcherTests
{
    [Fact]
    public async Task Hook_side_post_only_enqueues_and_consumer_runs_off_the_posting_thread()
    {
        var callbackStarted = new TaskCompletionSource<int>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        using var releaseCallback = new ManualResetEventSlim(false);
        using var posterIsBlocked = new ManualResetEventSlim(false);
        using var releasePoster = new ManualResetEventSlim(false);
        using var dispatcher = new LowLevelKeyboardEventDispatcher(dispatch =>
        {
            _ = dispatch.KeyEvent;
            callbackStarted.TrySetResult(Environment.CurrentManagedThreadId);
            releaseCallback.Wait(TimeSpan.FromSeconds(5));
        });
        var postingThread = 0;
        var firstPostAccepted = false;
        var poster = new Thread(() =>
        {
            postingThread = Environment.CurrentManagedThreadId;
            firstPostAccepted = dispatcher.TryPost(Key(KeyTransition.Down));
            posterIsBlocked.Set();
            releasePoster.Wait(TimeSpan.FromSeconds(5));
        });
        poster.Start();
        Assert.True(posterIsBlocked.Wait(TimeSpan.FromSeconds(5)));
        var callbackThread = await callbackStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.True(firstPostAccepted);
        Assert.NotEqual(postingThread, callbackThread);

        Assert.True(dispatcher.TryPost(Key(KeyTransition.Up)));
        releaseCallback.Set();
        releasePoster.Set();
        Assert.True(poster.Join(TimeSpan.FromSeconds(5)));
    }

    [Fact]
    public async Task Routed_screenshot_command_survives_the_existing_async_dispatch_pump()
    {
        var delivered = new TaskCompletionSource<LowLevelKeyboardDispatch>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        using var dispatcher = new LowLevelKeyboardEventDispatcher(
            (LowLevelKeyboardDispatch dispatch) => delivered.TrySetResult(dispatch));
        var command = new ScreenshotKeyboardRoutedCommand(
            SessionId: 7,
            ScreenshotKeyboardCommand.Escape);
        var expected = new LowLevelKeyboardDispatch(
            Key(KeyTransition.Down),
            Consumed: true,
            command);

        Assert.True(dispatcher.TryPost(expected));

        Assert.Equal(
            expected,
            await delivered.Task.WaitAsync(TimeSpan.FromSeconds(5)));
    }

    private static LowLevelKeyEvent Key(KeyTransition transition) => new(
        0x41,
        0x1E,
        LowLevelKeyFlags.None,
        transition,
        DateTimeOffset.UnixEpoch);
}
