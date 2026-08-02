using VoxFlow.Windows.Application.Dictation;

namespace VoxFlow.Windows.Platform.Input;

public sealed class AgentChordGestureRecognizer
{
    private readonly TimeSpan holdThreshold;
    private bool isPressed;
    private bool isSuppressedUntilRelease;
    private bool holdStarted;
    private DateTimeOffset pressedAt;

    public AgentChordGestureRecognizer(TimeSpan holdThreshold)
    {
        if (holdThreshold <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(holdThreshold));
        }
        this.holdThreshold = holdThreshold;
    }

    public HotkeyRouteAction Handle(
        InteractiveHotkeyRouteEvent routeEvent,
        DictationPhase phase)
    {
        ArgumentNullException.ThrowIfNull(routeEvent);
        if (routeEvent.Action != InteractiveHotkeyAction.AgentCompose)
        {
            return HotkeyRouteAction.None;
        }

        return routeEvent.Transition switch
        {
            KeyTransition.Down => HandleDown(routeEvent.Timestamp, phase),
            KeyTransition.Up => HandleUp(phase),
            _ => throw new ArgumentOutOfRangeException(
                nameof(routeEvent),
                routeEvent.Transition,
                null),
        };
    }

    public HotkeyRouteAction Advance(
        DateTimeOffset timestamp,
        DictationPhase phase)
    {
        if (!isPressed || isSuppressedUntilRelease || holdStarted)
        {
            return HotkeyRouteAction.None;
        }
        // Terminal Completed/Failed are idle-for-start after a prior session ends.
        if (timestamp < pressedAt + holdThreshold
            || phase is not (
                DictationPhase.Idle or
                DictationPhase.Completed or
                DictationPhase.Failed))
        {
            return HotkeyRouteAction.None;
        }

        holdStarted = true;
        return HotkeyRouteAction.HoldStart;
    }

    public void NotifyForegroundChanged()
    {
        // The target is frozen by the workflow entry point. Foreground changes
        // while the chord is held must not discard the matching A-key release.
    }

    private HotkeyRouteAction HandleDown(
        DateTimeOffset timestamp,
        DictationPhase phase)
    {
        if (isPressed || isSuppressedUntilRelease)
        {
            return HotkeyRouteAction.None;
        }
        if (phase is not (
            DictationPhase.Idle or
            DictationPhase.Recording or
            DictationPhase.Completed or
            DictationPhase.Failed))
        {
            // A subsequent Agent chord while final ASR, context collection or
            // sidecar work is active is an explicit cancellation gesture. It
            // is deliberately emitted on key-down so a stalled operation does
            // not wait for a matching key-up event.
            return HotkeyRouteAction.Cancel;
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
            return phase == DictationPhase.Recording
                ? HotkeyRouteAction.HoldStop
                : HotkeyRouteAction.None;
        }
        return phase switch
        {
            DictationPhase.Idle or DictationPhase.Completed or DictationPhase.Failed
                => HotkeyRouteAction.ToggleStart,
            DictationPhase.Recording => HotkeyRouteAction.ToggleStop,
            _ => HotkeyRouteAction.IgnoredBusy,
        };
    }
}
