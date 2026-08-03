using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class ScreenshotKeyboardHookRouterTests
{
    [Fact]
    public void Overlay_consumes_only_screenshot_commands_and_keeps_key_up_paired()
    {
        var router = new ScreenshotKeyboardHookRouter();
        var received = new List<ScreenshotKeyboardCommand>();
        using var session = router.BeginSession(received.Add);

        var down = router.Route(Key(0x46, KeyTransition.Down)); // F
        Assert.True(down.Consume);
        Assert.Equal(ScreenshotKeyboardCommand.FullDisplay, down.ScreenshotCommand?.Command);
        router.Dispatch(Assert.IsType<ScreenshotKeyboardRoutedCommand>(down.ScreenshotCommand));

        var up = router.Route(Key(0x46, KeyTransition.Up));
        Assert.True(up.Consume);
        Assert.Null(up.ScreenshotCommand);
        Assert.Equal([ScreenshotKeyboardCommand.FullDisplay], received);
    }

    [Fact]
    public void Ordinary_letters_and_unowned_modifier_combinations_pass_through()
    {
        var router = new ScreenshotKeyboardHookRouter();
        using var session = router.BeginSession(_ => { });

        AssertPass(router, Key(0x41, KeyTransition.Down)); // A
        AssertPass(router, Key(0x42, KeyTransition.Down)); // B
        AssertPass(router, Key(0x20, KeyTransition.Down)); // Space outside toolbar

        AssertPass(router, Key(0xA2, KeyTransition.Down)); // Left Ctrl
        AssertPass(router, Key(0x41, KeyTransition.Down)); // Ctrl+A
        AssertPass(router, Key(0x41, KeyTransition.Up));
        AssertPass(router, Key(0xA2, KeyTransition.Up));

        AssertPass(router, Key(0xA0, KeyTransition.Down)); // Left Shift
        AssertPass(router, Key(0x46, KeyTransition.Down)); // Shift+F
        AssertPass(router, Key(0x46, KeyTransition.Up));
        AssertPass(router, Key(0xA0, KeyTransition.Up));
    }

    [Fact]
    public void Tab_shortcuts_editing_chords_and_toolbar_space_route_exact_commands()
    {
        var router = new ScreenshotKeyboardHookRouter();
        var received = new List<ScreenshotKeyboardCommand>();
        using var session = router.BeginSession(received.Add);

        Press(router, 0x09); // Tab
        Modifier(router, 0xA0, isDown: true);
        Press(router, 0x09); // Shift+Tab
        Modifier(router, 0xA0, isDown: false);
        Modifier(router, 0xA2, isDown: true);
        Press(router, 0x43); // Ctrl+C
        Press(router, 0x56); // Ctrl+V
        Press(router, 0x44); // Ctrl+D
        Press(router, 0x5A); // Ctrl+Z
        Modifier(router, 0xA0, isDown: true);
        Press(router, 0x5A); // Ctrl+Shift+Z
        Modifier(router, 0xA0, isDown: false);
        Modifier(router, 0xA2, isDown: false);
        session.SetInputMode(ScreenshotKeyboardInputMode.Toolbar);
        Press(router, 0x20); // Space

        Assert.Equal(
            [
                ScreenshotKeyboardCommand.TabForward,
                ScreenshotKeyboardCommand.TabBackward,
                ScreenshotKeyboardCommand.Copy,
                ScreenshotKeyboardCommand.Paste,
                ScreenshotKeyboardCommand.Duplicate,
                ScreenshotKeyboardCommand.Undo,
                ScreenshotKeyboardCommand.Redo,
                ScreenshotKeyboardCommand.ActivateToolbarItem,
            ],
            received);
    }

    [Fact]
    public void Text_editing_temporarily_passes_every_key_to_the_active_text_box()
    {
        var router = new ScreenshotKeyboardHookRouter();
        using var session = router.BeginSession(_ => { });
        session.SetInputMode(ScreenshotKeyboardInputMode.TextEditing);

        foreach (var virtualKey in new uint[] { 0x09, 0x46, 0x25, 0x0D, 0x1B, 0x2E, 0x08, 0x20 })
        {
            AssertPass(router, Key(virtualKey, KeyTransition.Down));
            AssertPass(router, Key(virtualKey, KeyTransition.Up));
        }

        session.SetInputMode(ScreenshotKeyboardInputMode.Overlay);
        Assert.True(router.Route(Key(0x1B, KeyTransition.Down)).Consume);
    }

    [Fact]
    public void Session_lifecycle_ignores_stale_dispatch_and_stale_session_mutation()
    {
        var router = new ScreenshotKeyboardHookRouter();
        var firstReceived = new List<ScreenshotKeyboardCommand>();
        var first = router.BeginSession(firstReceived.Add);
        var stale = Assert.IsType<ScreenshotKeyboardRoutedCommand>(
            router.Route(Key(0x46, KeyTransition.Down)).ScreenshotCommand);
        first.Dispose();

        var secondReceived = new List<ScreenshotKeyboardCommand>();
        using var second = router.BeginSession(secondReceived.Add);
        router.Dispatch(stale);
        Assert.Empty(firstReceived);
        Assert.Empty(secondReceived);

        // The release for a swallowed key remains swallowed even across session turnover.
        var staleRelease = router.Route(Key(0x46, KeyTransition.Up));
        Assert.True(staleRelease.Consume);
        Assert.Null(staleRelease.ScreenshotCommand);

        Press(router, 0x46);
        Assert.Equal([ScreenshotKeyboardCommand.FullDisplay], secondReceived);
        second.Dispose();
        AssertPass(router, Key(0x46, KeyTransition.Down));
    }

    [Fact]
    public void A_second_session_cannot_steal_the_single_hook_route_owner()
    {
        var router = new ScreenshotKeyboardHookRouter();
        using var session = router.BeginSession(_ => { });

        Assert.Throws<InvalidOperationException>(() => router.BeginSession(_ => { }));
    }

    private static void Press(ScreenshotKeyboardHookRouter router, uint virtualKey)
    {
        var down = router.Route(Key(virtualKey, KeyTransition.Down));
        Assert.True(down.Consume);
        router.Dispatch(Assert.IsType<ScreenshotKeyboardRoutedCommand>(down.ScreenshotCommand));
        var up = router.Route(Key(virtualKey, KeyTransition.Up));
        Assert.True(up.Consume);
        Assert.Null(up.ScreenshotCommand);
    }

    private static void Modifier(
        ScreenshotKeyboardHookRouter router,
        uint virtualKey,
        bool isDown) => AssertPass(
            router,
            Key(virtualKey, isDown ? KeyTransition.Down : KeyTransition.Up));

    private static void AssertPass(
        ScreenshotKeyboardHookRouter router,
        LowLevelKeyEvent keyEvent)
    {
        var decision = router.Route(keyEvent);
        Assert.False(decision.Consume);
        Assert.Null(decision.ScreenshotCommand);
    }

    private static LowLevelKeyEvent Key(uint virtualKey, KeyTransition transition) => new(
        virtualKey,
        ScanCode: 0,
        LowLevelKeyFlags.None,
        transition,
        DateTimeOffset.UnixEpoch);
}
