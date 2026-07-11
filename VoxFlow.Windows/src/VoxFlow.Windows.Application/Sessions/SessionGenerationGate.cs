namespace VoxFlow.Windows.Application.Sessions;

/// <summary>
/// Serializes session lifecycle operations and event delivery asynchronously.
/// A cancel or completion cannot return while an earlier accepted callback is
/// still running, and callbacks never execute while holding a monitor lock.
/// </summary>
public sealed class SessionGenerationGate
{
    private readonly SemaphoreSlim lifecycleGate = new(1, 1);
    private readonly object snapshotGate = new();
    private Guid currentGeneration;

    public async ValueTask<Guid> BeginAsync(
        CancellationToken cancellationToken = default)
    {
        await lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            lock (snapshotGate)
            {
                Guid nextGeneration;
                do
                {
                    nextGeneration = Guid.NewGuid();
                }
                while (nextGeneration == Guid.Empty
                    || nextGeneration == currentGeneration);

                currentGeneration = nextGeneration;
                return nextGeneration;
            }
        }
        finally
        {
            lifecycleGate.Release();
        }
    }

    public bool IsCurrent(Guid generation)
    {
        lock (snapshotGate)
        {
            return IsCurrentUnsafe(generation);
        }
    }

    public async ValueTask<bool> TryDispatchAsync(
        Guid generation,
        Func<CancellationToken, ValueTask> callback,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(callback);

        await lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            lock (snapshotGate)
            {
                if (!IsCurrentUnsafe(generation))
                {
                    return false;
                }
            }

            await callback(cancellationToken).ConfigureAwait(false);
            return true;
        }
        finally
        {
            lifecycleGate.Release();
        }
    }

    public ValueTask<bool> CancelAsync(
        Guid generation,
        CancellationToken cancellationToken = default) =>
        EndAsync(generation, cancellationToken);

    public ValueTask<bool> CompleteAsync(
        Guid generation,
        CancellationToken cancellationToken = default) =>
        EndAsync(generation, cancellationToken);

    private async ValueTask<bool> EndAsync(
        Guid generation,
        CancellationToken cancellationToken)
    {
        await lifecycleGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            lock (snapshotGate)
            {
                if (!IsCurrentUnsafe(generation))
                {
                    return false;
                }

                currentGeneration = Guid.Empty;
                return true;
            }
        }
        finally
        {
            lifecycleGate.Release();
        }
    }

    private bool IsCurrentUnsafe(Guid generation) =>
        generation != Guid.Empty && generation == currentGeneration;
}
