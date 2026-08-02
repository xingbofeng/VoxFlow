namespace VoxFlow.Windows.Application.FileTranscription;

public interface IFileTranscriptionJobExecutor
{
    Task ExecuteAsync(
        string jobId,
        Guid runId,
        CancellationToken cancellationToken);
}

public interface IFileTranscriptionRunGate
{
    bool IsCurrent(string jobId, Guid runId);

    bool TryApply(string jobId, Guid runId, Action mutation);
}

public sealed class FileTranscriptionQueueService
    : IFileTranscriptionRunGate, IAsyncDisposable
{
    private readonly object stateGate = new();
    private readonly IFileTranscriptionJobExecutor executor;
    private readonly Queue<RunRegistration> pending = [];
    private readonly Dictionary<string, RunRegistration> registered =
        new(StringComparer.Ordinal);
    private readonly CancellationTokenSource lifetime = new();
    private TaskCompletionSource idle = CompletedSignal();
    private Task processingTask = Task.CompletedTask;
    private bool processorRunning;
    private bool disposed;

    public FileTranscriptionQueueService(IFileTranscriptionJobExecutor executor)
    {
        this.executor = executor ?? throw new ArgumentNullException(nameof(executor));
    }

    public bool TryEnqueue(string jobId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        lock (stateGate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (registered.ContainsKey(jobId))
            {
                return false;
            }

            if (registered.Count == 0)
            {
                idle = new TaskCompletionSource(
                    TaskCreationOptions.RunContinuationsAsynchronously);
            }

            var registration = new RunRegistration(
                jobId,
                Guid.NewGuid(),
                CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token));
            registered.Add(jobId, registration);
            pending.Enqueue(registration);
            if (!processorRunning)
            {
                processorRunning = true;
                processingTask = Task.Run(ProcessAsync, CancellationToken.None);
            }
            return true;
        }
    }

    public Task WhenIdleAsync()
    {
        lock (stateGate)
        {
            return idle.Task;
        }
    }

    public bool Cancel(string jobId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        lock (stateGate)
        {
            if (!registered.Remove(jobId, out var registration))
            {
                return false;
            }

            registration.Cancellation.Cancel();
            return true;
        }
    }

    public bool IsCurrent(string jobId, Guid runId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        if (runId == Guid.Empty)
        {
            return false;
        }
        lock (stateGate)
        {
            return registered.TryGetValue(jobId, out var registration)
                && registration.RunId == runId
                && !registration.Cancellation.IsCancellationRequested;
        }
    }

    public bool TryApply(string jobId, Guid runId, Action mutation)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);
        ArgumentNullException.ThrowIfNull(mutation);
        if (runId == Guid.Empty)
        {
            return false;
        }
        lock (stateGate)
        {
            if (!registered.TryGetValue(jobId, out var registration)
                || registration.RunId != runId
                || registration.Cancellation.IsCancellationRequested)
            {
                return false;
            }

            mutation();
            return true;
        }
    }

    public async ValueTask DisposeAsync()
    {
        Task task;
        lock (stateGate)
        {
            if (disposed)
            {
                return;
            }

            disposed = true;
            lifetime.Cancel();
            foreach (var registration in registered.Values)
            {
                registration.Cancellation.Cancel();
            }
            task = processingTask;
        }

        try
        {
            await task.ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            lifetime.Dispose();
        }
    }

    private async Task ProcessAsync()
    {
        while (true)
        {
            RunRegistration registration;
            lock (stateGate)
            {
                if (pending.Count == 0)
                {
                    processorRunning = false;
                    if (registered.Count == 0)
                    {
                        idle.TrySetResult();
                    }
                    return;
                }

                registration = pending.Dequeue();
            }

            try
            {
                registration.Cancellation.Token.ThrowIfCancellationRequested();
                await executor.ExecuteAsync(
                    registration.JobId,
                    registration.RunId,
                    registration.Cancellation.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
            catch
            {
                // The job executor owns persisted failure reporting. A failed
                // job must not prevent the following queued job from starting.
            }
            finally
            {
                lock (stateGate)
                {
                    if (registered.TryGetValue(registration.JobId, out var current)
                        && ReferenceEquals(current, registration))
                    {
                        registered.Remove(registration.JobId);
                    }
                    registration.Cancellation.Dispose();
                    if (registered.Count == 0 && pending.Count == 0)
                    {
                        idle.TrySetResult();
                    }
                }
            }
        }
    }

    private static TaskCompletionSource CompletedSignal()
    {
        var signal = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        signal.SetResult();
        return signal;
    }

    private sealed record RunRegistration(
        string JobId,
        Guid RunId,
        CancellationTokenSource Cancellation);
}
