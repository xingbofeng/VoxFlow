using System.Net.Http;
using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentHttpRequestToolHostTests
{
    [Theory]
    [InlineData("GET")]
    [InlineData("POST")]
    [InlineData("PUT")]
    [InlineData("PATCH")]
    [InlineData("DELETE")]
    public async Task Explicit_voice_https_url_allows_each_approved_method(string method)
    {
        var client = new CapturingClient();
        var result = await Host("请求 " + Url, client).ExecuteAsync(
            Call(method, new { url = Url, method }), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.Equal(method, client.Method?.Method);
        Assert.Equal(new Uri(Url), client.Uri);
        Assert.Equal(200, result.Result!.Value.GetProperty("statusCode").GetInt32());
        Assert.False(result.Result!.Value.GetProperty("truncated").GetBoolean());
    }

    [Fact]
    public async Task Context_only_url_does_not_authorize_an_http_request()
    {
        var client = new CapturingClient();
        var result = await Host("总结当前窗口内容", client).ExecuteAsync(
            Call("GET", new { url = Url }), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("missing_explicit_user_intent", result.Error?.Code);
        Assert.Null(client.Uri);
    }

    [Theory]
    [InlineData("http://example.test/status")]
    [InlineData("file:///C:/secret.txt")]
    [InlineData("https://")]
    public async Task Only_absolute_https_urls_are_accepted(string url)
    {
        var result = await Host("请求 " + url, new CapturingClient()).ExecuteAsync(
            Call("GET", new { url }), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("invalid_https_url", result.Error?.Code);
    }

    [Fact]
    public async Task Unsupported_method_and_header_injection_are_rejected_before_the_network()
    {
        var client = new CapturingClient();
        var unsupported = await Host("请求 " + Url, client).ExecuteAsync(
            Call("HEAD", new { url = Url, method = "HEAD" }), CancellationToken.None);
        var injectedHeader = await Host("请求 " + Url, client).ExecuteAsync(
            Call("GET", new { url = Url, headers = new { Test = "safe\r\nInjected: no" } }), CancellationToken.None);

        Assert.Equal("unsupported_http_method", unsupported.Error?.Code);
        Assert.Equal("invalid_headers", injectedHeader.Error?.Code);
        Assert.Null(client.Uri);
    }

    [Fact]
    public async Task Host_forwards_only_model_supplied_headers_and_body_without_echoing_them()
    {
        var client = new CapturingClient();
        var authorization = "Bearer" + " model-provided-value";
        var result = await Host("请求 " + Url, client).ExecuteAsync(
            Call("POST", new
            {
                url = Url,
                method = "POST",
                headers = new { Authorization = authorization },
                body = "payload",
            }), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.Equal("payload", client.Body);
        Assert.Equal(authorization, client.Headers!["Authorization"]);
        Assert.DoesNotContain("model-provided-value", result.Result!.Value.GetRawText(), StringComparison.Ordinal);
        Assert.DoesNotContain("payload", result.Result!.Value.GetRawText(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Response_is_limited_to_40k_characters()
    {
        var client = new CapturingClient(new(200, new string('x', 40_001)));
        var result = await Host("请求 " + Url, client).ExecuteAsync(
            Call("GET", new { url = Url }), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.True(result.Result!.Value.GetProperty("truncated").GetBoolean());
        Assert.Equal(40_000, result.Result!.Value.GetProperty("body").GetString()!.Length);
    }

    [Fact]
    public async Task Timeout_is_reported_without_turning_caller_cancellation_into_a_success()
    {
        var result = await Host("请求 " + Url, new BlockingClient(), TimeSpan.FromMilliseconds(10))
            .ExecuteAsync(Call("GET", new { url = Url }), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("http_timeout", result.Error?.Code);
    }

    private const string Url = "https://api.example.test/v1/status";

    private static BuiltinAgentHttpRequestToolHost Host(
        string instruction,
        IAgentHttpRequestClient client,
        TimeSpan? timeout = null) => new(new AgentToolAuthorizationPolicy(instruction), client, timeout);

    private static AgentToolCall Call(string method, object arguments) => new(
        "call-1", "http_request", JsonSerializer.SerializeToElement(arguments));

    private sealed class CapturingClient(AgentHttpResponse? response = null) : IAgentHttpRequestClient
    {
        private readonly AgentHttpResponse response = response ?? new(200, "ok");
        public HttpMethod? Method { get; private set; }
        public Uri? Uri { get; private set; }
        public IReadOnlyDictionary<string, string>? Headers { get; private set; }
        public string? Body { get; private set; }

        public Task<AgentHttpResponse> SendAsync(HttpMethod method, Uri uri,
            IReadOnlyDictionary<string, string> headers, string? body, CancellationToken cancellationToken)
        {
            Method = method;
            Uri = uri;
            Headers = headers;
            Body = body;
            return Task.FromResult(response);
        }
    }

    private sealed class BlockingClient : IAgentHttpRequestClient
    {
        public async Task<AgentHttpResponse> SendAsync(HttpMethod method, Uri uri,
            IReadOnlyDictionary<string, string> headers, string? body, CancellationToken cancellationToken)
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException("The cancellation token should have stopped the delay.");
        }
    }
}
