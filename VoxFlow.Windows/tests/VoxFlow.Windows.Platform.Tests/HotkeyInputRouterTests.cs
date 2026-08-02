using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Platform.Input;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class HotkeyInputRouterTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 10, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Default_binding_is_right_control_and_never_treats_right_alt_altgr_as_default()
    {
        var settings = HotkeyRouteSettings.Default;
        var router = new HotkeyInputRouter(settings);

        Assert.Equal(RightControlKeyClassifier.VirtualKeyRightControl,
            settings.PrimaryBinding.VirtualKey);
        Assert.True(settings.PrimaryBinding.IsExtended);
        Assert.Equal(
            HotkeyRouteAction.None,
            router.HandleKey(
                Key(
                    RightControlKeyClassifier.VirtualKeyRightMenu,
                    scanCode: 0x38,
                    extended: true),
                HotkeyModifiers.Control | HotkeyModifiers.Alt,
                DictationPhase.Idle));
    }

    [Fact]
    public void Right_control_used_with_a_regular_key_does_not_toggle_dictation_on_release()
    {
        var router = new HotkeyInputRouter(HotkeyRouteSettings.Default);

        Assert.Equal(
            HotkeyRouteAction.None,
            router.HandleKey(
                Key(
                    RightControlKeyClassifier.VirtualKeyRightControl,
                    RightControlKeyClassifier.ControlScanCode,
                    extended: true),
                HotkeyModifiers.None,
                DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.None,
            router.HandleKey(
                Key(0x43, 0x2E),
                HotkeyModifiers.Control,
                DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.None,
            router.HandleKey(
                Key(
                    RightControlKeyClassifier.VirtualKeyRightControl,
                    RightControlKeyClassifier.ControlScanCode,
                    extended: true,
                    transition: KeyTransition.Up),
                HotkeyModifiers.None,
                DictationPhase.Idle));
    }

    [Fact]
    public void Reapplying_unchanged_live_settings_preserves_a_pending_hybrid_press()
    {
        var router = new HotkeyInputRouter(HotkeyRouteSettings.Default);

        Assert.Equal(
            HotkeyRouteAction.None,
            router.HandleKey(
                RightControl(KeyTransition.Down),
                HotkeyModifiers.None,
                DictationPhase.Idle));
        router.UpdateSettings(HotkeyRouteSettings.Default);

        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            router.HandleKey(
                RightControl(KeyTransition.Up),
                HotkeyModifiers.None,
                DictationPhase.Idle));
    }

    [Fact]
    public void Middle_mouse_routes_hold_or_toggle_according_to_the_voice_setting()
    {
        var holdRouter = new HotkeyInputRouter(
            HotkeyRouteSettings.Default with
            {
                InteractionMode = HotkeyInteractionMode.Hold,
                MiddleMouseEnabled = true,
            });
        Assert.Equal(
            HotkeyRouteAction.HoldStart,
            holdRouter.HandleMouse(MouseButton.Middle, ButtonTransition.Down, DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.HoldStop,
            holdRouter.HandleMouse(MouseButton.Middle, ButtonTransition.Up, DictationPhase.Recording));

        var toggleRouter = new HotkeyInputRouter(
            HotkeyRouteSettings.Default with
            {
                InteractionMode = HotkeyInteractionMode.Toggle,
                MiddleMouseEnabled = true,
            });
        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            toggleRouter.HandleMouse(MouseButton.Middle, ButtonTransition.Down, DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.None,
            toggleRouter.HandleMouse(MouseButton.Middle, ButtonTransition.Up, DictationPhase.Recording));
    }

    [Fact]
    public void User_recorded_alternative_combination_replaces_the_primary_binding()
    {
        var binding = new HotkeyBinding(
            VirtualKey: 0x20,
            ScanCode: 0x39,
            Modifiers: HotkeyModifiers.Control | HotkeyModifiers.Shift,
            IsExtended: false);
        var router = new HotkeyInputRouter(new HotkeyRouteSettings(
            binding,
            HotkeyInteractionMode.Toggle,
            MiddleMouseEnabled: false));

        Assert.Equal(
            HotkeyRouteAction.None,
            router.HandleKey(Key(0x20, 0x39), HotkeyModifiers.Control, DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            router.HandleKey(
                Key(0x20, 0x39),
                HotkeyModifiers.Control | HotkeyModifiers.Shift,
                DictationPhase.Idle));
    }

    [Fact]
    public void Recorder_accepts_safe_combinations_and_presents_reserved_or_altgr_conflicts()
    {
        var recorder = new HotkeyBindingRecorder();

        var accepted = recorder.Capture(
            Key(0x20, 0x39),
            HotkeyModifiers.Control | HotkeyModifiers.Shift,
            existingBindings: []);
        var windowsReserved = recorder.Capture(
            Key(0x4C, 0x26),
            HotkeyModifiers.Windows,
            existingBindings: []);
        var altGr = recorder.Capture(
            Key(RightControlKeyClassifier.VirtualKeyRightMenu, 0x38, extended: true),
            HotkeyModifiers.Control | HotkeyModifiers.Alt,
            existingBindings: []);

        Assert.Equal(HotkeyCaptureStatus.Accepted, accepted.Status);
        Assert.NotNull(accepted.Binding);
        Assert.Equal(HotkeyConflictKind.None, accepted.Conflict);
        Assert.Equal(HotkeyCaptureStatus.Conflict, windowsReserved.Status);
        Assert.Equal(HotkeyConflictKind.WindowsReserved, windowsReserved.Conflict);
        Assert.Equal("hotkey.conflict.windowsReserved", windowsReserved.MessageKey);
        Assert.Equal(HotkeyCaptureStatus.Conflict, altGr.Status);
        Assert.Equal(HotkeyConflictKind.AltGrUnsafe, altGr.Conflict);
    }

    [Fact]
    public void Disabled_middle_mouse_does_not_route()
    {
        var router = new HotkeyInputRouter(
            HotkeyRouteSettings.Default with { MiddleMouseEnabled = false });

        Assert.Equal(
            HotkeyRouteAction.None,
            router.HandleMouse(MouseButton.Middle, ButtonTransition.Down, DictationPhase.Idle));
    }

    // Mirrors the Right Ctrl hybrid path: after stop ends in Failed/Completed the
    // primary hotkey must start again (StartAsync resets the terminal snapshot).
    [Theory]
    [InlineData(DictationPhase.Failed)]
    [InlineData(DictationPhase.Completed)]
    public void Hybrid_right_control_short_press_after_terminal_phase_starts(
        DictationPhase phase)
    {
        var router = new HotkeyInputRouter(HotkeyRouteSettings.Default);

        Assert.Equal(
            HotkeyRouteAction.None,
            router.HandleKey(RightControl(KeyTransition.Down), HotkeyModifiers.None, phase));
        Assert.Equal(
            HotkeyRouteAction.ToggleStart,
            router.HandleKey(
                RightControl(KeyTransition.Up),
                HotkeyModifiers.None,
                phase));
    }

    [Theory]
    [InlineData(DictationPhase.Failed, HotkeyRouteAction.ToggleStart)]
    [InlineData(DictationPhase.Completed, HotkeyRouteAction.ToggleStart)]
    [InlineData(DictationPhase.Processing, HotkeyRouteAction.IgnoredBusy)]
    [InlineData(DictationPhase.WaitingForFinal, HotkeyRouteAction.IgnoredBusy)]
    [InlineData(DictationPhase.Preparing, HotkeyRouteAction.ToggleStop)]
    [InlineData(DictationPhase.Injecting, HotkeyRouteAction.IgnoredBusy)]
    public void Toggle_mode_terminal_phases_start_while_mid_pipeline_stays_busy(
        DictationPhase phase,
        HotkeyRouteAction expected)
    {
        var router = new HotkeyInputRouter(
            HotkeyRouteSettings.Default with { InteractionMode = HotkeyInteractionMode.Toggle });

        Assert.Equal(
            expected,
            router.HandleKey(
                RightControl(KeyTransition.Down),
                HotkeyModifiers.None,
                phase));
    }

    [Fact]
    public void Hold_mode_release_while_preparing_routes_stop()
    {
        var router = new HotkeyInputRouter(
            HotkeyRouteSettings.Default with { InteractionMode = HotkeyInteractionMode.Hold });

        Assert.Equal(
            HotkeyRouteAction.HoldStart,
            router.HandleKey(
                RightControl(KeyTransition.Down),
                HotkeyModifiers.None,
                DictationPhase.Idle));
        Assert.Equal(
            HotkeyRouteAction.HoldStop,
            router.HandleKey(
                RightControl(KeyTransition.Up),
                HotkeyModifiers.None,
                DictationPhase.Preparing));
    }

    private static LowLevelKeyEvent RightControl(KeyTransition transition) => new(
        RightControlKeyClassifier.VirtualKeyRightControl,
        RightControlKeyClassifier.ControlScanCode,
        LowLevelKeyFlags.Extended | (transition == KeyTransition.Up
            ? LowLevelKeyFlags.Up
            : LowLevelKeyFlags.None),
        transition,
        Now);

    private static LowLevelKeyEvent Key(
        uint virtualKey,
        uint scanCode,
        bool extended = false,
        KeyTransition transition = KeyTransition.Down) => new(
            virtualKey,
            scanCode,
            extended ? LowLevelKeyFlags.Extended : LowLevelKeyFlags.None,
            transition,
            Now);
}
