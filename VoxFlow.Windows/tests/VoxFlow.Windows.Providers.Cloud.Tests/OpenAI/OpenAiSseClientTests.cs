using System.Net;
using System.Text;
using System.Text.Json;
using VoxFlow.Windows.Providers.Cloud.OpenAI;

namespace VoxFlow.Windows.Providers.Cloud.Tests.OpenAI;

public sealed class OpenAiSseClientTests
{
    private const string ApiKey = "s" + "k-fixture-sse-secret";

    [Theory]
    [InlineData("https://api.openai.com/v1", "https://api.openai.com/v1/chat/completions")]
    [InlineData("https://api.openai.com/v1/", "https://api.openai.com/v1/chat/completions")]
    [InlineData("https://compatible.invalid/openai/v1", "https://compatible.invalid/openai/v1/chat/completions")]
    [InlineData("https://compatible.invalid/openai/v1/chat/completions", "https://compatible.invalid/openai/v1/chat/completions")]
    public void Chat_completions_URL_is_normalized_without_duplicate_path_segments(
        string baseUrl,
        string expected)
    {
        Assert.Equal(
            new Uri(expected),
            OpenAiChatCompletionsClient.BuildChatCompletionsUri(new Uri(baseUrl)));
    }

    [Theory]
    [InlineData("http://api.openai.com/v1")]
    [InlineData("file:///v1")]
    public void Chat_completions_URL_rejects_non_https_endpoints(string baseUrl)
    {
        Assert.Throws<ArgumentException>(() =>
            OpenAiChatCompletionsClient.BuildChatCompletionsUri(new Uri(baseUrl)));
    }

    [Fact]
    public async Task Bearer_stream_request_accumulates_fragmented_UTF8_and_skips_non_content_events()
    {
        var sse = string.Join(
            "\r\n",
            ": keepalive",
            "event: message",
            "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}",
            "",
            "data: this-is-not-json",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"好🙂\"}}]}",
            "",
            "data: [DONE]",
            "");
        var handler = new CapturingHandler(
            _ => Response(new ByteByByteContent(Encoding.UTF8.GetBytes(sse))));
        using var httpClient = new HttpClient(handler);
        var client = new OpenAiChatCompletionsClient(httpClient);

        var snapshots = await CollectAsync(client.StreamRefinementAsync(
            new OpenAiClientConfiguration(
                new Uri("https://compatible.invalid/v1/"),
                "fixture-model",
                ApiKey),
            "原始文本",
            CancellationToken.None));

        Assert.Equal(["你", "你好🙂"], snapshots);
        Assert.Equal(
            new Uri("https://compatible.invalid/v1/chat/completions"),
            handler.RequestUri);
        Assert.Equal("Bearer", handler.AuthorizationScheme);
        Assert.Equal(ApiKey, handler.AuthorizationParameter);
        Assert.DoesNotContain(ApiKey, client.ToString(), StringComparison.Ordinal);
        using var body = JsonDocument.Parse(handler.RequestBody!);
        Assert.True(body.RootElement.GetProperty("stream").GetBoolean());
        Assert.Equal("fixture-model", body.RootElement.GetProperty("model").GetString());
        var messages = body.RootElement.GetProperty("messages");
        Assert.Equal("system", messages[0].GetProperty("role").GetString());
        Assert.Equal("user", messages[1].GetProperty("role").GetString());
        Assert.Equal("原始文本", messages[1].GetProperty("content").GetString());
    }

    [Fact]
    public async Task Multiple_data_lines_form_one_SSE_event_before_JSON_parsing()
    {
        const string sse =
            "data: {\"choices\":[{\"delta\":{\"content\":\"A\"}}]}\n\n" +
            "data: [DONE]\n\n";
        using var httpClient = new HttpClient(new CapturingHandler(
            _ => Response(new StringContent(sse, Encoding.UTF8, "text/event-stream"))));
        var client = new OpenAiChatCompletionsClient(httpClient);

        var snapshots = await CollectAsync(client.StreamRefinementAsync(
            Configuration(),
            "input",
            CancellationToken.None));

        Assert.Equal(["A"], snapshots);
    }

    [Fact]
    public async Task End_of_stream_without_DONE_is_an_interruption_even_after_partial_content()
    {
        const string sse =
            "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n";
        using var httpClient = new HttpClient(new CapturingHandler(
            _ => Response(new StringContent(sse, Encoding.UTF8, "text/event-stream"))));
        var client = new OpenAiChatCompletionsClient(httpClient);
        var snapshots = new List<string>();

        var exception = await Assert.ThrowsAsync<OpenAiClientException>(async () =>
        {
            await foreach (var snapshot in client.StreamRefinementAsync(
                Configuration(),
                "input",
                CancellationToken.None))
            {
                snapshots.Add(snapshot);
            }
        });

        Assert.Equal(["partial"], snapshots);
        Assert.Equal(OpenAiClientError.InterruptedStream, exception.Error);
        Assert.DoesNotContain(ApiKey, exception.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task DONE_without_content_is_a_safe_empty_response_error()
    {
        using var httpClient = new HttpClient(new CapturingHandler(
            _ => Response(new StringContent(
                "data: {\"choices\":[]}\n\ndata: [DONE]\n\n",
                Encoding.UTF8,
                "text/event-stream"))));
        var client = new OpenAiChatCompletionsClient(httpClient);

        var exception = await Assert.ThrowsAsync<OpenAiClientException>(async () =>
            await CollectAsync(client.StreamRefinementAsync(
                Configuration(),
                "input",
                CancellationToken.None)));

        Assert.Equal(OpenAiClientError.EmptyResponse, exception.Error);
    }

    [Fact]
    public async Task HTTP_error_is_classified_without_reading_or_echoing_the_response_body()
    {
        var response = new HttpResponseMessage(HttpStatusCode.Unauthorized)
        {
            Content = new ThrowIfReadContent(ApiKey),
        };
        using var httpClient = new HttpClient(new CapturingHandler(_ => response));
        var client = new OpenAiChatCompletionsClient(httpClient);

        var exception = await Assert.ThrowsAsync<OpenAiClientException>(async () =>
            await CollectAsync(client.StreamRefinementAsync(
                Configuration(),
                "input",
                CancellationToken.None)));

        Assert.Equal(OpenAiClientError.HttpFailure, exception.Error);
        Assert.Equal(HttpStatusCode.Unauthorized, exception.StatusCode);
        Assert.DoesNotContain(ApiKey, exception.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Cancellation_aborts_a_blocked_SSE_read_without_converting_it_to_provider_failure()
    {
        using var httpClient = new HttpClient(new CapturingHandler(
            _ => Response(new BlockingContent())));
        var client = new OpenAiChatCompletionsClient(httpClient);
        using var cancellation = new CancellationTokenSource();
        var enumerator = client.StreamRefinementAsync(
                Configuration(),
                "input",
                cancellation.Token)
            .GetAsyncEnumerator(cancellation.Token);
        var moveNext = enumerator.MoveNextAsync().AsTask();

        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => moveNext);
        await enumerator.DisposeAsync();
    }

    private static OpenAiClientConfiguration Configuration() => new(
        new Uri("https://api.openai.com/v1"),
        "fixture-model",
        ApiKey);

    private static HttpResponseMessage Response(HttpContent content) => new(HttpStatusCode.OK)
    {
        Content = content,
    };

    private static async Task<List<string>> CollectAsync(
        IAsyncEnumerable<string> stream)
    {
        List<string> values = [];
        await foreach (var value in stream)
        {
            values.Add(value);
        }

        return values;
    }

    private sealed class CapturingHandler(
        Func<HttpRequestMessage, HttpResponseMessage> responseFactory)
        : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }

        public string? AuthorizationScheme { get; private set; }

        public string? AuthorizationParameter { get; private set; }

        public string? RequestBody { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            RequestBody = request.Content is null
                ? null
                : await request.Content.ReadAsStringAsync(cancellationToken);
            return responseFactory(request);
        }
    }

    private sealed class ByteByByteContent(byte[] bytes) : HttpContent
    {
        protected override Task SerializeToStreamAsync(
            Stream stream,
            TransportContext? context) =>
            throw new NotSupportedException();

        protected override bool TryComputeLength(out long length)
        {
            length = bytes.Length;
            return true;
        }

        protected override Task<Stream> CreateContentReadStreamAsync() =>
            Task.FromResult<Stream>(new ByteByByteStream(bytes));
    }

    private sealed class ByteByByteStream(byte[] bytes) : MemoryStream(bytes, writable: false)
    {
        public override int Read(byte[] buffer, int offset, int count) =>
            base.Read(buffer, offset, Math.Min(1, count));

        public override int Read(Span<byte> buffer) =>
            base.Read(buffer[..Math.Min(1, buffer.Length)]);

        public override ValueTask<int> ReadAsync(
            Memory<byte> buffer,
            CancellationToken cancellationToken = default) =>
            base.ReadAsync(buffer[..Math.Min(1, buffer.Length)], cancellationToken);
    }

    private sealed class BlockingContent : HttpContent
    {
        protected override Task SerializeToStreamAsync(
            Stream stream,
            TransportContext? context) =>
            throw new NotSupportedException();

        protected override bool TryComputeLength(out long length)
        {
            length = 0;
            return false;
        }

        protected override Task<Stream> CreateContentReadStreamAsync() =>
            Task.FromResult<Stream>(new BlockingStream());
    }

    private sealed class BlockingStream : Stream
    {
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
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return 0;
        }

        public override long Seek(long offset, SeekOrigin origin) =>
            throw new NotSupportedException();

        public override void SetLength(long value) =>
            throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) =>
            throw new NotSupportedException();
    }

    private sealed class ThrowIfReadContent(string sentinel) : HttpContent
    {
        protected override Task SerializeToStreamAsync(
            Stream stream,
            TransportContext? context) =>
            throw new InvalidOperationException($"Response body must not be read: {sentinel}");

        protected override bool TryComputeLength(out long length)
        {
            length = 0;
            return false;
        }
    }
}
