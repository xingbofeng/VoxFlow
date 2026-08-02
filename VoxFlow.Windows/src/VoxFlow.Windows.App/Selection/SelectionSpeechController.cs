namespace VoxFlow.Windows.App.Selection;

public enum SelectionSpeechState
{
    Idle,
    Speaking,
    Unavailable,
    Failed,
}

public interface ISelectionSpeechBackend
{
    bool HasVoice { get; }

    Task SpeakAsync(string text, CancellationToken cancellationToken);
}

/// <summary>
/// Keeps system speech scoped to the result panel. A new request, explicit
/// stop, panel close, or disposal invalidates the old generation immediately.
/// </summary>
public sealed class SelectionSpeechController : IAsyncDisposable
{
    private readonly ISelectionSpeechBackend backend;
    private CancellationTokenSource? cancellation;
    private int generation;
    private bool disposed;

    public SelectionSpeechController(ISelectionSpeechBackend backend)
    {
        this.backend = backend ?? throw new ArgumentNullException(nameof(backend));
    }

    public SelectionSpeechState State { get; private set; } = SelectionSpeechState.Idle;

    public async Task SpeakAsync(string text)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        Stop();
        if (!backend.HasVoice)
        {
            State = SelectionSpeechState.Unavailable;
            return;
        }

        var currentGeneration = Interlocked.Increment(ref generation);
        var currentCancellation = new CancellationTokenSource();
        cancellation = currentCancellation;
        State = SelectionSpeechState.Speaking;
        try
        {
            await backend.SpeakAsync(text, currentCancellation.Token).ConfigureAwait(false);
            if (currentGeneration == Volatile.Read(ref generation))
            {
                State = SelectionSpeechState.Idle;
            }
        }
        catch (OperationCanceledException) when (currentCancellation.IsCancellationRequested)
        {
            if (currentGeneration == Volatile.Read(ref generation))
            {
                State = SelectionSpeechState.Idle;
            }
        }
        catch
        {
            if (currentGeneration == Volatile.Read(ref generation))
            {
                State = SelectionSpeechState.Failed;
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
        cancellation?.Cancel();
        cancellation = null;
        if (State == SelectionSpeechState.Speaking)
        {
            State = SelectionSpeechState.Idle;
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
}
