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

    private static LowLevelKeyEvent Key(
        uint virtualKey,
        uint scanCode,
        bool extended = false) => new(
            virtualKey,
            scanCode,
            extended ? LowLevelKeyFlags.Extended : LowLevelKeyFlags.None,
            KeyTransition.Down,
            Now);
}
