namespace VoxFlow.Windows.Testing;

public static class CancellableTestTask
{
    public static async Task WaitUntilCancelledAsync(CancellationToken cancellationToken)
    {
        if (!cancellationToken.CanBeCanceled)
        {
            throw new ArgumentException("A cancellable token is required.", nameof(cancellationToken));
        }

        try
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Cancellation is the successful completion condition for this test helper.
        }
    }
}
