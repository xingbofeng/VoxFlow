using VoxFlow.Windows.Application.Dictation;

namespace VoxFlow.Windows.Platform.Input;

[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Control = 1 << 0,
    Shift = 1 << 1,
    Alt = 1 << 2,
    Windows = 1 << 3,
}

public sealed record HotkeyBinding(
    uint VirtualKey,
    uint ScanCode,
    HotkeyModifiers Modifiers,
    bool IsExtended)
{
    public static HotkeyBinding RightControlDefault { get; } = new(
        RightControlKeyClassifier.VirtualKeyRightControl,
        RightControlKeyClassifier.ControlScanCode,
        HotkeyModifiers.None,
        IsExtended: true);

    public bool Matches(LowLevelKeyEvent keyEvent, HotkeyModifiers modifiers) =>
        keyEvent.VirtualKey == VirtualKey
        && keyEvent.ScanCode == ScanCode
        && keyEvent.Flags.HasFlag(LowLevelKeyFlags.Extended) == IsExtended
        && modifiers == Modifiers;
}

public enum HotkeyInteractionMode
{
    Hybrid,
    Hold,
    Toggle,
}

public sealed record HotkeyRouteSettings(
    HotkeyBinding PrimaryBinding,
    HotkeyInteractionMode InteractionMode,
    bool MiddleMouseEnabled)
{
    public static HotkeyRouteSettings Default { get; } = new(
        HotkeyBinding.RightControlDefault,
        HotkeyInteractionMode.Hybrid,
        MiddleMouseEnabled: false);
}

public enum MouseButton
{
    Left,
    Right,
    Middle,
}

public enum ButtonTransition
{
    Down,
    Up,
}

public sealed class HotkeyInputRouter
{
    private readonly HotkeyRouteSettings settings;
    private readonly RightControlGestureRecognizer hybridRecognizer = new(
        TimeSpan.FromMilliseconds(500));

    public HotkeyInputRouter(HotkeyRouteSettings settings)
    {
        this.settings = settings ?? throw new ArgumentNullException(nameof(settings));
    }

    public HotkeyRouteAction HandleKey(
        LowLevelKeyEvent keyEvent,
        HotkeyModifiers modifiers,
        DictationPhase phase)
    {
        ArgumentNullException.ThrowIfNull(keyEvent);
        if (!settings.PrimaryBinding.Matches(keyEvent, modifiers))
        {
            return HotkeyRouteAction.None;
        }

        if (settings.InteractionMode == HotkeyInteractionMode.Hybrid
            && settings.PrimaryBinding == HotkeyBinding.RightControlDefault)
        {
            return hybridRecognizer.Handle(keyEvent, phase);
        }

        return settings.InteractionMode switch
        {
            HotkeyInteractionMode.Hold => RouteHold(keyEvent.Transition, phase),
            HotkeyInteractionMode.Toggle => RouteToggle(keyEvent.Transition, phase),
            HotkeyInteractionMode.Hybrid => RouteToggle(keyEvent.Transition, phase),
            _ => throw new ArgumentOutOfRangeException(),
        };
    }

    public HotkeyRouteAction AdvanceHybrid(
        DateTimeOffset timestamp,
        DictationPhase phase) => settings.InteractionMode == HotkeyInteractionMode.Hybrid
            ? hybridRecognizer.Advance(timestamp, phase)
            : HotkeyRouteAction.None;

    public HotkeyRouteAction HandleMouse(
        MouseButton button,
        ButtonTransition transition,
        DictationPhase phase)
    {
        if (!settings.MiddleMouseEnabled || button != MouseButton.Middle)
        {
            return HotkeyRouteAction.None;
        }

        return settings.InteractionMode switch
        {
            HotkeyInteractionMode.Hold => RouteHold(
                transition == ButtonTransition.Down ? KeyTransition.Down : KeyTransition.Up,
                phase),
            HotkeyInteractionMode.Toggle or HotkeyInteractionMode.Hybrid => RouteToggle(
                transition == ButtonTransition.Down ? KeyTransition.Down : KeyTransition.Up,
                phase),
            _ => throw new ArgumentOutOfRangeException(),
        };
    }

    private static HotkeyRouteAction RouteHold(
        KeyTransition transition,
        DictationPhase phase)
    {
        if (transition == KeyTransition.Up)
        {
            return phase == DictationPhase.Recording
                ? HotkeyRouteAction.HoldStop
                : HotkeyRouteAction.None;
        }

        return phase switch
        {
            DictationPhase.Idle => HotkeyRouteAction.HoldStart,
            DictationPhase.Recording => HotkeyRouteAction.None,
            _ => HotkeyRouteAction.IgnoredBusy,
        };
    }

    private static HotkeyRouteAction RouteToggle(
        KeyTransition transition,
        DictationPhase phase)
    {
        if (transition == KeyTransition.Up)
        {
            return HotkeyRouteAction.None;
        }

        return phase switch
        {
            DictationPhase.Idle => HotkeyRouteAction.ToggleStart,
            DictationPhase.Recording => HotkeyRouteAction.ToggleStop,
            _ => HotkeyRouteAction.IgnoredBusy,
        };
    }
}

public enum HotkeyCaptureStatus
{
    Pending,
    Accepted,
    Conflict,
}

public enum HotkeyConflictKind
{
    None,
    ModifierOnly,
    WindowsReserved,
    AltGrUnsafe,
    AlreadyAssigned,
}

public sealed record HotkeyCaptureResult(
    HotkeyCaptureStatus Status,
    HotkeyBinding? Binding,
    HotkeyConflictKind Conflict,
    string? MessageKey);

public sealed class HotkeyBindingRecorder
{
    private static readonly IReadOnlySet<uint> WindowsReservedKeys = new HashSet<uint>
    {
        0x09, // Tab
        0x44, // D
        0x45, // E
        0x4C, // L
        0x52, // R
    };

    private static readonly IReadOnlySet<uint> ModifierKeys = new HashSet<uint>
    {
        0x10,
        0x11,
        0x12,
        0x5B,
        0x5C,
        0xA0,
        0xA1,
        0xA2,
        0xA4,
    };

    public HotkeyCaptureResult Capture(
        LowLevelKeyEvent keyEvent,
        HotkeyModifiers modifiers,
        IReadOnlyCollection<HotkeyBinding> existingBindings)
    {
        ArgumentNullException.ThrowIfNull(keyEvent);
        ArgumentNullException.ThrowIfNull(existingBindings);
        if (keyEvent.Transition != KeyTransition.Down)
        {
            return Pending();
        }

        if (keyEvent.VirtualKey == RightControlKeyClassifier.VirtualKeyRightMenu)
        {
            return Conflict(
                HotkeyConflictKind.AltGrUnsafe,
                "hotkey.conflict.altGrUnsafe");
        }

        if (ModifierKeys.Contains(keyEvent.VirtualKey)
            && !RightControlKeyClassifier.IsRightControl(keyEvent))
        {
            return Conflict(
                HotkeyConflictKind.ModifierOnly,
                "hotkey.conflict.modifierOnly");
        }

        if (modifiers.HasFlag(HotkeyModifiers.Windows)
            && WindowsReservedKeys.Contains(keyEvent.VirtualKey))
        {
            return Conflict(
                HotkeyConflictKind.WindowsReserved,
                "hotkey.conflict.windowsReserved");
        }

        var binding = new HotkeyBinding(
            keyEvent.VirtualKey,
            keyEvent.ScanCode,
            RightControlKeyClassifier.IsRightControl(keyEvent)
                ? HotkeyModifiers.None
                : modifiers,
            keyEvent.Flags.HasFlag(LowLevelKeyFlags.Extended));
        if (existingBindings.Contains(binding))
        {
            return Conflict(
                HotkeyConflictKind.AlreadyAssigned,
                "hotkey.conflict.alreadyAssigned");
        }

        return new HotkeyCaptureResult(
            HotkeyCaptureStatus.Accepted,
            binding,
            HotkeyConflictKind.None,
            MessageKey: null);
    }

    private static HotkeyCaptureResult Pending() => new(
        HotkeyCaptureStatus.Pending,
        Binding: null,
        HotkeyConflictKind.None,
        MessageKey: null);

    private static HotkeyCaptureResult Conflict(
        HotkeyConflictKind kind,
        string messageKey) => new(
            HotkeyCaptureStatus.Conflict,
            Binding: null,
            kind,
            messageKey);
}
