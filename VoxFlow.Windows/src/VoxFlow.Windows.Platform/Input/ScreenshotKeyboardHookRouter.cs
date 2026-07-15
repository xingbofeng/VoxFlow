namespace VoxFlow.Windows.Platform.Input;

public enum ScreenshotKeyboardCommand
{
    TabForward,
    TabBackward,
    FocusToolbar,
    ActivateToolbarItem,
    FullDisplay,
    MoveLeft,
    MoveRight,
    MoveUp,
    MoveDown,
    Complete,
    Escape,
    Delete,
    Backspace,
    Copy,
    Paste,
    Duplicate,
    Undo,
    Redo,
}

public enum ScreenshotKeyboardInputMode
{
    Overlay,
    Toolbar,
    TextEditing,
}

public sealed record ScreenshotKeyboardRoutedCommand(
    long SessionId,
    ScreenshotKeyboardCommand Command);

public readonly record struct LowLevelKeyboardRoutingDecision(
    bool Consume,
    ScreenshotKeyboardRoutedCommand? ScreenshotCommand)
{
    public static LowLevelKeyboardRoutingDecision PassThrough { get; } = new(
        Consume: false,
        ScreenshotCommand: null);
}

public sealed record LowLevelKeyboardDispatch(
    LowLevelKeyEvent KeyEvent,
    bool Consumed,
    ScreenshotKeyboardRoutedCommand? ScreenshotCommand);

/// <summary>
/// Synchronously classifies the small keyboard surface owned by an active screenshot overlay.
/// Native hook work stays bounded to this state machine; the routed command is delivered later
/// by the hook's existing asynchronous dispatcher.
/// </summary>
public sealed class ScreenshotKeyboardHookRouter
{
    private static readonly IReadOnlySet<uint> ControlKeys =
        new HashSet<uint> { 0x11, 0xA2, 0xA3 };
    private static readonly IReadOnlySet<uint> ShiftKeys =
        new HashSet<uint> { 0x10, 0xA0, 0xA1 };
    private static readonly IReadOnlySet<uint> AltKeys =
        new HashSet<uint> { 0x12, 0xA4, 0xA5 };
    private static readonly IReadOnlySet<uint> WindowsKeys =
        new HashSet<uint> { 0x5B, 0x5C };

    private readonly object syncRoot = new();
    private readonly HashSet<uint> pressedModifiers = [];
    private readonly HashSet<uint> suppressedKeys = [];
    private Action<ScreenshotKeyboardCommand>? commandHandler;
    private ScreenshotKeyboardInputMode inputMode;
    private long nextSessionId;
    private long activeSessionId;

    public ScreenshotKeyboardHookSession BeginSession(
        Action<ScreenshotKeyboardCommand> handler)
    {
        ArgumentNullException.ThrowIfNull(handler);
        lock (syncRoot)
        {
            if (activeSessionId != 0)
            {
                throw new InvalidOperationException(
                    "A screenshot keyboard hook session is already active.");
            }
            activeSessionId = checked(++nextSessionId);
            commandHandler = handler;
            inputMode = ScreenshotKeyboardInputMode.Overlay;
            return new ScreenshotKeyboardHookSession(this, activeSessionId);
        }
    }

    public LowLevelKeyboardRoutingDecision Route(LowLevelKeyEvent keyEvent)
    {
        ArgumentNullException.ThrowIfNull(keyEvent);
        lock (syncRoot)
        {
            UpdateModifiers(keyEvent);
            if (keyEvent.Transition == KeyTransition.Up
                && suppressedKeys.Remove(keyEvent.VirtualKey))
            {
                return new LowLevelKeyboardRoutingDecision(
                    Consume: true,
                    ScreenshotCommand: null);
            }
            if (keyEvent.Transition != KeyTransition.Down
                || activeSessionId == 0
                || inputMode == ScreenshotKeyboardInputMode.TextEditing
                || IsModifier(keyEvent.VirtualKey)
                || !TryResolveCommand(
                    keyEvent.VirtualKey,
                    CurrentModifiers(),
                    inputMode,
                    out var command))
            {
                return LowLevelKeyboardRoutingDecision.PassThrough;
            }

            suppressedKeys.Add(keyEvent.VirtualKey);
            return new LowLevelKeyboardRoutingDecision(
                Consume: true,
                new ScreenshotKeyboardRoutedCommand(activeSessionId, command));
        }
    }

    public void Dispatch(ScreenshotKeyboardRoutedCommand routedCommand)
    {
        ArgumentNullException.ThrowIfNull(routedCommand);
        Action<ScreenshotKeyboardCommand>? handler;
        lock (syncRoot)
        {
            handler = routedCommand.SessionId == activeSessionId
                ? commandHandler
                : null;
        }
        handler?.Invoke(routedCommand.Command);
    }

    private void SetInputMode(long sessionId, ScreenshotKeyboardInputMode mode)
    {
        if (!Enum.IsDefined(mode))
        {
            throw new ArgumentOutOfRangeException(nameof(mode));
        }
        lock (syncRoot)
        {
            if (sessionId == activeSessionId)
            {
                inputMode = mode;
            }
        }
    }

    private void EndSession(long sessionId)
    {
        lock (syncRoot)
        {
            if (sessionId != activeSessionId)
            {
                return;
            }
            activeSessionId = 0;
            commandHandler = null;
            inputMode = ScreenshotKeyboardInputMode.Overlay;
        }
    }

    private void UpdateModifiers(LowLevelKeyEvent keyEvent)
    {
        if (!IsModifier(keyEvent.VirtualKey))
        {
            return;
        }
        if (keyEvent.Transition == KeyTransition.Down)
        {
            pressedModifiers.Add(keyEvent.VirtualKey);
        }
        else
        {
            pressedModifiers.Remove(keyEvent.VirtualKey);
        }
    }

    private HotkeyModifiers CurrentModifiers()
    {
        var modifiers = HotkeyModifiers.None;
        if (pressedModifiers.Overlaps(ControlKeys))
        {
            modifiers |= HotkeyModifiers.Control;
        }
        if (pressedModifiers.Overlaps(ShiftKeys))
        {
            modifiers |= HotkeyModifiers.Shift;
        }
        if (pressedModifiers.Overlaps(AltKeys))
        {
            modifiers |= HotkeyModifiers.Alt;
        }
        if (pressedModifiers.Overlaps(WindowsKeys))
        {
            modifiers |= HotkeyModifiers.Windows;
        }
        return modifiers;
    }

    private static bool TryResolveCommand(
        uint virtualKey,
        HotkeyModifiers modifiers,
        ScreenshotKeyboardInputMode mode,
        out ScreenshotKeyboardCommand command)
    {
        command = default;
        if (modifiers == HotkeyModifiers.Control)
        {
            command = virtualKey switch
            {
                0x43 => ScreenshotKeyboardCommand.Copy,
                0x56 => ScreenshotKeyboardCommand.Paste,
                0x44 => ScreenshotKeyboardCommand.Duplicate,
                0x5A => ScreenshotKeyboardCommand.Undo,
                0x59 => ScreenshotKeyboardCommand.Redo,
                _ => default,
            };
            return virtualKey is 0x43 or 0x56 or 0x44 or 0x5A or 0x59;
        }
        if (modifiers == (HotkeyModifiers.Control | HotkeyModifiers.Shift)
            && virtualKey == 0x5A)
        {
            command = ScreenshotKeyboardCommand.Redo;
            return true;
        }
        if (virtualKey == 0x09
            && modifiers is HotkeyModifiers.None or HotkeyModifiers.Shift)
        {
            command = modifiers == HotkeyModifiers.Shift
                ? ScreenshotKeyboardCommand.TabBackward
                : ScreenshotKeyboardCommand.TabForward;
            return true;
        }
        if (modifiers != HotkeyModifiers.None)
        {
            return false;
        }

        command = virtualKey switch
        {
            0x75 => ScreenshotKeyboardCommand.FocusToolbar, // F6
            0x20 when mode == ScreenshotKeyboardInputMode.Toolbar =>
                ScreenshotKeyboardCommand.ActivateToolbarItem,
            0x46 => ScreenshotKeyboardCommand.FullDisplay,
            0x25 => ScreenshotKeyboardCommand.MoveLeft,
            0x27 => ScreenshotKeyboardCommand.MoveRight,
            0x26 => ScreenshotKeyboardCommand.MoveUp,
            0x28 => ScreenshotKeyboardCommand.MoveDown,
            0x0D => ScreenshotKeyboardCommand.Complete,
            0x1B => ScreenshotKeyboardCommand.Escape,
            0x2E => ScreenshotKeyboardCommand.Delete,
            0x08 => ScreenshotKeyboardCommand.Backspace,
            _ => default,
        };
        return virtualKey is 0x75 or 0x46 or 0x25 or 0x27 or 0x26 or 0x28
            or 0x0D or 0x1B or 0x2E or 0x08
            || virtualKey == 0x20 && mode == ScreenshotKeyboardInputMode.Toolbar;
    }

    private static bool IsModifier(uint virtualKey) =>
        ControlKeys.Contains(virtualKey)
        || ShiftKeys.Contains(virtualKey)
        || AltKeys.Contains(virtualKey)
        || WindowsKeys.Contains(virtualKey);

    public sealed class ScreenshotKeyboardHookSession : IDisposable
    {
        private readonly ScreenshotKeyboardHookRouter owner;
        private readonly long sessionId;
        private int disposed;

        internal ScreenshotKeyboardHookSession(
            ScreenshotKeyboardHookRouter owner,
            long sessionId)
        {
            this.owner = owner;
            this.sessionId = sessionId;
        }

        public void SetInputMode(ScreenshotKeyboardInputMode mode)
        {
            ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
            owner.SetInputMode(sessionId, mode);
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) == 0)
            {
                owner.EndSession(sessionId);
            }
        }
    }
}
