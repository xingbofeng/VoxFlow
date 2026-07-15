using VoxFlow.Windows.App.Selection;

namespace VoxFlow.Windows.App.Screenshot;

public enum ScreenshotSpeechState
{
    Idle,
    Speaking,
    Unavailable,
    Failed,
}

public interface IScreenshotSpeechBackend
{
    bool IsAvailable { get; }

    Task SpeakAsync(string text, CancellationToken cancellationToken);
}

/// <summary>
/// Prefers a configured on-device speech backend and falls back to the
/// installed Windows system voice. It never sends screenshot text to a
/// network service.
/// </summary>
public sealed class FallbackScreenshotSpeechBackend : IScreenshotSpeechBackend
{
    private readonly IScreenshotSpeechBackend? local;
    private readonly IScreenshotSpeechBackend system;

    public FallbackScreenshotSpeechBackend(
        IScreenshotSpeechBackend? local,
        IScreenshotSpeechBackend system)
    {
        this.local = local;
        this.system = system ?? throw new ArgumentNullException(nameof(system));
    }

    public bool IsAvailable => local?.IsAvailable == true || system.IsAvailable;

    public async Task SpeakAsync(string text, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        if (local?.IsAvailable == true)
        {
            try
            {
                await local.SpeakAsync(text, cancellationToken).ConfigureAwait(false);
                return;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch when (system.IsAvailable)
            {
                // The local engine is preferred, but an installed system voice
                // keeps the explicit read action useful when that engine fails.
            }
        }

        if (!system.IsAvailable)
        {
            throw new InvalidOperationException("No local screenshot speech backend is available.");
        }
        await system.SpeakAsync(text, cancellationToken).ConfigureAwait(false);
    }
}

public sealed class WindowsSystemScreenshotSpeechBackend : IScreenshotSpeechBackend
{
    private readonly WindowsSystemSpeechBackend backend = new();

    public bool IsAvailable => backend.HasVoice;

    public Task SpeakAsync(string text, CancellationToken cancellationToken) =>
        backend.SpeakAsync(text, cancellationToken);
}

public sealed class ScreenshotSpeechController : IAsyncDisposable
{
    private readonly IScreenshotSpeechBackend backend;
    private CancellationTokenSource? cancellation;
    private int generation;
    private bool disposed;

    public ScreenshotSpeechController(IScreenshotSpeechBackend backend)
    {
        this.backend = backend ?? throw new ArgumentNullException(nameof(backend));
    }

    public event EventHandler? StateChanged;

    public ScreenshotSpeechState State { get; private set; }

    public string? LastRequestedText { get; private set; }

    public Task ToggleAsync(string text)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (State == ScreenshotSpeechState.Speaking)
        {
            Stop();
            return Task.CompletedTask;
        }
        return SpeakAsync(text);
    }

    public async Task SpeakAsync(string text)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        Stop();
        LastRequestedText = text;
        if (!backend.IsAvailable)
        {
            SetState(ScreenshotSpeechState.Unavailable);
            return;
        }

        var currentGeneration = Interlocked.Increment(ref generation);
        var currentCancellation = new CancellationTokenSource();
        cancellation = currentCancellation;
        SetState(ScreenshotSpeechState.Speaking);
        try
        {
            await backend.SpeakAsync(text, currentCancellation.Token).ConfigureAwait(false);
            if (currentGeneration == Volatile.Read(ref generation))
            {
                SetState(ScreenshotSpeechState.Idle);
            }
        }
        catch (OperationCanceledException) when (currentCancellation.IsCancellationRequested)
        {
            if (currentGeneration == Volatile.Read(ref generation))
            {
                SetState(ScreenshotSpeechState.Idle);
            }
        }
        catch
        {
            if (currentGeneration == Volatile.Read(ref generation))
            {
                SetState(ScreenshotSpeechState.Failed);
            }
        }
        finally
        {
            if (ReferenceEquals(cancellation, currentCancellation))
            {
                cancellation = null;
            }
            currentCancellation.Dispose();
        }
    }

    public void Stop()
    {
        Interlocked.Increment(ref generation);
        var current = Interlocked.Exchange(ref cancellation, null);
        current?.Cancel();
        if (State == ScreenshotSpeechState.Speaking)
        {
            SetState(ScreenshotSpeechState.Idle);
        }
    }

    public ValueTask DisposeAsync()
    {
        if (!disposed)
        {
            disposed = true;
            Stop();
        }
        return ValueTask.CompletedTask;
    }

    private void SetState(ScreenshotSpeechState value)
    {
        if (State == value)
        {
            return;
        }
        State = value;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }
}
