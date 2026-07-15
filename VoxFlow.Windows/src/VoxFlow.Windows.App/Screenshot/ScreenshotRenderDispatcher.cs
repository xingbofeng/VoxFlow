using System.Collections.Concurrent;

namespace VoxFlow.Windows.App.Screenshot;

public interface IScreenshotRenderDispatcher : IDisposable
{
    Task<T> InvokeAsync<T>(
        Func<T> operation,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Runs WPF bitmap composition on one application-owned STA thread. The
/// returned task never executes its continuation inline on the render thread.
/// </summary>
public sealed class ScreenshotStaRenderDispatcher : IScreenshotRenderDispatcher
{
    private readonly BlockingCollection<IRenderWorkItem> work = [];
    private readonly Thread thread;
    private int disposed;

    public ScreenshotStaRenderDispatcher()
    {
        thread = new Thread(Run)
        {
            IsBackground = true,
            Name = "VoxFlow screenshot render STA",
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
    }

    public Task<T> InvokeAsync<T>(
        Func<T> operation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(operation);
        ObjectDisposedException.ThrowIf(
            Volatile.Read(ref disposed) != 0,
            this);
        cancellationToken.ThrowIfCancellationRequested();

        var item = new RenderWorkItem<T>(operation, cancellationToken);
        try
        {
            if (!work.TryAdd(item))
            {
                item.Dispose();
                throw new ObjectDisposedException(nameof(ScreenshotStaRenderDispatcher));
            }
        }
        catch (InvalidOperationException exception)
        {
            item.Dispose();
            throw new ObjectDisposedException(
                nameof(ScreenshotStaRenderDispatcher),
                exception.Message);
        }
        return item.Task;
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0)
        {
            return;
        }
        work.CompleteAdding();
        if (Thread.CurrentThread != thread)
        {
            _ = thread.Join(TimeSpan.FromSeconds(3));
        }
    }

    private void Run()
    {
        foreach (var item in work.GetConsumingEnumerable())
        {
            item.Execute();
        }
    }

    private interface IRenderWorkItem
    {
        void Execute();
    }

    private sealed class RenderWorkItem<T> : IRenderWorkItem, IDisposable
    {
        private readonly Func<T> operation;
        private readonly CancellationToken cancellationToken;
        private readonly TaskCompletionSource<T> completion = new(
            TaskCreationOptions.RunContinuationsAsynchronously);
        private CancellationTokenRegistration cancellationRegistration;

        public RenderWorkItem(
            Func<T> operation,
            CancellationToken cancellationToken)
        {
            this.operation = operation;
            this.cancellationToken = cancellationToken;
            if (cancellationToken.CanBeCanceled)
            {
                cancellationRegistration = cancellationToken.Register(
                    static state => ((RenderWorkItem<T>)state!).Cancel(),
                    this);
            }
        }

        public Task<T> Task => completion.Task;

        public void Execute()
        {
            try
            {
                if (completion.Task.IsCompleted)
                {
                    return;
                }
                cancellationToken.ThrowIfCancellationRequested();
                var result = operation();
                if (cancellationToken.IsCancellationRequested)
                {
                    completion.TrySetCanceled(cancellationToken);
                }
                else
                {
                    completion.TrySetResult(result);
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                completion.TrySetCanceled(cancellationToken);
            }
            catch (Exception exception)
            {
                completion.TrySetException(exception);
            }
            finally
            {
                Dispose();
            }
        }

        public void Dispose() => cancellationRegistration.Dispose();

        private void Cancel() => completion.TrySetCanceled(cancellationToken);
    }
}
