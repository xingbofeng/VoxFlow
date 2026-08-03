using System.Text.Json;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Common;

namespace VoxFlow.Windows.Providers.Cloud.Tencent;

public sealed class TencentAsrSessionException
    : Exception, IFileTranscriptionProviderErrorException
{
    public TencentAsrSessionException(VoxFlowError error)
        : base($"Tencent real-time ASR failed ({error.Code}).")
    {
        Error = error ?? throw new ArgumentNullException(nameof(error));
    }

    public VoxFlowError Error { get; }
}

/// <summary>
/// Direct WebSocket adapter for Tencent Cloud real-time ASR. Protocol source:
/// https://cloud.tencent.com/document/product/1093/48982.
/// </summary>
public sealed class TencentAsrSession : IDictationAsrSession
{
    private const string EndMessage = "{\"type\":\"end\"}";
    private readonly object stateGate = new();
    private readonly SemaphoreSlim sendGate = new(1, 1);
    private readonly CancellationTokenSource lifetime = new();
    private readonly TaskCompletionSource<TencentAsrSessionException?> handshake = new(
        TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TencentAsrCredentials credentials;
    private readonly TencentAsrOptions options;
    private readonly string voiceId;
    private readonly TencentSignedUrlBuilder signedUrlBuilder;
    private readonly ICloudWebSocket transport;
    private readonly TimeProvider timeProvider;
    private readonly TimeSpan handshakeTimeout;
    private readonly TimeSpan finalTimeout;
    private readonly TencentResultAccumulator accumulator = new();

    private SessionState state;
    private Task? receiveLoop;
    private Task? finalTimeoutTask;
    private int closeStarted;
    private int disposed;

    public TencentAsrSession(
        TencentAsrCredentials credentials,
        TencentAsrOptions options,
        string voiceId,
        TencentSignedUrlBuilder signedUrlBuilder,
        ICloudWebSocket transport,
        TimeProvider? timeProvider = null,
        TimeSpan? handshakeTimeout = null,
        TimeSpan? finalTimeout = null)
    {
        this.credentials = credentials ?? throw new ArgumentNullException(nameof(credentials));
        this.options = options ?? throw new ArgumentNullException(nameof(options));
        ArgumentException.ThrowIfNullOrWhiteSpace(voiceId);
        this.voiceId = voiceId;
        this.signedUrlBuilder = signedUrlBuilder
            ?? throw new ArgumentNullException(nameof(signedUrlBuilder));
        this.transport = transport ?? throw new ArgumentNullException(nameof(transport));
        this.timeProvider = timeProvider ?? TimeProvider.System;
        this.handshakeTimeout = ValidateTimeout(
            handshakeTimeout ?? TimeSpan.FromSeconds(10),
            nameof(handshakeTimeout));
        this.finalTimeout = ValidateTimeout(
            finalTimeout ?? TimeSpan.FromSeconds(15),
            nameof(finalTimeout));
    }

    public event EventHandler<AsrPartialResult>? PartialReceived;

    public event EventHandler<AsrFinalResult>? FinalReceived;

    public event EventHandler<VoxFlowError>? Failed;

    public async ValueTask StartAsync(CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        lock (stateGate)
        {
            if (state != SessionState.Created)
            {
                throw new InvalidOperationException("The Tencent ASR session already started.");
            }

            state = SessionState.Starting;
        }

        try
        {
            var signed = signedUrlBuilder.Build(credentials, options, voiceId);
            await transport.ConnectAsync(
                new CloudWebSocketConnectRequest(signed.ConnectUri),
                cancellationToken).ConfigureAwait(false);
            receiveLoop = ReceiveLoopAsync();

            var timeout = Task.Delay(handshakeTimeout, timeProvider, cancellationToken);
            var completed = await Task.WhenAny(handshake.Task, timeout).ConfigureAwait(false);
            if (completed != handshake.Task)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var timeoutError = Error(VoxFlowErrorCode.NetworkFailure);
                await FailAsync(timeoutError).ConfigureAwait(false);
            }

            var failure = await handshake.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
            if (failure is not null)
            {
                throw failure;
            }

            lock (stateGate)
            {
                if (state == SessionState.Starting)
                {
                    state = SessionState.Active;
                }
            }
        }
        catch (OperationCanceledException)
        {
            await CancelAsync(CancellationToken.None).ConfigureAwait(false);
            throw;
        }
        catch (TencentAsrSessionException)
        {
            throw;
        }
        catch (Exception)
        {
            var failure = Error(VoxFlowErrorCode.NetworkFailure);
            await FailAsync(failure).ConfigureAwait(false);
            throw new TencentAsrSessionException(failure);
        }
    }

    public async ValueTask PushAudioAsync(
        ReadOnlyMemory<byte> pcmS16LittleEndian,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        if (IsTerminalOrNotRecording())
        {
            return;
        }

        if (pcmS16LittleEndian.IsEmpty)
        {
            return;
        }

        if ((pcmS16LittleEndian.Length & 1) != 0)
        {
            throw new ArgumentException(
                "PCM S16LE audio must contain complete 16-bit samples.",
                nameof(pcmS16LittleEndian));
        }

        await sendGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (IsTerminalOrNotRecording())
            {
                return;
            }

            await transport.SendBinaryAsync(pcmS16LittleEndian, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            var failure = Error(VoxFlowErrorCode.NetworkFailure);
            await FailAsync(failure).ConfigureAwait(false);
            throw new TencentAsrSessionException(failure);
        }
        finally
        {
            sendGate.Release();
        }
    }

    public async ValueTask FinishAsync(CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        lock (stateGate)
        {
            if (IsTerminal(state) || state == SessionState.Finishing)
            {
                return;
            }

            if (state != SessionState.Active)
            {
                throw new InvalidOperationException("The Tencent ASR session is not recording.");
            }

            state = SessionState.Finishing;
        }

        await sendGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (IsTerminalState())
            {
                return;
            }

            await transport.SendTextAsync(EndMessage, cancellationToken).ConfigureAwait(false);
            finalTimeoutTask = WatchFinalTimeoutAsync();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            var failure = Error(VoxFlowErrorCode.NetworkFailure);
            await FailAsync(failure).ConfigureAwait(false);
            throw new TencentAsrSessionException(failure);
        }
        finally
        {
            sendGate.Release();
        }
    }

    public async ValueTask CancelAsync(CancellationToken cancellationToken)
    {
        if (Volatile.Read(ref disposed) != 0)
        {
            return;
        }

        var shouldClose = false;
        lock (stateGate)
        {
            if (!IsTerminal(state))
            {
                state = SessionState.Cancelled;
                shouldClose = true;
            }
        }

        if (!shouldClose)
        {
            return;
        }

        lifetime.Cancel();
        handshake.TrySetCanceled(lifetime.Token);
        await CloseOnceAsync(cancellationToken).ConfigureAwait(false);
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0)
        {
            return;
        }

        var shouldClose = false;
        lock (stateGate)
        {
            if (!IsTerminal(state))
            {
                state = SessionState.Cancelled;
                shouldClose = true;
            }
        }

        lifetime.Cancel();
        handshake.TrySetCanceled(lifetime.Token);
        if (shouldClose)
        {
            await CloseOnceAsync(CancellationToken.None).ConfigureAwait(false);
        }

        if (receiveLoop is not null)
        {
            try
            {
                await receiveLoop.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // Lifetime cancellation is the normal disposal path.
            }
            catch
            {
                // Receive failures are surfaced through Failed before disposal.
            }
        }

        if (finalTimeoutTask is not null)
        {
            try
            {
                await finalTimeoutTask.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // Lifetime cancellation is the normal disposal path.
            }
        }

        await transport.DisposeAsync().ConfigureAwait(false);
        lifetime.Dispose();
        sendGate.Dispose();
    }

    private async Task ReceiveLoopAsync()
    {
        try
        {
            while (!lifetime.IsCancellationRequested)
            {
                var message = await transport.ReceiveAsync(lifetime.Token).ConfigureAwait(false);
                if (message.Type == CloudWebSocketMessageType.Close)
                {
                    if (!IsTerminalState())
                    {
                        await FailAsync(Error(VoxFlowErrorCode.NetworkFailure))
                            .ConfigureAwait(false);
                    }

                    return;
                }

                if (message.Type != CloudWebSocketMessageType.Text)
                {
                    await FailAsync(Error(VoxFlowErrorCode.ProviderFailure))
                        .ConfigureAwait(false);
                    return;
                }

                await HandleTextMessageAsync(message.GetText()).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
            // Terminal state owns cancellation.
        }
        catch (JsonException)
        {
            await FailAsync(Error(VoxFlowErrorCode.ProviderFailure)).ConfigureAwait(false);
        }
        catch (Exception)
        {
            await FailAsync(Error(VoxFlowErrorCode.NetworkFailure)).ConfigureAwait(false);
        }
    }

    private async Task HandleTextMessageAsync(string text)
    {
        TencentProtocolUpdate update;
        lock (stateGate)
        {
            if (IsTerminal(state))
            {
                return;
            }

            update = accumulator.Apply(text);
        }

        if (update.ProviderCode != 0)
        {
            await FailAsync(ClassifyProviderCode(update.ProviderCode)).ConfigureAwait(false);
            return;
        }

        handshake.TrySetResult(null);
        if (update.PartialText is not null)
        {
            InvokeSafely(
                PartialReceived,
                new AsrPartialResult(update.PartialText, update.PartialRevision));
        }

        if (update.IsFinal)
        {
            await CompleteFinalAsync().ConfigureAwait(false);
        }
    }

    private async Task CompleteFinalAsync()
    {
        string finalText;
        lock (stateGate)
        {
            if (IsTerminal(state))
            {
                return;
            }

            finalText = accumulator.CurrentText;
            if (string.IsNullOrWhiteSpace(finalText))
            {
                // Keep the transition outside the lock so failure close is awaitable.
                finalText = string.Empty;
            }
            else
            {
                state = SessionState.Completed;
            }
        }

        if (string.IsNullOrWhiteSpace(finalText))
        {
            await FailAsync(Error(VoxFlowErrorCode.EmptyFinal)).ConfigureAwait(false);
            return;
        }

        lifetime.Cancel();
        await CloseOnceAsync(CancellationToken.None).ConfigureAwait(false);
        InvokeSafely(FinalReceived, new AsrFinalResult(finalText));
    }

    private async Task WatchFinalTimeoutAsync()
    {
        try
        {
            await Task.Delay(finalTimeout, timeProvider, lifetime.Token).ConfigureAwait(false);
            await FailAsync(Error(VoxFlowErrorCode.FinalTimeout)).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
            // Final, cancel, or provider error won the terminal race.
        }
    }

    private async Task FailAsync(VoxFlowError error)
    {
        var shouldPublish = false;
        lock (stateGate)
        {
            if (!IsTerminal(state))
            {
                state = SessionState.Failed;
                shouldPublish = true;
            }
        }

        if (!shouldPublish)
        {
            return;
        }

        var exception = new TencentAsrSessionException(error);
        handshake.TrySetResult(exception);
        lifetime.Cancel();
        await CloseOnceAsync(CancellationToken.None).ConfigureAwait(false);
        InvokeSafely(Failed, error);
    }

    private async ValueTask CloseOnceAsync(CancellationToken cancellationToken)
    {
        if (Interlocked.Exchange(ref closeStarted, 1) == 0)
        {
            await transport.CloseAsync(cancellationToken).ConfigureAwait(false);
        }
    }

    private bool IsTerminalOrNotRecording()
    {
        lock (stateGate)
        {
            return state != SessionState.Active;
        }
    }

    private bool IsTerminalState()
    {
        lock (stateGate)
        {
            return IsTerminal(state);
        }
    }

    private static bool IsTerminal(SessionState value) => value is
        SessionState.Completed or
        SessionState.Failed or
        SessionState.Cancelled;

    private static VoxFlowError ClassifyProviderCode(int code) => code switch
    {
        4002 => Error(VoxFlowErrorCode.AuthenticationFailed),
        4004 or 4005 => Error(VoxFlowErrorCode.QuotaExceeded),
        4008 or 4009 or 5000 or 5001 or 5002 => Error(VoxFlowErrorCode.NetworkFailure),
        _ => Error(VoxFlowErrorCode.ProviderFailure),
    };

    private static VoxFlowError Error(VoxFlowErrorCode code) =>
        new(code, AsrProviderId.TencentCloud);

    private static TimeSpan ValidateTimeout(TimeSpan value, string parameterName)
    {
        if (value <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }

        return value;
    }

    private static void InvokeSafely<T>(EventHandler<T>? handler, T value)
    {
        if (handler is null)
        {
            return;
        }

        foreach (EventHandler<T> subscriber in handler.GetInvocationList())
        {
            try
            {
                subscriber.Invoke(null, value);
            }
            catch
            {
                // Provider transport must not be torn down by a presentation subscriber.
            }
        }
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
    }

    private enum SessionState
    {
        Created,
        Starting,
        Active,
        Finishing,
        Completed,
        Failed,
        Cancelled,
    }
}
