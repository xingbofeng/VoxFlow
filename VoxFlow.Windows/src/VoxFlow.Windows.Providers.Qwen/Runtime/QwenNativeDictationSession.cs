using System.Buffers.Binary;
using System.Threading.Channels;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Qwen.Native;

namespace VoxFlow.Windows.Providers.Qwen.Runtime;

internal sealed class QwenNativeDictationSession : IDictationAsrSession
{
    internal const int EventChannelCapacity = 64;

    private readonly IQwenNativeApi api;
    private readonly QwenRuntimeLease runtimeLease;
    private readonly QwenSessionSafeHandle session;
    private readonly Channel<QwenNativeEventData> events;
    private readonly CancellationTokenSource lifetime = new();
    private Task? pollTask;
    private Task? dispatchTask;
    private int started;
    private int cancelled;
    private int disposed;

    internal QwenNativeDictationSession(
        IQwenNativeApi api,
        QwenRuntimeLease runtimeLease,
        int variant)
    {
        this.api = api ?? throw new ArgumentNullException(nameof(api));
        this.runtimeLease = runtimeLease ?? throw new ArgumentNullException(nameof(runtimeLease));
        session = api.CreateSession(runtimeLease.Runtime, variant);
        events = Channel.CreateBounded<QwenNativeEventData>(new BoundedChannelOptions(EventChannelCapacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = true,
            AllowSynchronousContinuations = false,
        });
    }

    public event EventHandler<AsrPartialResult>? PartialReceived;

    public event EventHandler<AsrFinalResult>? FinalReceived;

    public event EventHandler<VoxFlowError>? Failed;

    public ValueTask StartAsync(CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        cancellationToken.ThrowIfCancellationRequested();
        if (Interlocked.CompareExchange(ref started, 1, 0) != 0)
        {
            throw new InvalidOperationException("The Qwen native session has already started.");
        }

        int status = api.Start(session);
        if (status != 0)
        {
            throw new QwenNativeCallException("session_start", status);
        }

        pollTask = Task.Run(() => PollLoopAsync(lifetime.Token), CancellationToken.None);
        dispatchTask = Task.Run(() => DispatchLoopAsync(lifetime.Token), CancellationToken.None);
        return ValueTask.CompletedTask;
    }

    public ValueTask PushAudioAsync(
        ReadOnlyMemory<byte> pcmS16LittleEndian,
        CancellationToken cancellationToken)
    {
        EnsureActive(cancellationToken);
        if ((pcmS16LittleEndian.Length & 1) != 0)
        {
            throw new ArgumentException(
                "PCM S16LE audio must contain complete 16-bit samples.",
                nameof(pcmS16LittleEndian));
        }

        short[] samples = new short[pcmS16LittleEndian.Length / sizeof(short)];
        ReadOnlySpan<byte> source = pcmS16LittleEndian.Span;
        for (int index = 0; index < samples.Length; index++)
        {
            samples[index] = BinaryPrimitives.ReadInt16LittleEndian(
                source.Slice(index * sizeof(short), sizeof(short)));
        }

        int status = api.PushPcm16(session, samples);
        if (status != 0)
        {
            throw new QwenNativeCallException("session_push_pcm16", status);
        }

        return ValueTask.CompletedTask;
    }

    public async ValueTask FinishAsync(CancellationToken cancellationToken)
    {
        EnsureActive(cancellationToken);
        int status = await Task.Run(
            () => api.Finish(session),
            cancellationToken).ConfigureAwait(false);
        if (status != 0)
        {
            await events.Writer.WriteAsync(
                new QwenNativeEventData(
                    QwenNativeEventKind.Error,
                    0,
                    api.GetLastError(session),
                    status),
                cancellationToken).ConfigureAwait(false);
        }
    }

    public async ValueTask CancelAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (Interlocked.Exchange(ref cancelled, 1) != 0)
        {
            return;
        }

        api.Cancel(session);
        lifetime.Cancel();
        events.Writer.TryComplete();
        await AwaitBackgroundTasksAsync().ConfigureAwait(false);
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0)
        {
            return;
        }

        if (Interlocked.Exchange(ref cancelled, 1) == 0)
        {
            api.Cancel(session);
        }

        lifetime.Cancel();
        events.Writer.TryComplete();
        await AwaitBackgroundTasksAsync().ConfigureAwait(false);
        session.Dispose();
        await runtimeLease.DisposeAsync().ConfigureAwait(false);
        lifetime.Dispose();
    }

    private async Task PollLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                QwenNativePollResult result = api.Poll(session, out QwenNativeEventData @event);
                if (result == QwenNativePollResult.Event)
                {
                    await events.Writer.WriteAsync(@event, cancellationToken).ConfigureAwait(false);
                    continue;
                }

                if (result == QwenNativePollResult.Completed)
                {
                    break;
                }

                if (result == QwenNativePollResult.Error)
                {
                    await events.Writer.WriteAsync(
                        new QwenNativeEventData(
                            QwenNativeEventKind.Error,
                            0,
                            api.GetLastError(session),
                            0),
                        cancellationToken).ConfigureAwait(false);
                    break;
                }

                await Task.Delay(TimeSpan.FromMilliseconds(2), cancellationToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception)
        {
            events.Writer.TryWrite(new QwenNativeEventData(
                QwenNativeEventKind.Error,
                0,
                "The native Qwen event pump failed.",
                0));
        }
        finally
        {
            events.Writer.TryComplete();
        }
    }

    private async Task DispatchLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            await foreach (QwenNativeEventData @event in events.Reader.ReadAllAsync(cancellationToken).ConfigureAwait(false))
            {
                if (Volatile.Read(ref cancelled) != 0)
                {
                    continue;
                }

                switch (@event.Kind)
                {
                    case QwenNativeEventKind.Partial:
                        PartialReceived?.Invoke(
                            this,
                            new AsrPartialResult(@event.Text, Math.Max(0, @event.Revision)));
                        break;
                    case QwenNativeEventKind.Final:
                        FinalReceived?.Invoke(this, new AsrFinalResult(@event.Text));
                        break;
                    case QwenNativeEventKind.Error:
                        Failed?.Invoke(
                            this,
                            new VoxFlowError(
                                VoxFlowErrorCode.NativeRuntimeFailure,
                                AsrProviderId.Qwen));
                        break;
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
    }

    private void EnsureActive(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        if (Volatile.Read(ref started) == 0)
        {
            throw new InvalidOperationException("The Qwen native session has not started.");
        }

        if (Volatile.Read(ref cancelled) != 0)
        {
            throw new OperationCanceledException("The Qwen native session was cancelled.");
        }
    }

    private async Task AwaitBackgroundTasksAsync()
    {
        Task[] tasks = new[] { pollTask, dispatchTask }
            .Where(task => task is not null)
            .Cast<Task>()
            .ToArray();
        if (tasks.Length == 0)
        {
            return;
        }

        try
        {
            await Task.WhenAll(tasks).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }
    }
}
