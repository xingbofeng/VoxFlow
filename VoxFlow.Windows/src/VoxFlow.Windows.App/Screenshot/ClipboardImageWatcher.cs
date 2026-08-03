using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Threading;

namespace VoxFlow.Windows.App.Screenshot;

/// <summary>
/// Listens for system clipboard updates via a message-only window and
/// dispatches image-OCR work when automatic recognition is enabled.
/// </summary>
public sealed class ClipboardImageWatcher : IDisposable
{
    private const int WmClipboardUpdate = 0x031D;
    private const int WmDestroy = 0x0002;
    private const int HwndMessage = -3;

    private readonly Dispatcher dispatcher;
    private readonly Func<bool> isEnabled;
    private readonly Func<CancellationToken, Task> onImageClipboardChanged;
    private readonly DispatcherTimer debounce;
    private HwndSource? source;
    private bool disposed;

    public ClipboardImageWatcher(
        Dispatcher dispatcher,
        Func<bool> isEnabled,
        Func<CancellationToken, Task> onImageClipboardChanged)
    {
        this.dispatcher = dispatcher ?? throw new ArgumentNullException(nameof(dispatcher));
        this.isEnabled = isEnabled ?? throw new ArgumentNullException(nameof(isEnabled));
        this.onImageClipboardChanged = onImageClipboardChanged
            ?? throw new ArgumentNullException(nameof(onImageClipboardChanged));
        debounce = new DispatcherTimer(DispatcherPriority.Background, dispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(350),
        };
        debounce.Tick += OnDebounceTick;
    }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (!dispatcher.CheckAccess())
        {
            dispatcher.Invoke(Start);
            return;
        }
        if (source is not null)
        {
            return;
        }

        var parameters = new HwndSourceParameters("VoxFlowClipboardWatcher")
        {
            Width = 0,
            Height = 0,
            PositionX = 0,
            PositionY = 0,
            WindowStyle = 0,
            ParentWindow = new IntPtr(HwndMessage),
        };
        source = new HwndSource(parameters);
        source.AddHook(WndProc);
        if (!NativeMethods.AddClipboardFormatListener(source.Handle))
        {
            source.RemoveHook(WndProc);
            source.Dispose();
            source = null;
            throw new InvalidOperationException(
                "Failed to register the clipboard format listener.");
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        if (!dispatcher.CheckAccess())
        {
            dispatcher.Invoke(Dispose);
            return;
        }

        debounce.Stop();
        debounce.Tick -= OnDebounceTick;
        if (source is not null)
        {
            _ = NativeMethods.RemoveClipboardFormatListener(source.Handle);
            source.RemoveHook(WndProc);
            source.Dispose();
            source = null;
        }
    }

    private IntPtr WndProc(
        IntPtr hwnd,
        int msg,
        IntPtr wParam,
        IntPtr lParam,
        ref bool handled)
    {
        if (msg == WmClipboardUpdate)
        {
            if (isEnabled())
            {
                debounce.Stop();
                debounce.Start();
            }
            handled = false;
        }
        else if (msg == WmDestroy && source is not null)
        {
            _ = NativeMethods.RemoveClipboardFormatListener(source.Handle);
        }

        return IntPtr.Zero;
    }

    private void OnDebounceTick(object? sender, EventArgs e)
    {
        debounce.Stop();
        if (disposed || !isEnabled())
        {
            return;
        }

        _ = onImageClipboardChanged(CancellationToken.None);
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool AddClipboardFormatListener(IntPtr hwnd);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
    }
}
