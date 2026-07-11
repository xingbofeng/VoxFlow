using System.Windows.Threading;

namespace VoxFlow.Windows.Testing;

public sealed record StaWpfTestContext(ApartmentState ApartmentState, bool HasDispatcher);

public static class StaWpfTestHost
{
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(10);

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

        var completion = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var dispatcherReady = new TaskCompletionSource<Dispatcher>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var threadExited = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        using var operation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

        var thread = new Thread(() => RunDispatcher(
            callback,
            operation.Token,
            completion,
            dispatcherReady,
            threadExited))
        {
            IsBackground = true,
            Name = "VoxFlow WPF test host",
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();

        var dispatcher = await dispatcherReady.Task.ConfigureAwait(false);

        try
        {
            await completion.Task
                .WaitAsync(effectiveTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            await operation.CancelAsync().ConfigureAwait(false);
            RequestShutdown(dispatcher);
            throw;
        }
        catch (OperationCanceledException)
        {
            await operation.CancelAsync().ConfigureAwait(false);
            RequestShutdown(dispatcher);
            throw;
        }
        finally
        {
            RequestShutdown(dispatcher);

            try
            {
                await threadExited.Task
                    .WaitAsync(TimeSpan.FromSeconds(2))
                    .ConfigureAwait(false);
            }
            catch (TimeoutException)
            {
                // A callback that synchronously blocks an STA thread cannot be safely aborted.
            }
        }
    }

    private static void RunDispatcher(
        Func<StaWpfTestContext, CancellationToken, Task> callback,
        CancellationToken cancellationToken,
        TaskCompletionSource completion,
        TaskCompletionSource<Dispatcher> dispatcherReady,
        TaskCompletionSource threadExited)
    {
        var dispatcher = Dispatcher.CurrentDispatcher;
        dispatcherReady.TrySetResult(dispatcher);

        dispatcher.BeginInvoke(
            DispatcherPriority.Normal,
            new Action(async () =>
            {
                try
                {
                    await callback(
                        new StaWpfTestContext(
                            Thread.CurrentThread.GetApartmentState(),
                            Dispatcher.FromThread(Thread.CurrentThread) is not null),
                        cancellationToken);
                    completion.TrySetResult();
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
                    RequestShutdown(dispatcher);
                }
            }));

        try
        {
            Dispatcher.Run();
        }
        finally
        {
            threadExited.TrySetResult();
        }
    }

    private static void RequestShutdown(Dispatcher dispatcher)
    {
        if (!dispatcher.HasShutdownStarted && !dispatcher.HasShutdownFinished)
        {
            dispatcher.BeginInvokeShutdown(DispatcherPriority.Send);
        }
    }
}
