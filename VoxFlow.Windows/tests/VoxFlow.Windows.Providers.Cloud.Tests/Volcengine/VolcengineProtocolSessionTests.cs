using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Providers.Cloud.Volcengine;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Providers.Cloud.Tests.Volcengine;

public sealed class VolcengineProtocolSessionTests
{
    private static readonly VolcengineAsrCredentials Credentials = new(
        "fixture-app-id",
        "fixture-access-token",
        "fixture-secret-key");

    [Fact]
    public async Task Start_sends_gzipped_full_client_JSON_with_sequence_one_and_official_headers()
    {
        await using var fixture = new Fixture();

        await fixture.Session.StartAsync(CancellationToken.None);

        Assert.Equal("fixture-app-id", fixture.Socket.Request!.Headers["X-Api-App-Key"]);
        Assert.Equal("fixture-access-token", fixture.Socket.Request.Headers["X-Api-Access-Key"]);
        Assert.Equal("volc.bigasr.sauc.duration", fixture.Socket.Request.Headers["X-Api-Resource-Id"]);
        Assert.Equal("fixture-connect-id", fixture.Socket.Request.Headers["X-Api-Connect-Id"]);
        Assert.DoesNotContain(Credentials.SecretKey, fixture.Socket.Request.ToString(), StringComparison.Ordinal);

        var frame = VolcengineProtocolFrame.Decode(Assert.Single(fixture.Socket.SentBinary));
        Assert.Equal(VolcengineMessageType.FullClientRequest, frame.MessageType);
        Assert.Equal(VolcengineMessageFlags.PositiveSequence, frame.Flags);
        Assert.Equal(1, frame.Sequence);
        Assert.Equal(VolcengineSerialization.Json, frame.Serialization);
        Assert.Equal(VolcengineCompression.Gzip, frame.Compression);
        using var payload = JsonDocument.Parse(frame.Payload);
        Assert.Equal("VoxFlow", payload.RootElement.GetProperty("user").GetProperty("uid").GetString());
        Assert.Equal("pcm", payload.RootElement.GetProperty("audio").GetProperty("format").GetString());
        Assert.Equal(16_000, payload.RootElement.GetProperty("audio").GetProperty("rate").GetInt32());
        Assert.Equal(16, payload.RootElement.GetProperty("audio").GetProperty("bits").GetInt32());
        Assert.Equal(1, payload.RootElement.GetProperty("audio").GetProperty("channel").GetInt32());
        Assert.Equal("bigmodel", payload.RootElement.GetProperty("request").GetProperty("model_name").GetString());
        Assert.Equal("full", payload.RootElement.GetProperty("request").GetProperty("result_type").GetString());
    }

    [Fact]
    public async Task Audio_only_frames_are_gzipped_with_incrementing_sequence_then_negative_end_frame()
    {
        await using var fixture = await Fixture.StartedAsync();
        var first = new byte[] { 0, 1, 2, 3 };
        var second = new byte[] { 4, 5, 6, 7 };

        await fixture.Session.PushAudioAsync(first, CancellationToken.None);
        await fixture.Session.PushAudioAsync(second, CancellationToken.None);
        await fixture.Session.FinishAsync(CancellationToken.None);

        var frames = fixture.Socket.SentBinary
            .Select(VolcengineProtocolFrame.Decode)
            .ToArray();
        Assert.Equal(4, frames.Length);
        Assert.Equal(
            [1, 2, 3, null],
            frames.Select(frame => frame.Sequence).ToArray());
        Assert.Equal(first, frames[1].Payload);
        Assert.Equal(second, frames[2].Payload);
        Assert.All(
            frames.Skip(1).Take(2),
            frame =>
            {
                Assert.Equal(VolcengineMessageType.AudioOnlyRequest, frame.MessageType);
                Assert.Equal(VolcengineCompression.Gzip, frame.Compression);
                Assert.Equal(VolcengineSerialization.None, frame.Serialization);
            });
        Assert.Equal(VolcengineMessageFlags.NegativeSequence, frames[^1].Flags);
        Assert.Equal(VolcengineCompression.None, frames[^1].Compression);
        Assert.Empty(frames[^1].Payload);
        Assert.Equal(
            new byte[] { 0x11, 0x22, 0x00, 0x00, 0, 0, 0, 0 },
            fixture.Socket.SentBinary[^1]);
    }

    [Fact]
    public async Task Authoritative_full_text_replaces_partial_until_one_unique_final()
    {
        await using var fixture = await Fixture.StartedAsync();

        fixture.Socket.EnqueueBinary(ServerResponse("你", isFinal: false, sequence: 1));
        fixture.Socket.EnqueueBinary(ServerResponse("你好", isFinal: false, sequence: 2));
        fixture.Socket.EnqueueBinary(ServerResponse("你好，码上写。", isFinal: true));

        var final = await fixture.Final.Task.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Equal("你好，码上写。", final.Text);
        Assert.Equal(["你", "你好", "你好，码上写。"], fixture.Partials.Select(value => value.Text));
        Assert.Equal([1L, 2L, 3L], fixture.Partials.Select(value => value.Revision));
        Assert.Equal(1, fixture.FinalCount);

        fixture.Socket.EnqueueBinary(ServerResponse("late", isFinal: true));
        await Task.Delay(20);
        Assert.Equal(1, fixture.FinalCount);
    }

    [Fact]
    public async Task Provider_error_is_classified_and_never_exposes_server_text_or_secret_key()
    {
        await using var fixture = await Fixture.StartedAsync();
        const string unsafeServerText = "rejected fixture-secret-key and request details";

        fixture.Socket.EnqueueBinary(ServerError(45000030, unsafeServerText));

        var failure = await fixture.Failure.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Equal(VoxFlowErrorCode.ProviderFailure, failure.Code);
        Assert.Equal(AsrProviderId.Volcengine, failure.Provider);
        Assert.True(fixture.Socket.IsClosed);
        Assert.DoesNotContain(unsafeServerText, failure.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(Credentials.SecretKey, failure.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Final_timeout_uses_controlled_time_closes_transport_and_stops_later_audio()
    {
        await using var fixture = await Fixture.StartedAsync(finalTimeout: TimeSpan.FromSeconds(5));
        await fixture.Session.FinishAsync(CancellationToken.None);
        var before = fixture.Socket.SentBinary.Count;

        fixture.Time.Advance(TimeSpan.FromSeconds(5));
        var failure = await fixture.Failure.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await fixture.Session.PushAudioAsync(new byte[] { 0, 0 }, CancellationToken.None);

        Assert.Equal(VoxFlowErrorCode.FinalTimeout, failure.Code);
        Assert.Equal(before, fixture.Socket.SentBinary.Count);
        Assert.True(fixture.Socket.IsClosed);
        Assert.Equal(1, fixture.FailureCount);
    }

    [Fact]
    public async Task Cancel_closes_transport_and_drops_late_partial_final_and_audio()
    {
        await using var fixture = await Fixture.StartedAsync();

        await fixture.Session.CancelAsync(CancellationToken.None);
        fixture.Socket.EnqueueBinary(ServerResponse("late", isFinal: true));
        await fixture.Session.PushAudioAsync(new byte[] { 0, 0 }, CancellationToken.None);
        await Task.Delay(20);

        Assert.True(fixture.Socket.IsClosed);
        Assert.Empty(fixture.Partials);
        Assert.Equal(0, fixture.FinalCount);
        Assert.Equal(0, fixture.FailureCount);
        Assert.Single(fixture.Socket.SentBinary);
    }

    [Fact]
    public async Task Early_final_stops_all_later_audio_and_finish_sends()
    {
        await using var fixture = await Fixture.StartedAsync();
        fixture.Socket.EnqueueBinary(ServerResponse("完成。", isFinal: true));
        await fixture.Final.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var before = fixture.Socket.SentBinary.Count;

        await fixture.Session.PushAudioAsync(new byte[] { 0, 0 }, CancellationToken.None);
        await fixture.Session.FinishAsync(CancellationToken.None);

        Assert.Equal(before, fixture.Socket.SentBinary.Count);
    }

    private static byte[] ServerResponse(
        string text,
        bool isFinal,
        int sequence = -1) => EncodeServerFrame(
            messageType: 0x9,
            flags: (byte)(isFinal ? 0x2 : 0x1),
            sequence: isFinal ? null : sequence,
            JsonSerializer.SerializeToUtf8Bytes(new
            {
                result = new { text },
                is_final = isFinal,
            }));

    private static byte[] ServerError(int code, string message) => EncodeServerFrame(
        messageType: 0xF,
        flags: 0,
        sequence: null,
        JsonSerializer.SerializeToUtf8Bytes(new { code, message }));

    private static byte[] EncodeServerFrame(
        byte messageType,
        byte flags,
        int? sequence,
        byte[] payload)
    {
        using var output = new MemoryStream();
        output.WriteByte(0x11);
        output.WriteByte((byte)((messageType << 4) | flags));
        output.WriteByte(0x11);
        output.WriteByte(0);
        if (sequence is not null)
        {
            Span<byte> encodedSequence = stackalloc byte[4];
            BinaryPrimitives.WriteInt32BigEndian(encodedSequence, sequence.Value);
            output.Write(encodedSequence);
        }

        using var compressed = new MemoryStream();
        using (var gzip = new GZipStream(compressed, CompressionLevel.SmallestSize, leaveOpen: true))
        {
            gzip.Write(payload);
        }

        var encodedPayload = compressed.ToArray();
        Span<byte> length = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(length, (uint)encodedPayload.Length);
        output.Write(length);
        output.Write(encodedPayload);
        return output.ToArray();
    }

    private sealed class Fixture : IAsyncDisposable
    {
        public Fixture(TimeSpan? finalTimeout = null)
        {
            Time = new ControlledTimeProvider(
                new DateTimeOffset(2026, 7, 11, 0, 0, 0, TimeSpan.Zero));
            Socket = new FakeCloudWebSocket();
            Session = new VolcengineRealtimeAsrSession(
                Credentials,
                new SingleSocketFactory(Socket),
                connectIdGenerator: () => "fixture-connect-id",
                timeProvider: Time,
                finalTimeout: finalTimeout ?? TimeSpan.FromSeconds(15));
            Session.PartialReceived += (_, value) => Partials.Enqueue(value);
            Session.FinalReceived += (_, value) =>
            {
                Interlocked.Increment(ref finalCount);
                Final.TrySetResult(value);
            };
            Session.Failed += (_, value) =>
            {
                Interlocked.Increment(ref failureCount);
                Failure.TrySetResult(value);
            };
        }

        private int finalCount;
        private int failureCount;

        public ControlledTimeProvider Time { get; }

        public FakeCloudWebSocket Socket { get; }

        public VolcengineRealtimeAsrSession Session { get; }

        public ConcurrentQueue<AsrPartialResult> Partials { get; } = new();

        public TaskCompletionSource<AsrFinalResult> Final { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource<VoxFlowError> Failure { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public int FinalCount => Volatile.Read(ref finalCount);

        public int FailureCount => Volatile.Read(ref failureCount);

        public static async Task<Fixture> StartedAsync(TimeSpan? finalTimeout = null)
        {
            var fixture = new Fixture(finalTimeout);
            await fixture.Session.StartAsync(CancellationToken.None);
            return fixture;
        }

        public ValueTask DisposeAsync() => Session.DisposeAsync();
    }

    private sealed class SingleSocketFactory(ICloudWebSocket socket) : ICloudWebSocketFactory
    {
        public ICloudWebSocket Create() => socket;
    }

    private sealed class FakeCloudWebSocket : ICloudWebSocket
    {
        private readonly Channel<CloudWebSocketReceiveMessage> incoming =
            Channel.CreateUnbounded<CloudWebSocketReceiveMessage>();
        private readonly object gate = new();

        public CloudWebSocketConnectRequest? Request { get; private set; }

        public List<byte[]> SentBinary { get; } = [];

        public bool IsClosed { get; private set; }

        public ValueTask ConnectAsync(
            CloudWebSocketConnectRequest request,
            CancellationToken cancellationToken)
        {
            Request = request;
            return ValueTask.CompletedTask;
        }

        public ValueTask SendBinaryAsync(
            ReadOnlyMemory<byte> payload,
            CancellationToken cancellationToken)
        {
            lock (gate)
            {
                if (!IsClosed)
                {
                    SentBinary.Add(payload.ToArray());
                }
            }

            return ValueTask.CompletedTask;
        }

        public ValueTask SendTextAsync(
            string payload,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException("Volcengine uses binary WebSocket messages only.");

        public ValueTask<CloudWebSocketReceiveMessage> ReceiveAsync(
            CancellationToken cancellationToken) =>
            incoming.Reader.ReadAsync(cancellationToken);

        public ValueTask CloseAsync(CancellationToken cancellationToken)
        {
            lock (gate)
            {
                IsClosed = true;
            }

            incoming.Writer.TryWrite(CloudWebSocketReceiveMessage.Closed());
            return ValueTask.CompletedTask;
        }

        public ValueTask DisposeAsync()
        {
            incoming.Writer.TryComplete();
            return ValueTask.CompletedTask;
        }

        public void EnqueueBinary(byte[] payload) =>
            incoming.Writer.TryWrite(CloudWebSocketReceiveMessage.Binary(payload));
    }
}
