using Microsoft.Win32;

namespace VoxFlow.Windows.Platform.Screenshot;

internal interface IScreenshotCaptureInvalidationSink
{
    void Invalidate(ScreenshotCaptureInvalidationReason reason);
}

/// <summary>
/// Bridges process/session and host-window topology notifications into a full DX11 reset.
/// The WPF host forwards WM_DISPLAYCHANGE/WM_DEVICECHANGE through HandleWindowMessage.
/// </summary>
public sealed class WindowsScreenshotCaptureLifecycle : IDisposable
{
    public const int DisplayChangeMessage = 0x007E;
    public const int DeviceChangeMessage = 0x0219;

    private readonly IScreenshotCaptureInvalidationSink sink;
    private readonly bool subscribedToSystemEvents;
    private bool disposed;

    public WindowsScreenshotCaptureLifecycle(Dx11ScreenshotFrameSource frameSource)
        : this((IScreenshotCaptureInvalidationSink)frameSource, subscribeSystemEvents: true)
    {
    }

    internal WindowsScreenshotCaptureLifecycle(
        IScreenshotCaptureInvalidationSink sink,
        bool subscribeSystemEvents = false)
    {
        this.sink = sink ?? throw new ArgumentNullException(nameof(sink));
        subscribedToSystemEvents = subscribeSystemEvents;
        if (subscribedToSystemEvents)
        {
            SystemEvents.DisplaySettingsChanging += OnDisplaySettingsChanging;
            SystemEvents.SessionSwitch += OnSessionSwitch;
        }
    }

    public bool HandleWindowMessage(int message)
    {
        if (disposed)
        {
            return false;
        }

        var reason = message switch
        {
            DisplayChangeMessage => ScreenshotCaptureInvalidationReason.DisplayChange,
            DeviceChangeMessage => ScreenshotCaptureInvalidationReason.DeviceChange,
            _ => (ScreenshotCaptureInvalidationReason?)null,
        };
        if (reason is null)
        {
            return false;
        }
        sink.Invalidate(reason.Value);
        return true;
    }

    public void Shutdown()
    {
        if (!disposed)
        {
            sink.Invalidate(ScreenshotCaptureInvalidationReason.ApplicationShutdown);
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        if (subscribedToSystemEvents)
        {
            SystemEvents.DisplaySettingsChanging -= OnDisplaySettingsChanging;
            SystemEvents.SessionSwitch -= OnSessionSwitch;
        }
    }

    private void OnDisplaySettingsChanging(object? sender, EventArgs eventArgs)
    {
        _ = sender;
        _ = eventArgs;
        sink.Invalidate(ScreenshotCaptureInvalidationReason.DisplayChange);
    }

    private void OnSessionSwitch(object sender, SessionSwitchEventArgs eventArgs)
    {
        _ = sender;
        var reason = eventArgs.Reason is SessionSwitchReason.SessionLock
            or SessionSwitchReason.SessionLogoff
            or SessionSwitchReason.ConsoleDisconnect
            or SessionSwitchReason.RemoteDisconnect
            ? ScreenshotCaptureInvalidationReason.SessionLock
            : ScreenshotCaptureInvalidationReason.DesktopSwitch;
        sink.Invalidate(reason);
    }
}
