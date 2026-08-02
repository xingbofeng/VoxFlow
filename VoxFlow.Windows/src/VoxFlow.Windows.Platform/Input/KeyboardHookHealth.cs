namespace VoxFlow.Windows.Platform.Input;

public enum HotkeyHealthFeedback
{
    HookUnavailable,
    HookRecovered,
}

public interface IHotkeyFeedbackSink
{
    void Report(HotkeyHealthFeedback feedback);
}

public interface IKeyboardHookBackend : IDisposable
{
    bool TryInstall();
}

public interface IKeyboardHookHealth
{
    bool IsInstalled { get; }
}

public sealed class LowLevelKeyboardHookSupervisor : IDisposable
{
    private readonly IKeyboardHookBackend backend;
    private readonly IHotkeyFeedbackSink feedbackSink;
    private bool disposed;

    public LowLevelKeyboardHookSupervisor(
        IKeyboardHookBackend backend,
        IHotkeyFeedbackSink feedbackSink)
    {
        this.backend = backend ?? throw new ArgumentNullException(nameof(backend));
        this.feedbackSink = feedbackSink ?? throw new ArgumentNullException(nameof(feedbackSink));
    }

    public bool IsHealthy { get; private set; }

    public bool Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        IsHealthy = backend.TryInstall();
        if (!IsHealthy)
        {
            feedbackSink.Report(HotkeyHealthFeedback.HookUnavailable);
        }

        return IsHealthy;
    }

    public bool CheckHealth()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        var healthy = backend is not IKeyboardHookHealth health || health.IsInstalled;
        if (healthy == IsHealthy)
        {
            return healthy;
        }

        IsHealthy = healthy;
        feedbackSink.Report(healthy
            ? HotkeyHealthFeedback.HookRecovered
            : HotkeyHealthFeedback.HookUnavailable);
        return healthy;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        IsHealthy = false;
        backend.Dispose();
    }
}
