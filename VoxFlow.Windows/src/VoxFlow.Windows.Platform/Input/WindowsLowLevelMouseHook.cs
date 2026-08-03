using System.Runtime.InteropServices;

namespace VoxFlow.Windows.Platform.Input;

/// <summary>Owns a WH_MOUSE_LL message loop and forwards physical middle-button
/// transitions. The hook only consumes the button when the live setting says
/// middle-button dictation is enabled.</summary>
public sealed class WindowsLowLevelMouseHook : IDisposable
{
    private const int WhMouseLowLevel = 14;
    private const uint WmMiddleButtonDown = 0x0207;
    private const uint WmMiddleButtonUp = 0x0208;
    private const uint WmQuit = 0x0012;
    private const uint InjectedFlag = 0x00000001;

    private readonly object syncRoot = new();
    private readonly Action<MouseButton, ButtonTransition> onMouseEvent;
    private readonly Func<bool> shouldConsumeMiddleButton;
    private readonly ManualResetEventSlim startupCompleted = new(false);
    private readonly HookProcedure hookProcedure;
    private Thread? messageThread;
    private nint hookHandle;
    private uint messageThreadId;
    private bool startupSucceeded;
    private bool disposed;

    public WindowsLowLevelMouseHook(
        Action<MouseButton, ButtonTransition> onMouseEvent,
        Func<bool> shouldConsumeMiddleButton)
    {
        this.onMouseEvent = onMouseEvent
            ?? throw new ArgumentNullException(nameof(onMouseEvent));
        this.shouldConsumeMiddleButton = shouldConsumeMiddleButton
            ?? throw new ArgumentNullException(nameof(shouldConsumeMiddleButton));
        hookProcedure = OnHook;
    }

    public bool TryInstall()
    {
        lock (syncRoot)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (hookHandle != nint.Zero && messageThread is { IsAlive: true })
            {
                return true;
            }

            startupSucceeded = false;
            startupCompleted.Reset();
            messageThread = new Thread(RunMessageLoop)
            {
                IsBackground = true,
                Name = "VoxFlow WH_MOUSE_LL message loop",
            };
            messageThread.SetApartmentState(ApartmentState.MTA);
            messageThread.Start();
        }

        return startupCompleted.Wait(TimeSpan.FromSeconds(5)) && startupSucceeded;
    }

    public void Dispose()
    {
        Thread? thread;
        uint threadId;
        lock (syncRoot)
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            thread = messageThread;
            threadId = messageThreadId;
        }

        if (threadId != 0)
        {
            _ = PostThreadMessage(threadId, WmQuit, nint.Zero, nint.Zero);
        }
        if (thread is not null && thread != Thread.CurrentThread)
        {
            _ = thread.Join(TimeSpan.FromSeconds(3));
        }
        startupCompleted.Dispose();
    }

    private void RunMessageLoop()
    {
        nint installedHook = nint.Zero;
        try
        {
            var threadId = GetCurrentThreadId();
            _ = PeekMessage(out _, nint.Zero, 0, 0, 0);
            installedHook = SetWindowsHookEx(
                WhMouseLowLevel,
                hookProcedure,
                GetModuleHandle(null),
                0);
            lock (syncRoot)
            {
                messageThreadId = threadId;
                hookHandle = installedHook;
                startupSucceeded = installedHook != nint.Zero;
            }
            startupCompleted.Set();
            if (installedHook == nint.Zero)
            {
                return;
            }

            while (GetMessage(out var message, nint.Zero, 0, 0) > 0)
            {
                _ = TranslateMessage(in message);
                _ = DispatchMessage(in message);
            }
        }
        finally
        {
            if (installedHook != nint.Zero)
            {
                _ = UnhookWindowsHookEx(installedHook);
            }
            lock (syncRoot)
            {
                hookHandle = nint.Zero;
                messageThreadId = 0;
            }
            startupCompleted.Set();
        }
    }

    private nint OnHook(int code, nint message, nint data)
    {
        if (code >= 0
            && message.ToInt64() is WmMiddleButtonDown or WmMiddleButtonUp)
        {
            var native = Marshal.PtrToStructure<MouseHookData>(data);
            if ((native.Flags & InjectedFlag) == 0)
            {
                try
                {
                    onMouseEvent(
                        MouseButton.Middle,
                        message.ToInt64() == WmMiddleButtonUp
                            ? ButtonTransition.Up
                            : ButtonTransition.Down);
                    if (shouldConsumeMiddleButton())
                    {
                        return new nint(1);
                    }
                }
                catch
                {
                    // A hook callback must always fail open.
                }
            }
        }

        return CallNextHookEx(nint.Zero, code, message, data);
    }

    private delegate nint HookProcedure(int code, nint message, nint data);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct NativePoint
    {
        public readonly int X;
        public readonly int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct MouseHookData
    {
        public readonly NativePoint Point;
        public readonly uint MouseData;
        public readonly uint Flags;
        public readonly uint Time;
        public readonly nuint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct NativeMessage
    {
        public readonly nint Window;
        public readonly uint Message;
        public readonly nuint WParam;
        public readonly nint LParam;
        public readonly uint Time;
        public readonly NativePoint Point;
        public readonly uint Private;
    }

    [DllImport("user32.dll", EntryPoint = "SetWindowsHookExW", SetLastError = true)]
    private static extern nint SetWindowsHookEx(
        int hookType,
        HookProcedure callback,
        nint module,
        uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hook);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hook, int code, nint message, nint data);

    [DllImport("user32.dll", EntryPoint = "GetMessageW", SetLastError = true)]
    private static extern int GetMessage(
        out NativeMessage message,
        nint window,
        uint minimumMessage,
        uint maximumMessage);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TranslateMessage(in NativeMessage message);

    [DllImport("user32.dll", EntryPoint = "DispatchMessageW")]
    private static extern nint DispatchMessage(in NativeMessage message);

    [DllImport("user32.dll", EntryPoint = "PeekMessageW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PeekMessage(
        out NativeMessage message,
        nint window,
        uint minimumMessage,
        uint maximumMessage,
        uint removeMessage);

    [DllImport("user32.dll", EntryPoint = "PostThreadMessageW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostThreadMessage(
        uint threadId,
        uint message,
        nint wParam,
        nint lParam);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("kernel32.dll", EntryPoint = "GetModuleHandleW", CharSet = CharSet.Unicode)]
    private static extern nint GetModuleHandle(string? moduleName);
}
