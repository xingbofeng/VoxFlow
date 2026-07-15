using System.Threading.Channels;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Providers.Cloud.Common;
using VoxFlow.Windows.Providers.Cloud.Tencent;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Providers.Cloud.Tests.Tencent;

public sealed class TencentAsrSessionTests
{
    [Fact]
    public async Task Handshake_uses_signed_defaults_then_sends_PCM_and_exact_end_message()
    {
        await using var fixture = await Fixture.StartedAsync();
        var frame = new byte[] { 0, 0, 255, 127, 0, 128 };

        await fixture.Session.PushAudioAsync(frame, CancellationToken.None);
        await fixture.Session.FinishAsync(CancellationToken.None);

        Assert.NotNull(fixture.Transport.ConnectRequest);
        Assert.Empty(fixture.Transport.ConnectRequest!.Headers);
        Assert.Contains("engine_model_type=16k_zh", fixture.Transport.ConnectRequest.Uri.Query, StringComparison.Ordinal);
        Assert.Contains("voice_format=1", fixture.Transport.ConnectRequest.Uri.Query, StringComparison.Ordinal);
        Assert.Contains("needvad=1", fixture.Transport.ConnectRequest.Uri.Query, StringComparison.Ordinal);
        Assert.Equal([frame], fixture.Transport.BinaryMessages);
        Assert.Equal(["{\"type\":\"end\"}"], fixture.Transport.TextMessages);
    }

    [Fact]
    public async Task Odd_length_audio_is_rejected_before_any_WebSocket_send()
    {
        await using var fixture = await Fixture.StartedAsync();

        await Assert.ThrowsAsync<ArgumentException>(async () =>
            await fixture.Session.PushAudioAsync(
                new byte[] { 0, 1, 2 },
                CancellationToken.None));

        Assert.Empty(fixture.Transport.BinaryMessages);
    }

    [Fact]
    public async Task Stable_indexes_and_current_revision_form_ordered_nonduplicated_partial_and_final()
    {
        await using var fixture = await Fixture.StartedAsync();

        fixture.Transport.EnqueueText(Result(sliceType: 2, index: 0, text: "稳定"));
        fixture.Transport.EnqueueText(Result(sliceType: 1, index: 1, text: "片"));
        fixture.Transport.EnqueueText(Result(sliceType: 1, index: 1, text: "片段"));
        fixture.Transport.EnqueueText(Result(sliceType: 2, index: 1, text: "片段"));
        fixture.Transport.EnqueueText(Result(sliceType: 2, index: 0, text: "不应替换"));
        fixture.Transport.EnqueueText("{\"code\":0,\"message\":\"success\",\"final\":1}");

        var final = await fixture.Final.Task.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Equal("稳定片段", final.Text);
        Assert.Contains(fixture.Partials, partial => partial.Text == "稳定片");
        Assert.Contains(fixture.Partials, partial => partial.Text == "稳定片段");
        Assert.DoesNotContain(fixture.Partials, partial => partial.Text.Contains("不应替换", StringComparison.Ordinal));
        Assert.Equal(
            Enumerable.Range(1, fixture.Partials.Count).Select(value => (long)value),
            fixture.Partials.Select(partial => partial.Revision));

        fixture.Transport.EnqueueText("{\"code\":0,\"message\":\"success\",\"final\":1}");
        await Task.Delay(20);
        Assert.Equal(1, fixture.FinalCount);
    }

    [Fact]
    public async Task Provider_error_is_classified_without_echoing_provider_message_or_signed_request()
    {
        const string unsafeProviderText = "authentication rejected fixture-sensitive-detail";
        await using var fixture = Fixture.Create();
        fixture.Transport.EnqueueText(
            $"{{\"code\":4002,\"message\":\"{unsafeProviderText}\",\"voice_id\":\"fixture\"}}");

        var exception = await Assert.ThrowsAsync<TencentAsrSessionException>(async () =>
            await fixture.Session.StartAsync(CancellationToken.None));

        Assert.Equal(VoxFlowErrorCode.AuthenticationFailed, exception.Error.Code);
        Assert.Equal(AsrProviderId.TencentCloud, exception.Error.Provider);
        Assert.Equal(VoxFlowErrorCode.AuthenticationFailed, (await fixture.Failure.Task).Code);
        Assert.DoesNotContain(unsafeProviderText, exception.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("signature", exception.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.True(fixture.Transport.CloseCalls >= 1);
    }

    [Fact]
    public async Task Final_timeout_stops_sends_closes_socket_and_emits_one_safe_failure()
    {
        await using var fixture = await Fixture.StartedAsync(finalTimeout: TimeSpan.FromSeconds(3));
        await fixture.Session.PushAudioAsync(new byte[] { 0, 0 }, CancellationToken.None);
        await fixture.Session.FinishAsync(CancellationToken.None);

        fixture.Time.Advance(TimeSpan.FromSeconds(4));
        var failure = await fixture.Failure.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var sendsBeforeLateAudio = fixture.Transport.BinaryMessages.Count;
        await fixture.Session.PushAudioAsync(new byte[] { 1, 0 }, CancellationToken.None);

        Assert.Equal(VoxFlowErrorCode.FinalTimeout, failure.Code);
        Assert.Equal(AsrProviderId.TencentCloud, failure.Provider);
        Assert.Equal(sendsBeforeLateAudio, fixture.Transport.BinaryMessages.Count);
        Assert.Equal(1, fixture.FailureCount);
        Assert.True(fixture.Transport.CloseCalls >= 1);
    }

    [Fact]
    public async Task Cancellation_closes_socket_and_discards_late_partial_final_and_audio()
    {
        await using var fixture = await Fixture.StartedAsync();

        await fixture.Session.CancelAsync(CancellationToken.None);
        fixture.Transport.EnqueueText(Result(sliceType: 1, index: 0, text: "late partial"));
        fixture.Transport.EnqueueText("{\"code\":0,\"message\":\"success\",\"final\":1}");
        await fixture.Session.PushAudioAsync(new byte[] { 0, 0 }, CancellationToken.None);
        await fixture.Session.FinishAsync(CancellationToken.None);
        await Task.Delay(20);

        Assert.Empty(fixture.Partials);
        Assert.Equal(0, fixture.FinalCount);
        Assert.Equal(0, fixture.FailureCount);
        Assert.Empty(fixture.Transport.BinaryMessages);
        Assert.Empty(fixture.Transport.TextMessages);
        Assert.True(fixture.Transport.CloseCalls >= 1);
    }

    [Fact]
    public async Task Early_provider_final_stops_audio_and_end_sends_immediately()
    {
        await using var fixture = await Fixture.StartedAsync();
        fixture.Transport.EnqueueText(Result(sliceType: 2, index: 0, text: "已经完成"));
        fixture.Transport.EnqueueText("{\"code\":0,\"message\":\"success\",\"final\":1}");
        var final = await fixture.Final.Task.WaitAsync(TimeSpan.FromSeconds(2));

        await fixture.Session.PushAudioAsync(new byte[] { 0, 0 }, CancellationToken.None);
        await fixture.Session.FinishAsync(CancellationToken.None);

        Assert.Equal("已经完成", final.Text);
        Assert.Empty(fixture.Transport.BinaryMessages);
        Assert.Empty(fixture.Transport.TextMessages);
    }

    [Fact]
    public async Task Handshake_timeout_is_deterministic_and_secret_safe()
    {
        await using var fixture = Fixture.Create(handshakeTimeout: TimeSpan.FromSeconds(2));

        var start = fixture.Session.StartAsync(CancellationToken.None).AsTask();
        await WaitUntilAsync(() => fixture.Transport.ConnectRequest is not null);
        fixture.Time.Advance(TimeSpan.FromSeconds(3));
        var exception = await Assert.ThrowsAsync<TencentAsrSessionException>(() => start);

        Assert.Equal(VoxFlowErrorCode.NetworkFailure, exception.Error.Code);
        Assert.Equal(VoxFlowErrorCode.NetworkFailure, (await fixture.Failure.Task).Code);
        Assert.DoesNotContain("fixture-signing-key", exception.ToString(), StringComparison.Ordinal);
        Assert.True(fixture.Transport.CloseCalls >= 1);
    }

    private static string Result(int sliceType, int index, string text) =>
        $"{{\"code\":0,\"message\":\"success\",\"result\":{{" +
        $"\"slice_type\":{sliceType},\"index\":{index}," +
        $"\"voice_text_str\":\"{text}\"}}}}";

    private static async Task WaitUntilAsync(Func<bool> predicate)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        while (!predicate())
        {
            await Task.Delay(1, timeout.Token);
        }
    }

    private sealed class Fixture : IAsyncDisposable
    {
        private Fixture(
            TimeSpan? handshakeTimeout = null,
            TimeSpan? finalTimeout = null)
        {
            Time = new ControlledTimeProvider(
                new DateTimeOffset(2026, 7, 11, 0, 0, 0, TimeSpan.Zero));
            Transport = new FakeCloudWebSocket();
            Session = new TencentAsrSession(
                new TencentAsrCredentials(
                    "1234567890",
                    "fixture-secret-id",
                    "fixture-signing-key"),
                TencentAsrOptions.Default,
                "fixture-voice-id",
                new TencentSignedUrlBuilder(Time, new FakeTencentNonceSource()),
                Transport,
                Time,
                handshakeTimeout ?? TimeSpan.FromSeconds(5),
                finalTimeout ?? TimeSpan.FromSeconds(15));
            Session.PartialReceived += (_, partial) =>
            {
                lock (Partials)
                {
                    Partials.Add(partial);
                }
            };
            Session.FinalReceived += (_, final) =>
            {
                Interlocked.Increment(ref finalCount);
                Final.TrySetResult(final);
            };
            Session.Failed += (_, error) =>
            {
                Interlocked.Increment(ref failureCount);
                Failure.TrySetResult(error);
            };
        }

        private int finalCount;
        private int failureCount;

        public ControlledTimeProvider Time { get; }

        public FakeCloudWebSocket Transport { get; }

        public TencentAsrSession Session { get; }

        public List<AsrPartialResult> Partials { get; } = [];

        public TaskCompletionSource<AsrFinalResult> Final { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource<VoxFlowError> Failure { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public int FinalCount => Volatile.Read(ref finalCount);

        public int FailureCount => Volatile.Read(ref failureCount);

        public static Fixture Create(
            TimeSpan? handshakeTimeout = null,
            TimeSpan? finalTimeout = null) => new(handshakeTimeout, finalTimeout);

        public static async Task<Fixture> StartedAsync(
            TimeSpan? finalTimeout = null)
        {
            var fixture = new Fixture(finalTimeout: finalTimeout);
            fixture.Transport.EnqueueText(
                "{\"code\":0,\"message\":\"success\",\"voice_id\":\"fixture\"}");
            await fixture.Session.StartAsync(CancellationToken.None);
            return fixture;
        }

        public ValueTask DisposeAsync() => Session.DisposeAsync();
    }

    private sealed class FakeTencentNonceSource : ITencentNonceSource
    {
        public int NextNonce() => 1_234_567;
    }

    private sealed class FakeCloudWebSocket : ICloudWebSocket
    {
        private readonly Channel<CloudWebSocketReceiveMessage> receives =
            Channel.CreateUnbounded<CloudWebSocketReceiveMessage>(
                new UnboundedChannelOptions
                {
                    SingleReader = true,
                    SingleWriter = false,
                });
        private readonly object gate = new();

        public CloudWebSocketConnectRequest? ConnectRequest { get; private set; }

        public List<byte[]> BinaryMessages { get; } = [];

        public List<string> TextMessages { get; } = [];

        public int CloseCalls { get; private set; }

        public ValueTask ConnectAsync(
            CloudWebSocketConnectRequest request,
            CancellationToken cancellationToken)
        {
            ConnectRequest = request;
            return ValueTask.CompletedTask;
        }

        public ValueTask SendBinaryAsync(
            ReadOnlyMemory<byte> payload,
            CancellationToken cancellationToken)
        {
            lock (gate)
            {
                BinaryMessages.Add(payload.ToArray());
            }

            return ValueTask.CompletedTask;
        }

        public ValueTask SendTextAsync(
            string payload,
            CancellationToken cancellationToken)
        {
            lock (gate)
            {
                TextMessages.Add(payload);
            }

            return ValueTask.CompletedTask;
        }

        public ValueTask<CloudWebSocketReceiveMessage> ReceiveAsync(
            CancellationToken cancellationToken) => receives.Reader.ReadAsync(cancellationToken);

        public ValueTask CloseAsync(CancellationToken cancellationToken)
        {
            lock (gate)
            {
                CloseCalls++;
            }

            return ValueTask.CompletedTask;
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;

        public void EnqueueText(string message) =>
            receives.Writer.TryWrite(CloudWebSocketReceiveMessage.Text(message));
    }
}
