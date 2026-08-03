using VoxFlow.Windows.Application.Dictation;

namespace VoxFlow.Windows.Platform.Input;

[Flags]
public enum LowLevelKeyFlags : uint
{
    None = 0,
    Extended = 0x01,
    Injected = 0x10,
    AltDown = 0x20,
    Up = 0x80,
}

public enum KeyTransition
{
    Down,
    Up,
}

public sealed record LowLevelKeyEvent(
    uint VirtualKey,
    uint ScanCode,
    LowLevelKeyFlags Flags,
    KeyTransition Transition,
    DateTimeOffset Timestamp);

public static class RightControlKeyClassifier
{
    public const uint VirtualKeyControl = 0x11;
    public const uint VirtualKeyLeftControl = 0xA2;
    public const uint VirtualKeyRightControl = 0xA3;
    public const uint VirtualKeyRightMenu = 0xA5;
    public const uint ControlScanCode = 0x1D;

    public static bool IsRightControl(LowLevelKeyEvent keyEvent)
    {
        ArgumentNullException.ThrowIfNull(keyEvent);
        return keyEvent.VirtualKey == VirtualKeyRightControl
            && keyEvent.ScanCode == ControlScanCode
            && keyEvent.Flags.HasFlag(LowLevelKeyFlags.Extended);
    }
}

public enum HotkeyRouteAction
{
    None,
    ToggleStart,
    ToggleStop,
    HoldStart,
    HoldStop,
    Cancel,
    IgnoredBusy,
}

public sealed class RightControlGestureRecognizer
{
    private readonly TimeSpan holdThreshold;
    private bool isPressed;
    private bool isSuppressedUntilRelease;
    private bool holdStarted;
    private DateTimeOffset pressedAt;

    public RightControlGestureRecognizer(TimeSpan holdThreshold)
    {
        if (holdThreshold <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(holdThreshold));
        }

        this.holdThreshold = holdThreshold;
    }

    public HotkeyRouteAction Handle(
        LowLevelKeyEvent keyEvent,
        DictationPhase phase)
    {
        ArgumentNullException.ThrowIfNull(keyEvent);
        if (!RightControlKeyClassifier.IsRightControl(keyEvent))
        {
            return HotkeyRouteAction.None;
        }

        return keyEvent.Transition switch
        {
            KeyTransition.Down => HandleDown(keyEvent.Timestamp, phase),
            KeyTransition.Up => HandleUp(phase),
            _ => throw new ArgumentOutOfRangeException(nameof(keyEvent), keyEvent.Transition, null),
        };
    }

    public HotkeyRouteAction Advance(DateTimeOffset timestamp, DictationPhase phase)
    {
        if (!isPressed || isSuppressedUntilRelease || holdStarted)
        {
            return HotkeyRouteAction.None;
        }

        if (timestamp < pressedAt + holdThreshold)
        {
            return HotkeyRouteAction.None;
        }

        // Terminal phases (Completed/Failed) are idle-for-start: a held Right Ctrl
        // after empty-final / failure must be able to begin a new session.
        if (!IsStartable(phase))
        {
            return HotkeyRouteAction.None;
        }

        holdStarted = true;
        return HotkeyRouteAction.HoldStart;
    }

    public void SuppressPendingChord()
    {
        if (!isPressed || holdStarted)
        {
            return;
        }

        isPressed = false;
        holdStarted = false;
        isSuppressedUntilRelease = true;
    }

    public void Reset()
    {
        isPressed = false;
        isSuppressedUntilRelease = false;
        holdStarted = false;
        pressedAt = default;
    }

    private HotkeyRouteAction HandleDown(DateTimeOffset timestamp, DictationPhase phase)
    {
        if (isPressed || isSuppressedUntilRelease)
        {
            return HotkeyRouteAction.None;
        }

        // Only mid-pipeline phases are busy. Terminal Completed/Failed leave the
        // snapshot non-Idle until StartAsync resets it, so treat them as startable.
        if (phase is not (
            DictationPhase.Idle or
            DictationPhase.Preparing or
            DictationPhase.Recording or
            DictationPhase.Completed or
            DictationPhase.Failed))
        {
            isSuppressedUntilRelease = true;
            return HotkeyRouteAction.IgnoredBusy;
        }

        isPressed = true;
        holdStarted = false;
        pressedAt = timestamp;
        return HotkeyRouteAction.None;
    }

    private HotkeyRouteAction HandleUp(DictationPhase phase)
    {
        if (isSuppressedUntilRelease)
        {
            isSuppressedUntilRelease = false;
            isPressed = false;
            holdStarted = false;
            return HotkeyRouteAction.None;
        }

        if (!isPressed)
        {
            return HotkeyRouteAction.None;
        }

        isPressed = false;
        if (holdStarted)
        {
            holdStarted = false;
            return phase is DictationPhase.Preparing or DictationPhase.Recording
                ? HotkeyRouteAction.HoldStop
                : HotkeyRouteAction.None;
        }

        return phase switch
        {
            DictationPhase.Idle or DictationPhase.Completed or DictationPhase.Failed
                => HotkeyRouteAction.ToggleStart,
            DictationPhase.Preparing or DictationPhase.Recording
                => HotkeyRouteAction.ToggleStop,
            _ => HotkeyRouteAction.IgnoredBusy,
        };
    }

    private static bool IsStartable(DictationPhase phase) =>
        phase is DictationPhase.Idle or DictationPhase.Completed or DictationPhase.Failed;
}
