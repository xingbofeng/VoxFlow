namespace VoxFlow.Windows.Platform.Input;

public sealed record InteractiveHotkeyRouteEvent(
    InteractiveHotkeyAction Action,
    KeyTransition Transition,
    DateTimeOffset Timestamp);

/// <summary>
/// Converts the low-level keyboard stream into one unique workflow event.
/// The hook thread only enqueues raw events; this state machine runs on the
/// existing asynchronous input pump.
/// </summary>
public sealed class InteractiveHotkeyRoute
{
    private static readonly IReadOnlySet<uint> ControlKeys =
        new HashSet<uint> { 0x11, 0xA2, 0xA3 };
    private static readonly IReadOnlySet<uint> ShiftKeys =
        new HashSet<uint> { 0x10, 0xA0, 0xA1 };
    private static readonly IReadOnlySet<uint> AltKeys =
        new HashSet<uint> { 0x12, 0xA4, 0xA5 };
    private static readonly IReadOnlySet<uint> WindowsKeys =
        new HashSet<uint> { 0x5B, 0x5C };

    private InteractiveHotkeyBindingSet bindings;
    private readonly HashSet<uint> pressedModifiers = [];
    private readonly HashSet<uint> pressedKeys = [];
    private readonly Dictionary<uint, InteractiveHotkeyAction> activeActions = [];

    public InteractiveHotkeyRoute(InteractiveHotkeyBindingSet bindings)
    {
        this.bindings = bindings
            ?? throw new ArgumentNullException(nameof(bindings));
    }

    public void UpdateBindings(InteractiveHotkeyBindingSet updatedBindings)
    {
        bindings = updatedBindings
            ?? throw new ArgumentNullException(nameof(updatedBindings));
        pressedModifiers.Clear();
        pressedKeys.Clear();
        activeActions.Clear();
    }

    public InteractiveHotkeyRouteEvent? Handle(LowLevelKeyEvent keyEvent)
    {
        ArgumentNullException.ThrowIfNull(keyEvent);
        if (IsModifier(keyEvent.VirtualKey))
        {
            if (keyEvent.Transition == KeyTransition.Down)
            {
                pressedModifiers.Add(keyEvent.VirtualKey);
            }
            else
            {
                pressedModifiers.Remove(keyEvent.VirtualKey);
            }
            return null;
        }

        if (keyEvent.Transition == KeyTransition.Up)
        {
            if (!pressedKeys.Remove(keyEvent.VirtualKey)
                || !activeActions.Remove(keyEvent.VirtualKey, out var activeAction))
            {
                return null;
            }
            return new InteractiveHotkeyRouteEvent(
                activeAction,
                KeyTransition.Up,
                keyEvent.Timestamp);
        }

        if (!pressedKeys.Add(keyEvent.VirtualKey))
        {
            return null;
        }

        var modifiers = CurrentModifiers();
        if (pressedModifiers.Contains(RightControlKeyClassifier.VirtualKeyRightMenu))
        {
            return null;
        }
        foreach (var action in Enum.GetValues<InteractiveHotkeyAction>())
        {
            if (bindings.Get(action) is { } binding
                && binding.Matches(keyEvent, modifiers))
            {
                activeActions.Add(keyEvent.VirtualKey, action);
                return new InteractiveHotkeyRouteEvent(
                    action,
                    KeyTransition.Down,
                    keyEvent.Timestamp);
            }
        }
        return null;
    }

    private HotkeyModifiers CurrentModifiers()
    {
        var value = HotkeyModifiers.None;
        if (pressedModifiers.Overlaps(ControlKeys))
        {
            value |= HotkeyModifiers.Control;
        }
        if (pressedModifiers.Overlaps(ShiftKeys))
        {
            value |= HotkeyModifiers.Shift;
        }
        if (pressedModifiers.Overlaps(AltKeys))
        {
            value |= HotkeyModifiers.Alt;
        }
        if (pressedModifiers.Overlaps(WindowsKeys))
        {
            value |= HotkeyModifiers.Windows;
        }
        return value;
    }

    private static bool IsModifier(uint virtualKey) =>
        ControlKeys.Contains(virtualKey)
        || ShiftKeys.Contains(virtualKey)
        || AltKeys.Contains(virtualKey)
        || WindowsKeys.Contains(virtualKey);
}
