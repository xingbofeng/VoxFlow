using System.Threading.Channels;

namespace VoxFlow.Windows.Platform.Input;

public sealed class LowLevelKeyboardEventDispatcher : IDisposable
{
    private readonly Action<LowLevelKeyboardDispatch> consumer;
    private readonly Channel<LowLevelKeyboardDispatch> channel =
        Channel.CreateUnbounded<LowLevelKeyboardDispatch>(new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = true,
            AllowSynchronousContinuations = false,
        });
    private readonly Task consumerTask;
    private int disposed;

    public LowLevelKeyboardEventDispatcher(Action<LowLevelKeyboardDispatch> consumer)
    {
        this.consumer = consumer ?? throw new ArgumentNullException(nameof(consumer));
        consumerTask = Task.Run(ConsumeAsync);
    }

    public bool TryPost(LowLevelKeyEvent keyEvent)
    {
        ArgumentNullException.ThrowIfNull(keyEvent);
        return TryPost(new LowLevelKeyboardDispatch(
            keyEvent,
            Consumed: false,
            ScreenshotCommand: null));
    }

    public bool TryPost(LowLevelKeyboardDispatch dispatch)
    {
        ArgumentNullException.ThrowIfNull(dispatch);
        return Volatile.Read(ref disposed) == 0
            && channel.Writer.TryWrite(dispatch);
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0)
        {
            return;
        }

        channel.Writer.TryComplete();
        try
        {
            _ = consumerTask.Wait(TimeSpan.FromSeconds(3));
        }
        catch (AggregateException)
        {
            // Consumer failures never escape native hook shutdown.
        }
    }

    private async Task ConsumeAsync()
    {
        await foreach (var dispatch in channel.Reader.ReadAllAsync().ConfigureAwait(false))
        {
            try
            {
                consumer(dispatch);
            }
            catch (Exception)
            {
                // A failed workflow consumer cannot stop global key delivery.
            }
        }
    }
}
