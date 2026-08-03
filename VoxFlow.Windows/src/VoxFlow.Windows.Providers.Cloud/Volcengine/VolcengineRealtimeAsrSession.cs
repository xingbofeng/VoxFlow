using System.Text.Json;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Common;

namespace VoxFlow.Windows.Providers.Cloud.Volcengine;

public sealed class VolcengineAsrSessionException
    : Exception, IFileTranscriptionProviderErrorException
{
    public VolcengineAsrSessionException(string safeErrorCode, VoxFlowError error)
        : base($"Volcengine real-time ASR failed ({safeErrorCode}).")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(safeErrorCode);
        SafeErrorCode = safeErrorCode;
        Error = error ?? throw new ArgumentNullException(nameof(error));
    }

    public string SafeErrorCode { get; }

    public VoxFlowError Error { get; }
}

public sealed class VolcengineRealtimeAsrSession : IDictationAsrSession
{
    private readonly object stateGate = new();
    private readonly SemaphoreSlim sendGate = new(1, 1);
    private readonly CancellationTokenSource lifetime = new();
    private readonly VolcengineAsrCredentials credentials;
    private readonly ICloudWebSocketFactory socketFactory;
    private readonly Func<string> connectIdGenerator;
    private readonly TimeProvider timeProvider;
    private readonly TimeSpan finalTimeout;

    private ICloudWebSocket? socket;
    private Task? receiveLoop;
    private Task? finalTimeoutTask;
    private SessionState state;
    private string currentText = string.Empty;
    private long revision;
    private int nextSequence = 2;
    private int closeStarted;
    private int disposed;

    public VolcengineRealtimeAsrSession(
        VolcengineAsrCredentials credentials,
        ICloudWebSocketFactory socketFactory,
        Func<string>? connectIdGenerator = null,
        TimeProvider? timeProvider = null,
        TimeSpan? finalTimeout = null)
    {
        ArgumentNullException.ThrowIfNull(credentials);
        if (!credentials.IsComplete)
        {
            throw new ArgumentException(
                "Complete Volcengine credentials are required.",
                nameof(credentials));
        }

        this.credentials = credentials.Normalized();
        this.socketFactory = socketFactory
            ?? throw new ArgumentNullException(nameof(socketFactory));
        this.connectIdGenerator = connectIdGenerator
            ?? (() => Guid.NewGuid().ToString());
        this.timeProvider = timeProvider ?? TimeProvider.System;
        this.finalTimeout = finalTimeout ?? TimeSpan.FromSeconds(15);
        if (this.finalTimeout <= TimeSpan.Zero
            || this.finalTimeout == Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(finalTimeout));
        }
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
                throw new InvalidOperationException("The Volcengine ASR session already started.");
            }

            state = SessionState.Starting;
        }

        try
        {
            var connectId = connectIdGenerator();
            ArgumentException.ThrowIfNullOrWhiteSpace(connectId);
            socket = socketFactory.Create()
                ?? throw new InvalidOperationException("No cloud WebSocket was created.");
            var descriptor = VolcengineHandshakeDescriptor.Create(credentials, connectId);
            await socket.ConnectAsync(
                    new CloudWebSocketConnectRequest(
                        descriptor.Endpoint,
                        descriptor.Headers),
                    cancellationToken)
                .ConfigureAwait(false);
            await socket.SendBinaryAsync(CreateStartFrame(), cancellationToken)
                .ConfigureAwait(false);

            lock (stateGate)
            {
                if (state == SessionState.Starting)
                {
                    state = SessionState.Active;
                }
            }

            receiveLoop = ReceiveLoopAsync();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await CancelAsync(CancellationToken.None).ConfigureAwait(false);
            throw;
        }
        catch (Exception)
        {
            var failure = ExceptionFor(
                "networkFailure",
                VoxFlowErrorCode.NetworkFailure);
            await TransitionToFailureAsync(failure).ConfigureAwait(false);
            throw failure;
        }
    }

    public async ValueTask PushAudioAsync(
        ReadOnlyMemory<byte> pcmS16LittleEndian,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        if (pcmS16LittleEndian.IsEmpty || !IsActive())
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
            if (!IsActive())
            {
                return;
            }

            var sequence = checked(nextSequence++);
            var frame = VolcengineProtocolFrame.EncodeAudioOnlyRequest(
                pcmS16LittleEndian.Span,
                sequence);
            await GetSocket().SendBinaryAsync(frame, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            var failure = ExceptionFor(
                "networkFailure",
                VoxFlowErrorCode.NetworkFailure);
            await TransitionToFailureAsync(failure).ConfigureAwait(false);
            throw failure;
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
                throw new InvalidOperationException("The Volcengine ASR session is not recording.");
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

            await GetSocket().SendBinaryAsync(
                    VolcengineProtocolFrame.EncodeFinalAudioRequest(),
                    cancellationToken)
                .ConfigureAwait(false);
            finalTimeoutTask = WatchFinalTimeoutAsync();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            var failure = ExceptionFor(
                "networkFailure",
                VoxFlowErrorCode.NetworkFailure);
            await TransitionToFailureAsync(failure).ConfigureAwait(false);
            throw failure;
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
                // Receive failures are converted to safe provider errors.
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

        if (socket is not null)
        {
            await socket.DisposeAsync().ConfigureAwait(false);
        }

        lifetime.Dispose();
        sendGate.Dispose();
    }

    private async Task ReceiveLoopAsync()
    {
        try
        {
            while (!lifetime.IsCancellationRequested)
            {
                var message = await GetSocket().ReceiveAsync(lifetime.Token)
                    .ConfigureAwait(false);
                if (message.Type == CloudWebSocketMessageType.Close)
                {
                    if (!IsTerminalState())
                    {
                        await TransitionToFailureAsync(ExceptionFor(
                                "networkFailure",
                                VoxFlowErrorCode.NetworkFailure))
                            .ConfigureAwait(false);
                    }

                    return;
                }

                if (message.Type != CloudWebSocketMessageType.Binary)
                {
                    await TransitionToFailureAsync(ExceptionFor(
                            "invalidMessage",
                            VoxFlowErrorCode.ProviderFailure))
                        .ConfigureAwait(false);
                    return;
                }

                await HandleFrameAsync(
                        VolcengineProtocolFrame.Decode(message.Payload.Span))
                    .ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
            // A terminal state owns cancellation.
        }
        catch (JsonException)
        {
            await TransitionToFailureAsync(ExceptionFor(
                    "invalidMessage",
                    VoxFlowErrorCode.ProviderFailure))
                .ConfigureAwait(false);
        }
        catch (InvalidDataException)
        {
            await TransitionToFailureAsync(ExceptionFor(
                    "invalidMessage",
                    VoxFlowErrorCode.ProviderFailure))
                .ConfigureAwait(false);
        }
        catch (Exception)
        {
            await TransitionToFailureAsync(ExceptionFor(
                    "networkFailure",
                    VoxFlowErrorCode.NetworkFailure))
                .ConfigureAwait(false);
        }
    }

    private async Task HandleFrameAsync(VolcengineProtocolFrame frame)
    {
        if (IsTerminalState() || frame.MessageType == VolcengineMessageType.ServerAck)
        {
            return;
        }

        if (frame.MessageType == VolcengineMessageType.ServerErrorResponse)
        {
            using var errorDocument = JsonDocument.Parse(frame.Payload);
            var errorCode = errorDocument.RootElement.TryGetProperty("code", out var codeElement)
                && codeElement.TryGetInt32(out var parsed)
                ? parsed
                : -1;
            await TransitionToFailureAsync(ClassifyProviderError(errorCode))
                .ConfigureAwait(false);
            return;
        }

        if (frame.MessageType != VolcengineMessageType.FullServerResponse
            || frame.Serialization != VolcengineSerialization.Json)
        {
            throw new InvalidDataException("Unexpected Volcengine server frame.");
        }

        using var document = JsonDocument.Parse(frame.Payload);
        var root = document.RootElement;
        if (root.TryGetProperty("code", out var providerCode)
            && providerCode.TryGetInt32(out var code)
            && code != 0)
        {
            await TransitionToFailureAsync(ClassifyProviderError(code))
                .ConfigureAwait(false);
            return;
        }

        var transcript = GetTranscript(root);
        var jsonFinal = root.TryGetProperty("is_final", out var finalElement)
            && finalElement.ValueKind is JsonValueKind.True;
        await PublishTranscriptAsync(transcript, frame.IsFinal || jsonFinal)
            .ConfigureAwait(false);
    }

    private async Task PublishTranscriptAsync(string transcript, bool isFinal)
    {
        AsrPartialResult? partial = null;
        lock (stateGate)
        {
            if (IsTerminal(state))
            {
                return;
            }

            if (!string.Equals(transcript, currentText, StringComparison.Ordinal))
            {
                currentText = transcript;
                revision = checked(revision + 1);
                partial = new AsrPartialResult(currentText, revision);
            }
        }

        if (partial is not null)
        {
            InvokeSafely(PartialReceived, partial);
        }

        if (isFinal)
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

            finalText = currentText;
            if (!string.IsNullOrWhiteSpace(finalText))
            {
                state = SessionState.Completed;
            }
        }

        if (string.IsNullOrWhiteSpace(finalText))
        {
            await TransitionToFailureAsync(ExceptionFor(
                    "emptyFinal",
                    VoxFlowErrorCode.EmptyFinal))
                .ConfigureAwait(false);
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
            await Task.Delay(finalTimeout, timeProvider, lifetime.Token)
                .ConfigureAwait(false);
            await TransitionToFailureAsync(ExceptionFor(
                    "finalTimeout",
                    VoxFlowErrorCode.FinalTimeout))
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
            // A final, provider error, or cancellation won the race.
        }
    }

    private async Task TransitionToFailureAsync(VolcengineAsrSessionException exception)
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

        lifetime.Cancel();
        await CloseOnceAsync(CancellationToken.None).ConfigureAwait(false);
        InvokeSafely(Failed, exception.Error);
    }

    private byte[] CreateStartFrame()
    {
        var payload = JsonSerializer.SerializeToUtf8Bytes(new
        {
            user = new { uid = "VoxFlow" },
            audio = new
            {
                format = "pcm",
                codec = "raw",
                rate = 16_000,
                bits = 16,
                channel = 1,
            },
            request = new
            {
                model_name = VolcengineAsrDefaults.Model,
                enable_punc = true,
                result_type = "full",
            },
        });
        return VolcengineProtocolFrame.EncodeFullClientRequest(payload);
    }

    private static string GetTranscript(JsonElement root)
    {
        if (root.TryGetProperty("result", out var result)
            && result.ValueKind == JsonValueKind.Object
            && result.TryGetProperty("text", out var resultText)
            && resultText.ValueKind == JsonValueKind.String)
        {
            return resultText.GetString() ?? string.Empty;
        }

        if (root.TryGetProperty("payload", out var payload)
            && payload.ValueKind == JsonValueKind.Object)
        {
            if (payload.TryGetProperty("result", out var payloadResult)
                && payloadResult.ValueKind == JsonValueKind.Object
                && payloadResult.TryGetProperty("text", out var nestedText)
                && nestedText.ValueKind == JsonValueKind.String)
            {
                return nestedText.GetString() ?? string.Empty;
            }

            if (payload.TryGetProperty("text", out var payloadText)
                && payloadText.ValueKind == JsonValueKind.String)
            {
                return payloadText.GetString() ?? string.Empty;
            }
        }

        return root.TryGetProperty("text", out var text)
            && text.ValueKind == JsonValueKind.String
            ? text.GetString() ?? string.Empty
            : string.Empty;
    }

    private static VolcengineAsrSessionException ClassifyProviderError(int code) =>
        code is 401 or 403 or 45000001 or 45000002
            ? ExceptionFor("authenticationFailed", VoxFlowErrorCode.AuthenticationFailed)
            : code is 429 or 45000029
                ? ExceptionFor("quotaExceeded", VoxFlowErrorCode.QuotaExceeded)
                : ExceptionFor("providerFailure", VoxFlowErrorCode.ProviderFailure);

    private static VolcengineAsrSessionException ExceptionFor(
        string safeCode,
        VoxFlowErrorCode errorCode) => new(
            safeCode,
            new VoxFlowError(errorCode, AsrProviderId.Volcengine));

    private ICloudWebSocket GetSocket() => socket
        ?? throw new InvalidOperationException("The Volcengine WebSocket is not connected.");

    private async ValueTask CloseOnceAsync(CancellationToken cancellationToken)
    {
        var current = socket;
        if (current is not null && Interlocked.Exchange(ref closeStarted, 1) == 0)
        {
            await current.CloseAsync(cancellationToken).ConfigureAwait(false);
        }
    }

    private bool IsActive()
    {
        lock (stateGate)
        {
            return state == SessionState.Active;
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
                // UI subscribers cannot tear down the provider transport.
            }
        }
    }

    private void ThrowIfDisposed() =>
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);

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
