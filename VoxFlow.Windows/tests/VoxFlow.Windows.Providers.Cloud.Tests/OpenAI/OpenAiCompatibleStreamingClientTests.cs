using System.Net;
using System.Text;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.Providers.Cloud.Tests.OpenAI;

public sealed class OpenAiCompatibleStreamingClientTests
{
    private const string ApiKey = "~";

    [Fact]
    public async Task Byte_fragmented_CRLF_stream_emits_delta_cumulative_and_one_final_usage()
    {
        var sse = string.Join(
            "\r\n",
            ": keepalive",
            "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"好🙂\"}}]}",
            "",
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":2,\"total_tokens\":5}}",
            "",
            "data: [DONE]",
            "");
        var handler = new CapturingHandler(_ => Response(
            new ByteByByteContent(Encoding.UTF8.GetBytes(sse))));
        using var http = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        var client = new OpenAiCompatibleClient(http, "dev");

        var updates = await CollectAsync(client.StreamAsync(
            Configuration(),
            Request(),
            CancellationToken.None));

        Assert.Collection(
            updates,
            first =>
            {
                Assert.Equal("你", first.DeltaText);
                Assert.Equal("你", first.AccumulatedText);
                Assert.False(first.IsFinal);
            },
            second =>
            {
                Assert.Equal("好🙂", second.DeltaText);
                Assert.Equal("你好🙂", second.AccumulatedText);
                Assert.False(second.IsFinal);
            },
            final =>
            {
                Assert.Equal(string.Empty, final.DeltaText);
                Assert.Equal("你好🙂", final.AccumulatedText);
                Assert.True(final.IsFinal);
                Assert.Equal(3, final.TokenUsage?.InputTokens);
                Assert.Equal(2, final.TokenUsage?.OutputTokens);
                Assert.Equal(5, final.TokenUsage?.TotalTokens);
            });
        Assert.Equal("Bearer", handler.AuthorizationScheme);
        Assert.Equal(ApiKey, handler.AuthorizationParameter);
        Assert.True(handler.StreamRequested);
    }

    [Fact]
    public async Task Multiple_data_lines_are_joined_before_JSON_parsing()
    {
        const string sse =
            "data: {\"choices\":[\n" +
            "data: {\"delta\":{\"content\":\"A\"}}]}\n\n" +
            "data: [DONE]\n\n";
        using var http = new HttpClient(new CapturingHandler(_ => Response(
            new StringContent(sse, Encoding.UTF8, "text/event-stream"))))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");

        var updates = await CollectAsync(client.StreamAsync(
            Configuration(),
            Request(),
            CancellationToken.None));

        Assert.Equal(2, updates.Count);
        Assert.Equal("A", updates[0].DeltaText);
        Assert.True(updates[1].IsFinal);
        Assert.Equal("A", updates[1].AccumulatedText);
    }

    [Fact]
    public async Task EOF_without_DONE_is_interrupted_after_preserving_partial_updates()
    {
        const string sse =
            "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n";
        using var http = new HttpClient(new CapturingHandler(_ => Response(
            new StringContent(sse, Encoding.UTF8, "text/event-stream"))))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");
        var updates = new List<LlmStreamUpdate>();

        var error = await Assert.ThrowsAsync<OpenAiCompatibleClientException>(async () =>
        {
            await foreach (var update in client.StreamAsync(
                Configuration(),
                Request(),
                CancellationToken.None))
            {
                updates.Add(update);
            }
        });

        Assert.Equal(OpenAiCompatibleClientError.InterruptedStream, error.Error);
        Assert.Equal("partial", Assert.Single(updates).AccumulatedText);
    }

    [Fact]
    public async Task DONE_with_only_empty_or_non_content_events_is_empty_response()
    {
        const string sse =
            "data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}\n\n" +
            "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
            "data: [DONE]\n\n";
        using var http = new HttpClient(new CapturingHandler(_ => Response(
            new StringContent(sse, Encoding.UTF8, "text/event-stream"))))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");

        var error = await Assert.ThrowsAsync<OpenAiCompatibleClientException>(async () =>
            await CollectAsync(client.StreamAsync(
                Configuration(),
                Request(),
                CancellationToken.None)));

        Assert.Equal(OpenAiCompatibleClientError.EmptyResponse, error.Error);
    }

    [Fact]
    public async Task HTTP_error_does_not_read_or_echo_response_body()
    {
        var response = new HttpResponseMessage(HttpStatusCode.TooManyRequests)
        {
            Content = new ThrowIfReadContent(ApiKey),
        };
        using var http = new HttpClient(new CapturingHandler(_ => response))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");

        var error = await Assert.ThrowsAsync<OpenAiCompatibleClientException>(async () =>
            await CollectAsync(client.StreamAsync(
                Configuration(),
                Request(),
                CancellationToken.None)));

        Assert.Equal(OpenAiCompatibleClientError.HttpFailure, error.Error);
        Assert.Equal(HttpStatusCode.TooManyRequests, error.StatusCode);
        Assert.DoesNotContain(ApiKey, error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task User_cancellation_aborts_read_and_disposes_response_stream()
    {
        var stream = new BlockingStream();
        using var http = new HttpClient(new CapturingHandler(_ => Response(
            new StreamContent(stream))))
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var client = new OpenAiCompatibleClient(http, "dev");
        using var cancellation = new CancellationTokenSource();
        var enumerator = client.StreamAsync(
                Configuration(),
                Request(),
                cancellation.Token)
            .GetAsyncEnumerator(cancellation.Token);
        var moveNext = enumerator.MoveNextAsync().AsTask();
        await stream.ReadStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));

        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => moveNext);
        await enumerator.DisposeAsync();
        await stream.Disposed.Task.WaitAsync(TimeSpan.FromSeconds(2));
    }

    private static LlmProviderClientConfiguration Configuration() => new(
        "fixture",
        new Uri("https://example.test/v1"),
        "model-a",
        ApiKey,
        0.2,
        TimeSpan.FromSeconds(30));

    private static LlmCompletionRequest Request() => new(
        [new LlmChatMessage(LlmMessageRole.User, "hello")]);

    private static HttpResponseMessage Response(HttpContent content) => new(
        HttpStatusCode.OK)
    {
        Content = content,
    };

    private static async Task<List<LlmStreamUpdate>> CollectAsync(
        IAsyncEnumerable<LlmStreamUpdate> stream)
    {
        List<LlmStreamUpdate> updates = [];
        await foreach (var update in stream)
        {
            updates.Add(update);
        }
        return updates;
    }

    private sealed class CapturingHandler(
        Func<HttpRequestMessage, HttpResponseMessage> responseFactory)
        : HttpMessageHandler
    {
        public string? AuthorizationScheme { get; private set; }

        public string? AuthorizationParameter { get; private set; }

        public bool StreamRequested { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            StreamRequested = request.Content is not null
                && (await request.Content.ReadAsStringAsync(cancellationToken))
                    .Contains("\"stream\":true", StringComparison.Ordinal);
            return responseFactory(request);
        }
    }

    private sealed class ByteByByteContent(byte[] bytes) : HttpContent
    {
        protected override Task SerializeToStreamAsync(
            Stream stream,
            TransportContext? context) => throw new NotSupportedException();

        protected override bool TryComputeLength(out long length)
        {
            length = bytes.Length;
            return true;
        }

        protected override Task<Stream> CreateContentReadStreamAsync() =>
            Task.FromResult<Stream>(new ByteByByteStream(bytes));
    }

    private sealed class ByteByByteStream(byte[] bytes)
        : MemoryStream(bytes, writable: false)
    {
        public override ValueTask<int> ReadAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken = default) =>
            base.ReadAsync(buffer[..Math.Min(1, buffer.Length)], cancellationToken);
    }

    private sealed class BlockingStream : Stream
    {
        public TaskCompletionSource ReadStarted { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource Disposed { get; } = new(
            TaskCreationOptions.RunContinuationsAsynchronously);

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override void Flush()
        {
        }

        public override int Read(byte[] buffer, int offset, int count) =>
            throw new NotSupportedException();

        public override async ValueTask<int> ReadAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken = default)
        {
            ReadStarted.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return 0;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                Disposed.TrySetResult();
            }
            base.Dispose(disposing);
        }

        public override long Seek(long offset, SeekOrigin origin) =>
            throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) =>
            throw new NotSupportedException();
    }

    private sealed class ThrowIfReadContent(string sentinel) : HttpContent
    {
        protected override Task SerializeToStreamAsync(
            Stream stream,
            TransportContext? context) =>
            throw new InvalidOperationException(
                $"Response body must not be read: {sentinel}");

        protected override bool TryComputeLength(out long length)
        {
            length = 0;
            return false;
        }
    }
}
