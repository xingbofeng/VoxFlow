using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class RightControlHotkeyTests
{
    private static readonly DateTimeOffset Start =
        new(2026, 7, 10, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Right_control_requires_the_right_vk_scan_code_and_extended_flag()
    {
        Assert.True(RightControlKeyClassifier.IsRightControl(
            KeyDown(RightControlKeyClassifier.VirtualKeyRightControl, 0x1D, extended: true)));

        Assert.False(RightControlKeyClassifier.IsRightControl(
            KeyDown(RightControlKeyClassifier.VirtualKeyLeftControl, 0x1D, extended: false)));
        Assert.False(RightControlKeyClassifier.IsRightControl(
            KeyDown(RightControlKeyClassifier.VirtualKeyControl, 0x1D, extended: false)));
        Assert.False(RightControlKeyClassifier.IsRightControl(
            KeyDown(RightControlKeyClassifier.VirtualKeyRightMenu, 0x38, extended: true)));
        Assert.False(RightControlKeyClassifier.IsRightControl(
            KeyDown(RightControlKeyClassifier.VirtualKeyRightControl, 0x2A, extended: true)));
    }

    [Fact]
    public void Five_hundred_millisecond_press_starts_hold_and_release_stops_it()
    {
        var recognizer = new RightControlGestureRecognizer(TimeSpan.FromMilliseconds(500));

        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Handle(KeyDown(timestamp: Start), DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Advance(Start.AddMilliseconds(499), DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.HoldStart,
            recognizer.Advance(Start.AddMilliseconds(500), DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.HoldStop,
            recognizer.Handle(KeyUp(Start.AddMilliseconds(800)), DictationPhase.Recording));
    }

    [Theory]
    [InlineData(DictationPhase.Idle, HotkeyRouteAction.ToggleStart)]
    [InlineData(DictationPhase.Recording, HotkeyRouteAction.ToggleStop)]
    public void Short_press_toggles_recording(
        DictationPhase phase,
        HotkeyRouteAction expected)
    {
        var recognizer = new RightControlGestureRecognizer(TimeSpan.FromMilliseconds(500));

        Assert.Equal(HotkeyRouteAction.None, recognizer.Handle(KeyDown(), phase));
        Assert.Equal(
            expected,
            recognizer.Handle(KeyUp(Start.AddMilliseconds(120)), phase));
    }

    [Theory]
    [InlineData(DictationPhase.WaitingForFinal)]
    [InlineData(DictationPhase.Processing)]
    [InlineData(DictationPhase.Injecting)]
    public void Busy_processing_phases_ignore_right_control(DictationPhase phase)
    {
        var recognizer = new RightControlGestureRecognizer(TimeSpan.FromMilliseconds(500));

        Assert.Equal(
            HotkeyRouteAction.IgnoredBusy,
            recognizer.Handle(KeyDown(), phase));
        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Handle(KeyUp(Start.AddMilliseconds(100)), phase));
        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Advance(Start.AddSeconds(1), phase));
    }

    [Fact]
    public void Hold_release_while_provider_is_preparing_stops_the_pending_recording()
    {
        var recognizer = new RightControlGestureRecognizer(TimeSpan.FromMilliseconds(500));

        Assert.Equal(HotkeyRouteAction.None, recognizer.Handle(KeyDown(), DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.HoldStart,
            recognizer.Advance(Start.AddMilliseconds(500), DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.HoldStop,
            recognizer.Handle(KeyUp(Start.AddMilliseconds(650)), DictationPhase.Preparing));
    }

    [Fact]
    public void Second_short_press_while_provider_is_preparing_stops_the_pending_recording()
    {
        var recognizer = new RightControlGestureRecognizer(TimeSpan.FromMilliseconds(500));

        Assert.Equal(HotkeyRouteAction.None, recognizer.Handle(KeyDown(), DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            recognizer.Handle(KeyUp(Start.AddMilliseconds(120)), DictationPhase.Idle));

        Assert.Equal(
            HotkeyRouteAction.None,
            recognizer.Handle(
                KeyDown(timestamp: Start.AddMilliseconds(200)),
                DictationPhase.Preparing));
        Assert.Equal(
            HotkeyRouteAction.ToggleStop,
            recognizer.Handle(KeyUp(Start.AddMilliseconds(300)), DictationPhase.Preparing));
    }

    // Regression: after stop → Failed (e.g. Tencent empty-final) or Completed, the
    // snapshot stays terminal until StartAsync resets it. Right Ctrl must still
    // emit ToggleStart / HoldStart instead of permanent IgnoredBusy dead-key.
    [Theory]
    [InlineData(DictationPhase.Failed)]
    [InlineData(DictationPhase.Completed)]
    public void Short_press_after_terminal_phase_starts_new_recording(DictationPhase phase)
    {
        var recognizer = new RightControlGestureRecognizer(TimeSpan.FromMilliseconds(500));

        Assert.Equal(HotkeyRouteAction.None, recognizer.Handle(KeyDown(), phase));
        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            recognizer.Handle(KeyUp(Start.AddMilliseconds(120)), phase));
    }

    [Theory]
    [InlineData(DictationPhase.Failed)]
    [InlineData(DictationPhase.Completed)]
    public void Hold_after_terminal_phase_starts_new_recording(DictationPhase phase)
    {
        var recognizer = new RightControlGestureRecognizer(TimeSpan.FromMilliseconds(500));

        Assert.Equal(HotkeyRouteAction.None, recognizer.Handle(KeyDown(), phase));
        Assert.Equal(
            HotkeyRouteAction.HoldStart,
            recognizer.Advance(Start.AddMilliseconds(500), phase));
    }

    [Fact]
    public void Hook_install_failure_is_reported_as_user_visible_health_feedback()
    {
        var backend = new FakeKeyboardHookBackend(shouldInstall: false);
        var feedback = new CapturingHotkeyFeedbackSink();
        using var supervisor = new LowLevelKeyboardHookSupervisor(backend, feedback);

        Assert.False(supervisor.Start());
        Assert.Equal(HotkeyHealthFeedback.HookUnavailable, feedback.LastFeedback);
        Assert.False(supervisor.IsHealthy);
        Assert.Equal(1, backend.InstallCalls);
    }

    private static LowLevelKeyEvent KeyDown(
        uint virtualKey = RightControlKeyClassifier.VirtualKeyRightControl,
        uint scanCode = 0x1D,
        bool extended = true,
        DateTimeOffset? timestamp = null) => new(
            virtualKey,
            scanCode,
            extended ? LowLevelKeyFlags.Extended : LowLevelKeyFlags.None,
            KeyTransition.Down,
            timestamp ?? Start);

    private static LowLevelKeyEvent KeyUp(DateTimeOffset timestamp) => new(
        RightControlKeyClassifier.VirtualKeyRightControl,
        0x1D,
        LowLevelKeyFlags.Extended | LowLevelKeyFlags.Up,
        KeyTransition.Up,
        timestamp);

    private sealed class FakeKeyboardHookBackend(bool shouldInstall) : IKeyboardHookBackend
    {
        public int InstallCalls { get; private set; }

        public bool TryInstall()
        {
            InstallCalls++;
            return shouldInstall;
        }

        public void Dispose()
        {
        }
    }

    private sealed class CapturingHotkeyFeedbackSink : IHotkeyFeedbackSink
    {
        public HotkeyHealthFeedback? LastFeedback { get; private set; }

        public void Report(HotkeyHealthFeedback feedback) => LastFeedback = feedback;
    }
}
