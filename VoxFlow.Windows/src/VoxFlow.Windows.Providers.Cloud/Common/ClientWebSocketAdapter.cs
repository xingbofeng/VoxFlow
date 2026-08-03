using System.Net.WebSockets;
using System.Text;

namespace VoxFlow.Windows.Providers.Cloud.Common;

public sealed class ClientWebSocketFactory : ICloudWebSocketFactory
{
    public ICloudWebSocket Create() => new ClientWebSocketAdapter();
}

public sealed class ClientWebSocketAdapter : ICloudWebSocket
{
    private const int DefaultReceiveBufferBytes = 4 * 1024;
    private const int DefaultMaximumMessageBytes = 1024 * 1024;
    private static readonly UTF8Encoding Utf8 = new(false, true);

    private readonly IClientWebSocketRuntime runtime;
    private readonly int receiveBufferBytes;
    private readonly int maximumMessageBytes;
    private int connectStarted;
    private int closeStarted;
    private int disposed;

    public ClientWebSocketAdapter()
        : this(
            new SystemClientWebSocketRuntime(),
            DefaultReceiveBufferBytes,
            DefaultMaximumMessageBytes)
    {
    }

    internal ClientWebSocketAdapter(
        IClientWebSocketRuntime runtime,
        int receiveBufferBytes = DefaultReceiveBufferBytes,
        int maximumMessageBytes = DefaultMaximumMessageBytes)
    {
        this.runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        if (receiveBufferBytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(receiveBufferBytes));
        }

        if (maximumMessageBytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumMessageBytes));
        }

        this.receiveBufferBytes = receiveBufferBytes;
        this.maximumMessageBytes = maximumMessageBytes;
    }

    public async ValueTask ConnectAsync(
        CloudWebSocketConnectRequest request,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(request);
        if (Interlocked.Exchange(ref connectStarted, 1) != 0)
        {
            throw new InvalidOperationException("The WebSocket connection has already started.");
        }

        foreach (var header in request.Headers)
        {
            runtime.SetRequestHeader(header.Key, header.Value);
        }

        await runtime.ConnectAsync(request.Uri, cancellationToken).ConfigureAwait(false);
    }

    public ValueTask SendBinaryAsync(
        ReadOnlyMemory<byte> payload,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        return runtime.SendAsync(
            payload,
            WebSocketMessageType.Binary,
            endOfMessage: true,
            cancellationToken);
    }

    public ValueTask SendTextAsync(
        string payload,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(payload);
        return runtime.SendAsync(
            Utf8.GetBytes(payload),
            WebSocketMessageType.Text,
            endOfMessage: true,
            cancellationToken);
    }

    public async ValueTask<CloudWebSocketReceiveMessage> ReceiveAsync(
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        var buffer = new byte[receiveBufferBytes];
        using var message = new MemoryStream();
        WebSocketMessageType? expectedType = null;

        while (true)
        {
            var result = await runtime.ReceiveAsync(buffer, cancellationToken)
                .ConfigureAwait(false);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                return CloudWebSocketReceiveMessage.Closed();
            }

            expectedType ??= result.MessageType;
            if (result.MessageType != expectedType)
            {
                throw new InvalidDataException(
                    "A fragmented WebSocket message changed its frame type.");
            }

            if (checked(message.Length + result.Count) > maximumMessageBytes)
            {
                throw new InvalidDataException("The WebSocket message exceeded the safe size limit.");
            }

            message.Write(buffer, 0, result.Count);
            if (!result.EndOfMessage)
            {
                continue;
            }

            var payload = message.ToArray();
            return expectedType == WebSocketMessageType.Text
                ? CloudWebSocketReceiveMessage.Text(Utf8.GetString(payload))
                : CloudWebSocketReceiveMessage.Binary(payload);
        }
    }

    public async ValueTask CloseAsync(CancellationToken cancellationToken)
    {
        if (Volatile.Read(ref disposed) != 0
            || Interlocked.Exchange(ref closeStarted, 1) != 0)
        {
            return;
        }

        if (runtime.State is WebSocketState.Open or WebSocketState.CloseReceived)
        {
            await runtime.CloseOutputAsync(
                WebSocketCloseStatus.NormalClosure,
                statusDescription: null,
                cancellationToken).ConfigureAwait(false);
        }
    }

    public ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) == 0)
        {
            runtime.Dispose();
        }

        return ValueTask.CompletedTask;
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
    }
}

internal interface IClientWebSocketRuntime : IDisposable
{
    WebSocketState State { get; }

    void SetRequestHeader(string name, string value);

    ValueTask ConnectAsync(Uri uri, CancellationToken cancellationToken);

    ValueTask SendAsync(
        ReadOnlyMemory<byte> payload,
        WebSocketMessageType messageType,
        bool endOfMessage,
        CancellationToken cancellationToken);

    ValueTask<ValueWebSocketReceiveResult> ReceiveAsync(
        Memory<byte> buffer,
        CancellationToken cancellationToken);

    ValueTask CloseOutputAsync(
        WebSocketCloseStatus closeStatus,
        string? statusDescription,
        CancellationToken cancellationToken);
}

internal sealed class SystemClientWebSocketRuntime : IClientWebSocketRuntime
{
    private readonly ClientWebSocket client = new();

    public WebSocketState State => client.State;

    public void SetRequestHeader(string name, string value) =>
        client.Options.SetRequestHeader(name, value);

    public ValueTask ConnectAsync(Uri uri, CancellationToken cancellationToken) =>
        new(client.ConnectAsync(uri, cancellationToken));

    public ValueTask SendAsync(
        ReadOnlyMemory<byte> payload,
        WebSocketMessageType messageType,
        bool endOfMessage,
        CancellationToken cancellationToken) =>
        client.SendAsync(payload, messageType, endOfMessage, cancellationToken);

    public ValueTask<ValueWebSocketReceiveResult> ReceiveAsync(
        Memory<byte> buffer,
        CancellationToken cancellationToken) =>
        client.ReceiveAsync(buffer, cancellationToken);

    public ValueTask CloseOutputAsync(
        WebSocketCloseStatus closeStatus,
        string? statusDescription,
        CancellationToken cancellationToken) =>
        new(client.CloseOutputAsync(closeStatus, statusDescription, cancellationToken));

    public void Dispose() => client.Dispose();
}
