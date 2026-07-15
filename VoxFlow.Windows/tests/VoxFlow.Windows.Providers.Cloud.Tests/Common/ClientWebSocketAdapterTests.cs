using System.Net.WebSockets;
using System.Text;
using VoxFlow.Windows.Providers.Cloud.Common;

namespace VoxFlow.Windows.Providers.Cloud.Tests.Common;

public sealed class ClientWebSocketAdapterTests
{
    [Fact]
    public async Task Connect_applies_runtime_only_headers_and_uses_the_original_URI()
    {
        var runtime = new FakeClientWebSocketRuntime();
        await using var adapter = new ClientWebSocketAdapter(runtime);
        var request = new CloudWebSocketConnectRequest(
            new Uri("wss://example.invalid/socket?signature=fixture"),
            new Dictionary<string, string> { ["Authorization"] = "Bearer fixture" });

        await adapter.ConnectAsync(request, CancellationToken.None);

        Assert.Equal(request.Uri, runtime.ConnectedUri);
        Assert.Equal("Bearer fixture", runtime.Headers["Authorization"]);
    }

    [Fact]
    public async Task Send_preserves_binary_and_UTF8_text_message_boundaries()
    {
        var runtime = new FakeClientWebSocketRuntime { State = WebSocketState.Open };
        await using var adapter = new ClientWebSocketAdapter(runtime);

        await adapter.SendBinaryAsync(
            new byte[] { 0, 1, 2, 255 },
            CancellationToken.None);
        await adapter.SendTextAsync("结束", CancellationToken.None);

        Assert.Collection(
            runtime.Sent,
            frame =>
            {
                Assert.Equal(WebSocketMessageType.Binary, frame.Type);
                Assert.Equal([0, 1, 2, 255], frame.Payload);
                Assert.True(frame.EndOfMessage);
            },
            frame =>
            {
                Assert.Equal(WebSocketMessageType.Text, frame.Type);
                Assert.Equal("结束", Encoding.UTF8.GetString(frame.Payload));
                Assert.True(frame.EndOfMessage);
            });
    }

    [Fact]
    public async Task Receive_assembles_fragmented_messages_and_maps_close()
    {
        var runtime = new FakeClientWebSocketRuntime();
        runtime.EnqueueReceive("分"u8.ToArray(), WebSocketMessageType.Text, endOfMessage: false);
        runtime.EnqueueReceive("片"u8.ToArray(), WebSocketMessageType.Text, endOfMessage: true);
        runtime.EnqueueClose();
        await using var adapter = new ClientWebSocketAdapter(runtime);

        var text = await adapter.ReceiveAsync(CancellationToken.None);
        var close = await adapter.ReceiveAsync(CancellationToken.None);

        Assert.Equal(CloudWebSocketMessageType.Text, text.Type);
        Assert.Equal("分片", text.GetText());
        Assert.Equal(CloudWebSocketMessageType.Close, close.Type);
    }

    [Fact]
    public async Task Receive_rejects_mixed_fragment_types_and_oversized_messages()
    {
        var mixed = new FakeClientWebSocketRuntime();
        mixed.EnqueueReceive([1], WebSocketMessageType.Text, endOfMessage: false);
        mixed.EnqueueReceive([2], WebSocketMessageType.Binary, endOfMessage: true);
        await using var mixedAdapter = new ClientWebSocketAdapter(mixed, maximumMessageBytes: 8);

        await Assert.ThrowsAsync<InvalidDataException>(async () =>
            await mixedAdapter.ReceiveAsync(CancellationToken.None));

        var oversized = new FakeClientWebSocketRuntime();
        oversized.EnqueueReceive([1, 2, 3], WebSocketMessageType.Binary, endOfMessage: false);
        oversized.EnqueueReceive([4, 5, 6], WebSocketMessageType.Binary, endOfMessage: true);
        await using var oversizedAdapter = new ClientWebSocketAdapter(
            oversized,
            receiveBufferBytes: 4,
            maximumMessageBytes: 4);

        await Assert.ThrowsAsync<InvalidDataException>(async () =>
            await oversizedAdapter.ReceiveAsync(CancellationToken.None));
    }

    [Fact]
    public async Task Close_and_dispose_are_idempotent()
    {
        var runtime = new FakeClientWebSocketRuntime { State = WebSocketState.Open };
        var adapter = new ClientWebSocketAdapter(runtime);

        await adapter.CloseAsync(CancellationToken.None);
        await adapter.CloseAsync(CancellationToken.None);
        await adapter.DisposeAsync();
        await adapter.DisposeAsync();

        Assert.Equal(1, runtime.CloseCalls);
        Assert.Equal(1, runtime.DisposeCalls);
    }

    private sealed class FakeClientWebSocketRuntime : IClientWebSocketRuntime
    {
        private readonly Queue<FakeReceive> receives = [];

        public Dictionary<string, string> Headers { get; } = [];

        public List<FakeSend> Sent { get; } = [];

        public Uri? ConnectedUri { get; private set; }

        public WebSocketState State { get; set; } = WebSocketState.None;

        public int CloseCalls { get; private set; }

        public int DisposeCalls { get; private set; }

        public void SetRequestHeader(string name, string value) => Headers[name] = value;

        public ValueTask ConnectAsync(Uri uri, CancellationToken cancellationToken)
        {
            ConnectedUri = uri;
            State = WebSocketState.Open;
            return ValueTask.CompletedTask;
        }

        public ValueTask SendAsync(
            ReadOnlyMemory<byte> payload,
            WebSocketMessageType messageType,
            bool endOfMessage,
            CancellationToken cancellationToken)
        {
            Sent.Add(new FakeSend(payload.ToArray(), messageType, endOfMessage));
            return ValueTask.CompletedTask;
        }

        public ValueTask<ValueWebSocketReceiveResult> ReceiveAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken)
        {
            var receive = receives.Dequeue();
            receive.Payload.CopyTo(buffer);
            return ValueTask.FromResult(new ValueWebSocketReceiveResult(
                receive.Payload.Length,
                receive.Type,
                receive.EndOfMessage));
        }

        public ValueTask CloseOutputAsync(
            WebSocketCloseStatus closeStatus,
            string? statusDescription,
            CancellationToken cancellationToken)
        {
            CloseCalls++;
            State = WebSocketState.Closed;
            return ValueTask.CompletedTask;
        }

        public void Dispose()
        {
            DisposeCalls++;
            State = WebSocketState.Closed;
        }

        public void EnqueueReceive(
            byte[] payload,
            WebSocketMessageType type,
            bool endOfMessage) => receives.Enqueue(new FakeReceive(payload, type, endOfMessage));

        public void EnqueueClose() => receives.Enqueue(new FakeReceive(
            [],
            WebSocketMessageType.Close,
            EndOfMessage: true));
    }

    private sealed record FakeReceive(
        byte[] Payload,
        WebSocketMessageType Type,
        bool EndOfMessage);

    private sealed record FakeSend(
        byte[] Payload,
        WebSocketMessageType Type,
        bool EndOfMessage);
}
