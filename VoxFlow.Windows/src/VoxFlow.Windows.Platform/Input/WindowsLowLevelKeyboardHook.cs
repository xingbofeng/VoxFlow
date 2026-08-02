using System.Runtime.InteropServices;

namespace VoxFlow.Windows.Platform.Input;

public sealed class WindowsLowLevelKeyboardHook : IKeyboardHookBackend, IKeyboardHookHealth
{
    private const int WhKeyboardLowLevel = 13;
    private const uint WmKeyDown = 0x0100;
    private const uint WmKeyUp = 0x0101;
    private const uint WmSysKeyDown = 0x0104;
    private const uint WmSysKeyUp = 0x0105;
    private const uint WmQuit = 0x0012;

    private readonly object syncRoot = new();
    private readonly TimeProvider timeProvider;
    private readonly ManualResetEventSlim startupCompleted = new(false);
    private readonly HookProcedure hookProcedure;
    private readonly LowLevelKeyboardEventDispatcher eventDispatcher;
    private readonly Func<LowLevelKeyEvent, LowLevelKeyboardRoutingDecision> routeEvent;
    private Thread? messageThread;
    private nint hookHandle;
    private uint messageThreadId;
    private bool startupSucceeded;
    private bool disposed;

    public WindowsLowLevelKeyboardHook(
        Action<LowLevelKeyboardDispatch> onKeyEvent,
        Func<LowLevelKeyEvent, LowLevelKeyboardRoutingDecision>? routeEvent = null,
        TimeProvider? timeProvider = null)
    {
        ArgumentNullException.ThrowIfNull(onKeyEvent);
        this.timeProvider = timeProvider ?? TimeProvider.System;
        this.routeEvent = routeEvent ?? (_ => LowLevelKeyboardRoutingDecision.PassThrough);
        hookProcedure = OnHook;
        eventDispatcher = new LowLevelKeyboardEventDispatcher(onKeyEvent);
    }

    public bool IsInstalled
    {
        get
        {
            lock (syncRoot)
            {
                return hookHandle != nint.Zero
                    && messageThread is { IsAlive: true };
            }
        }
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
                Name = "VoxFlow WH_KEYBOARD_LL message loop",
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

        eventDispatcher.Dispose();

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
                WhKeyboardLowLevel,
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
            && message.ToInt64() is WmKeyDown or WmKeyUp or WmSysKeyDown or WmSysKeyUp)
        {
            var native = Marshal.PtrToStructure<KeyboardHookData>(data);
            var flags = (LowLevelKeyFlags)native.Flags;
            if (!flags.HasFlag(LowLevelKeyFlags.Injected))
            {
                var keyEvent = new LowLevelKeyEvent(
                    native.VirtualKey,
                    native.ScanCode,
                    flags,
                    message.ToInt64() is WmKeyUp or WmSysKeyUp
                        ? KeyTransition.Up
                        : KeyTransition.Down,
                    timeProvider.GetUtcNow());
                LowLevelKeyboardRoutingDecision routing;
                try
                {
                    routing = routeEvent(keyEvent);
                }
                catch (Exception)
                {
                    routing = LowLevelKeyboardRoutingDecision.PassThrough;
                }
                eventDispatcher.TryPost(new LowLevelKeyboardDispatch(
                    keyEvent,
                    routing.Consume,
                    routing.ScreenshotCommand));
                if (routing.Consume)
                {
                    return new nint(1);
                }
            }
        }

        return CallNextHookEx(nint.Zero, code, message, data);
    }

    private delegate nint HookProcedure(int code, nint message, nint data);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct KeyboardHookData
    {
        public readonly uint VirtualKey;
        public readonly uint ScanCode;
        public readonly uint Flags;
        public readonly uint Time;
        public readonly nuint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct NativePoint
    {
        public readonly int X;
        public readonly int Y;
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
    private static extern nint CallNextHookEx(
        nint hook,
        int code,
        nint message,
        nint data);

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
