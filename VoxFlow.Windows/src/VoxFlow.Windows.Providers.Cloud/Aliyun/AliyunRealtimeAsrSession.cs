using System.Text.Json;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Common;

namespace VoxFlow.Windows.Providers.Cloud.Aliyun;

public sealed class AliyunAsrProtocolException
    : Exception, IFileTranscriptionProviderErrorException
{
    public AliyunAsrProtocolException(string safeErrorCode, VoxFlowError error)
        : base($"Aliyun real-time ASR failed ({safeErrorCode}).")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(safeErrorCode);
        SafeErrorCode = safeErrorCode;
        Error = error ?? throw new ArgumentNullException(nameof(error));
    }

    public string SafeErrorCode { get; }

    public VoxFlowError Error { get; }
}

/// <summary>
/// DashScope duplex real-time ASR session. The wire sequence and payloads follow
/// the official WebSocket API:
/// https://help.aliyun.com/en/model-studio/fun-asr-realtime-websocket-api
/// </summary>
public sealed class AliyunRealtimeAsrSession : IDictationAsrSession
{
    private readonly object stateGate = new();
    private readonly SemaphoreSlim sendGate = new(1, 1);
    private readonly CancellationTokenSource lifetime = new();
    private readonly TaskCompletionSource<AliyunAsrProtocolException?> taskStarted = new(
        TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly string apiKey;
    private readonly ICloudWebSocketFactory socketFactory;
    private readonly Func<Guid> taskIdGenerator;
    private readonly TimeProvider timeProvider;
    private readonly TimeSpan connectionTimeout;
    private readonly SortedDictionary<int, Sentence> sentences = [];

    private ICloudWebSocket? socket;
    private Task? receiveLoop;
    private SessionState state;
    private Guid taskId;
    private string lastPartial = string.Empty;
    private long revision;
    private int closeStarted;
    private int disposed;

    public AliyunRealtimeAsrSession(
        string apiKey,
        ICloudWebSocketFactory socketFactory,
        Func<Guid>? taskIdGenerator = null,
        TimeProvider? timeProvider = null,
        TimeSpan? connectionTimeout = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(apiKey);
        this.apiKey = apiKey.Trim();
        this.socketFactory = socketFactory
            ?? throw new ArgumentNullException(nameof(socketFactory));
        this.taskIdGenerator = taskIdGenerator ?? Guid.NewGuid;
        this.timeProvider = timeProvider ?? TimeProvider.System;
        this.connectionTimeout = connectionTimeout ?? TimeSpan.FromSeconds(30);
        if (this.connectionTimeout <= TimeSpan.Zero
            || this.connectionTimeout == Timeout.InfiniteTimeSpan)
        {
            throw new ArgumentOutOfRangeException(nameof(connectionTimeout));
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
                throw new InvalidOperationException("The Aliyun ASR session already started.");
            }

            state = SessionState.Starting;
            taskId = taskIdGenerator();
            if (taskId == Guid.Empty)
            {
                state = SessionState.Failed;
                throw new InvalidOperationException("The Aliyun task ID cannot be empty.");
            }
        }

        try
        {
            socket = socketFactory.Create()
                ?? throw new InvalidOperationException("No cloud WebSocket was created.");
            var handshake = AliyunHandshakeDescriptor.Create(apiKey);
            await socket.ConnectAsync(
                    new CloudWebSocketConnectRequest(
                        handshake.Endpoint,
                        handshake.Headers),
                    cancellationToken)
                .ConfigureAwait(false);
            receiveLoop = ReceiveLoopAsync();
            await socket.SendTextAsync(CreateRunTaskMessage(), cancellationToken)
                .ConfigureAwait(false);

            using var timeoutCancellation = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken);
            var timeout = Task.Delay(
                connectionTimeout,
                timeProvider,
                timeoutCancellation.Token);
            var completed = await Task.WhenAny(taskStarted.Task, timeout).ConfigureAwait(false);
            if (completed != taskStarted.Task)
            {
                cancellationToken.ThrowIfCancellationRequested();
                await TransitionToFailureAsync(
                        new AliyunAsrProtocolException(
                            "connectionTimeout",
                            Error(VoxFlowErrorCode.NetworkFailure)))
                    .ConfigureAwait(false);
                throw new TimeoutException("Aliyun ASR task-started timed out.");
            }

            timeoutCancellation.Cancel();
            var startFailure = await taskStarted.Task
                .WaitAsync(cancellationToken)
                .ConfigureAwait(false);
            if (startFailure is not null)
            {
                throw startFailure;
            }

            lock (stateGate)
            {
                if (state == SessionState.Starting)
                {
                    state = SessionState.Active;
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await CancelAsync(CancellationToken.None).ConfigureAwait(false);
            throw;
        }
        catch (TimeoutException)
        {
            throw;
        }
        catch (AliyunAsrProtocolException)
        {
            throw;
        }
        catch (Exception)
        {
            var failure = new AliyunAsrProtocolException(
                "networkFailure",
                Error(VoxFlowErrorCode.NetworkFailure));
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

            await GetSocket().SendBinaryAsync(pcmS16LittleEndian, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            var failure = new AliyunAsrProtocolException(
                "networkFailure",
                Error(VoxFlowErrorCode.NetworkFailure));
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
                throw new InvalidOperationException("The Aliyun ASR session is not recording.");
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

            await GetSocket().SendTextAsync(
                    CreateFinishTaskMessage(),
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            var failure = new AliyunAsrProtocolException(
                "networkFailure",
                Error(VoxFlowErrorCode.NetworkFailure));
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
        taskStarted.TrySetCanceled(lifetime.Token);
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
        taskStarted.TrySetCanceled(lifetime.Token);
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
                // Receive failures are already converted to a safe provider error.
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
                        await TransitionToFailureAsync(
                                new AliyunAsrProtocolException(
                                    "networkFailure",
                                    Error(VoxFlowErrorCode.NetworkFailure)))
                            .ConfigureAwait(false);
                    }

                    return;
                }

                if (message.Type != CloudWebSocketMessageType.Text)
                {
                    await TransitionToFailureAsync(
                            new AliyunAsrProtocolException(
                                "invalidMessage",
                                Error(VoxFlowErrorCode.ProviderFailure)))
                        .ConfigureAwait(false);
                    return;
                }

                await HandleMessageAsync(message.GetText()).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
            // A terminal state owns cancellation.
        }
        catch (JsonException)
        {
            await TransitionToFailureAsync(
                    new AliyunAsrProtocolException(
                        "invalidMessage",
                        Error(VoxFlowErrorCode.ProviderFailure)))
                .ConfigureAwait(false);
        }
        catch (Exception)
        {
            await TransitionToFailureAsync(
                    new AliyunAsrProtocolException(
                        "networkFailure",
                        Error(VoxFlowErrorCode.NetworkFailure)))
                .ConfigureAwait(false);
        }
    }

    private async Task HandleMessageAsync(string text)
    {
        using var document = JsonDocument.Parse(text, new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 32,
        });
        var root = document.RootElement;
        if (!root.TryGetProperty("header", out var header)
            || header.ValueKind != JsonValueKind.Object
            || !header.TryGetProperty("event", out var eventElement)
            || eventElement.ValueKind != JsonValueKind.String)
        {
            throw new JsonException("Aliyun ASR response header was invalid.");
        }

        if (header.TryGetProperty("task_id", out var taskElement)
            && taskElement.ValueKind == JsonValueKind.String
            && !string.Equals(
                taskElement.GetString(),
                taskId.ToString(),
                StringComparison.OrdinalIgnoreCase))
        {
            throw new JsonException("Aliyun ASR response task ID did not match.");
        }

        switch (eventElement.GetString())
        {
            case "task-started":
                taskStarted.TrySetResult(null);
                break;
            case "result-generated":
                PublishResult(root);
                break;
            case "task-finished":
                await CompleteFinalAsync().ConfigureAwait(false);
                break;
            case "task-failed":
                var providerCode = header.TryGetProperty("error_code", out var code)
                    && code.ValueKind == JsonValueKind.String
                    ? code.GetString()
                    : null;
                await TransitionToFailureAsync(ClassifyProviderFailure(providerCode))
                    .ConfigureAwait(false);
                break;
        }
    }

    private void PublishResult(JsonElement root)
    {
        if (IsTerminalState()
            || !root.TryGetProperty("payload", out var payload)
            || !payload.TryGetProperty("output", out var output)
            || !output.TryGetProperty("sentence", out var sentence)
            || sentence.ValueKind != JsonValueKind.Object)
        {
            return;
        }

        if (sentence.TryGetProperty("heartbeat", out var heartbeat)
            && heartbeat.ValueKind is JsonValueKind.True)
        {
            return;
        }

        if (!sentence.TryGetProperty("sentence_id", out var idElement)
            || !idElement.TryGetInt32(out var sentenceId)
            || sentenceId < 0
            || !sentence.TryGetProperty("text", out var textElement)
            || textElement.ValueKind != JsonValueKind.String)
        {
            throw new JsonException("Aliyun ASR sentence payload was invalid.");
        }

        var transcript = textElement.GetString() ?? string.Empty;
        var isFinalSentence = sentence.TryGetProperty("sentence_end", out var endElement)
            && endElement.ValueKind is JsonValueKind.True;
        string? partial = null;
        long partialRevision = 0;
        lock (stateGate)
        {
            if (IsTerminal(state))
            {
                return;
            }

            if (!sentences.TryGetValue(sentenceId, out var current) || !current.IsFinal)
            {
                sentences[sentenceId] = new Sentence(transcript, isFinalSentence);
            }

            var combined = string.Concat(sentences.Values.Select(value => value.Text));
            if (!string.Equals(combined, lastPartial, StringComparison.Ordinal))
            {
                lastPartial = combined;
                revision = checked(revision + 1);
                partial = combined;
                partialRevision = revision;
            }
        }

        if (partial is not null)
        {
            InvokeSafely(PartialReceived, new AsrPartialResult(partial, partialRevision));
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

            finalText = string.Concat(sentences.Values.Select(value => value.Text));
            if (!string.IsNullOrWhiteSpace(finalText))
            {
                state = SessionState.Completed;
            }
        }

        if (string.IsNullOrWhiteSpace(finalText))
        {
            await TransitionToFailureAsync(
                    new AliyunAsrProtocolException(
                        "emptyFinal",
                        Error(VoxFlowErrorCode.EmptyFinal)))
                .ConfigureAwait(false);
            return;
        }

        lifetime.Cancel();
        await CloseOnceAsync(CancellationToken.None).ConfigureAwait(false);
        InvokeSafely(FinalReceived, new AsrFinalResult(finalText));
    }

    private async Task TransitionToFailureAsync(AliyunAsrProtocolException exception)
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

        taskStarted.TrySetResult(exception);
        lifetime.Cancel();
        await CloseOnceAsync(CancellationToken.None).ConfigureAwait(false);
        InvokeSafely(Failed, exception.Error);
    }

    private string CreateRunTaskMessage() => JsonSerializer.Serialize(new
    {
        header = new
        {
            action = "run-task",
            task_id = taskId.ToString(),
            streaming = "duplex",
        },
        payload = new
        {
            task_group = "audio",
            task = "asr",
            function = "recognition",
            model = AliyunAsrDefaults.Model,
            parameters = new
            {
                format = "pcm",
                sample_rate = 16_000,
                punctuation_prediction_enabled = true,
            },
            input = new { },
        },
    });

    private string CreateFinishTaskMessage() => JsonSerializer.Serialize(new
    {
        header = new
        {
            action = "finish-task",
            task_id = taskId.ToString(),
            streaming = "duplex",
        },
        payload = new
        {
            input = new { },
        },
    });

    private static AliyunAsrProtocolException ClassifyProviderFailure(string? code)
    {
        var normalized = code ?? string.Empty;
        if (normalized.Contains("key", StringComparison.OrdinalIgnoreCase)
            || normalized.Contains("auth", StringComparison.OrdinalIgnoreCase)
            || normalized.Contains("unauthorized", StringComparison.OrdinalIgnoreCase))
        {
            return new AliyunAsrProtocolException(
                "authenticationFailed",
                Error(VoxFlowErrorCode.AuthenticationFailed));
        }

        if (normalized.Contains("quota", StringComparison.OrdinalIgnoreCase)
            || normalized.Contains("limit", StringComparison.OrdinalIgnoreCase))
        {
            return new AliyunAsrProtocolException(
                "quotaExceeded",
                Error(VoxFlowErrorCode.QuotaExceeded));
        }

        return new AliyunAsrProtocolException(
            "providerFailure",
            Error(VoxFlowErrorCode.ProviderFailure));
    }

    private ICloudWebSocket GetSocket() => socket
        ?? throw new InvalidOperationException("The Aliyun WebSocket is not connected.");

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

    private static VoxFlowError Error(VoxFlowErrorCode code) =>
        new(code, AsrProviderId.AliyunDashScope);

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

    private sealed record Sentence(string Text, bool IsFinal);

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
