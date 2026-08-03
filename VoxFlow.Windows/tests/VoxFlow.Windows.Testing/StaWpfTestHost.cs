using System.Windows.Threading;

namespace VoxFlow.Windows.Testing;

public sealed record StaWpfTestContext(ApartmentState ApartmentState, bool HasDispatcher);

public static class StaWpfTestHost
{
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);
    private static readonly SemaphoreSlim CallbackGate = new(1, 1);
    private static readonly Lazy<Dispatcher> SharedDispatcher = new(
        StartDispatcher,
        LazyThreadSafetyMode.ExecutionAndPublication);

    public static Task RunAsync(
        Func<StaWpfTestContext, Task> callback,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(callback);

        return RunAsync(
            (context, _) => callback(context),
            timeout,
            cancellationToken);
    }

    public static async Task RunAsync(
        Func<StaWpfTestContext, CancellationToken, Task> callback,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(callback);

        var effectiveTimeout = timeout ?? DefaultTimeout;
        if (effectiveTimeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        await CallbackGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        using var operation = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        var dispatcher = SharedDispatcher.Value;

        try
        {
            var callbackTask = dispatcher.InvokeAsync(
                    () => callback(
                        new StaWpfTestContext(
                            Thread.CurrentThread.GetApartmentState(),
                            Dispatcher.FromThread(Thread.CurrentThread) is not null),
                        operation.Token),
                    DispatcherPriority.Normal,
                    cancellationToken)
                .Task
                .Unwrap();
            await callbackTask
                .WaitAsync(effectiveTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            await operation.CancelAsync().ConfigureAwait(false);
            throw;
        }
        catch (OperationCanceledException)
        {
            await operation.CancelAsync().ConfigureAwait(false);
            throw;
        }
        finally
        {
            CallbackGate.Release();
        }
    }

    private static Dispatcher StartDispatcher()
    {
        var dispatcherReady = new TaskCompletionSource<Dispatcher>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            var dispatcher = Dispatcher.CurrentDispatcher;
            dispatcherReady.TrySetResult(dispatcher);
            Dispatcher.Run();
        })
        {
            IsBackground = true,
            Name = "VoxFlow shared WPF test host",
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return dispatcherReady.Task.GetAwaiter().GetResult();
    }
}
