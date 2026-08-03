using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;
using System.Text.Json;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentWebFetchToolHostTests
{
    [Fact]
    public async Task Explicit_url_fetches_html_as_markdown_like_text()
    {
        var client = new FakeClient(new(200, "text/html", "<html><body><h1>Install</h1><p>Run make build.</p><script>alert(1)</script></body></html>"));
        var result = await Host("读取 " + Url + " 并总结", client).ExecuteAsync(Call(Url), CancellationToken.None);

        Assert.True(result.Ok);
        var text = result.Result!.Value.GetProperty("result").GetString()!;
        Assert.Contains("# Install", text);
        Assert.Contains("Run make build.", text);
        Assert.DoesNotContain("alert(1)", text);
        Assert.Equal(Url, client.Url!.AbsoluteUri);
    }

    [Fact]
    public async Task Preapproved_documentation_host_does_not_need_full_url_in_voice_instruction()
    {
        var result = await Host("查一下官方 Swift 文档", new FakeClient(new(200, "text/plain", "ok")))
            .ExecuteAsync(Call("https://docs.swift.org/swift-book/documentation/the-swift-programming-language/"), CancellationToken.None);

        Assert.True(result.Ok);
    }

    [Theory]
    [InlineData("https://user:password@example.test/docs")]
    [InlineData("file:///C:/secret.txt")]
    [InlineData("not a URL")]
    public async Task Userinfo_and_non_web_urls_are_rejected(string url)
    {
        var result = await Host("读取 " + url, new FakeClient(new(200, "text/plain", "ok")))
            .ExecuteAsync(Call(url), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("invalid_url", result.Error?.Code);
    }

    [Fact]
    public async Task Context_only_non_preapproved_url_is_rejected()
    {
        var result = await Host("总结当前窗口", new FakeClient(new(200, "text/plain", "ok")))
            .ExecuteAsync(Call(Url), CancellationToken.None);

        Assert.False(result.Ok);
        Assert.Equal("missing_explicit_user_intent", result.Error?.Code);
    }

    [Fact]
    public async Task Cross_host_redirect_is_returned_without_following()
    {
        var client = new FakeClient(new(302, "text/plain", string.Empty, new Uri("https://evil.example/steal")));
        var result = await Host("读取 " + Url, client).ExecuteAsync(Call(Url), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.Contains("REDIRECT DETECTED", result.Result!.Value.GetProperty("result").GetString()!);
        Assert.Contains("evil.example", result.Result!.Value.GetProperty("result").GetString()!);
    }

    [Fact]
    public async Task Same_host_redirect_is_followed_with_a_bounded_second_request()
    {
        var client = new SequenceClient(
            new(302, "text/plain", string.Empty, new Uri("https://api.example.test/v1/next")),
            new(200, "text/plain", "final page"));
        var result = await Host("读取 " + Url, client).ExecuteAsync(Call(Url), CancellationToken.None);

        Assert.True(result.Ok);
        Assert.Equal(2, client.Urls.Count);
        Assert.Equal("https://api.example.test/v1/next", result.Result!.Value.GetProperty("url").GetString());
        Assert.Equal("final page", result.Result!.Value.GetProperty("result").GetString());
    }

    [Fact]
    public async Task Result_is_limited_to_100k_characters()
    {
        var result = await Host("读取 " + Url, new FakeClient(new(200, "text/plain", new string('x', 100_001))))
            .ExecuteAsync(Call(Url), CancellationToken.None);

        Assert.True(result.Result!.Value.GetProperty("truncated").GetBoolean());
        Assert.Equal(100_000, result.Result!.Value.GetProperty("result").GetString()!.Length);
    }

    [Fact]
    public async Task Timeout_and_failures_are_honest()
    {
        var timeout = await Host("读取 " + Url, new BlockingClient(), TimeSpan.FromMilliseconds(10))
            .ExecuteAsync(Call(Url), CancellationToken.None);
        var failure = await Host("读取 " + Url, new ThrowingClient()).ExecuteAsync(Call(Url), CancellationToken.None);

        Assert.Equal("web_fetch_timeout", timeout.Error?.Code);
        Assert.Equal("web_fetch_failed", failure.Error?.Code);
    }

    private const string Url = "https://api.example.test/v1/docs";
    private static BuiltinAgentWebFetchToolHost Host(string instruction, IAgentWebFetchClient client, TimeSpan? timeout = null) =>
        new(new AgentToolAuthorizationPolicy(instruction), client, timeout);
    private static AgentToolCall Call(string url) => new("fetch-1", "web_fetch", JsonSerializer.SerializeToElement(new { url, prompt = "summarize" }));

    private sealed class FakeClient(AgentWebFetchResponse response) : IAgentWebFetchClient
    {
        private readonly AgentWebFetchResponse response = response;
        public Uri? Url { get; private set; }
        public Task<AgentWebFetchResponse> GetAsync(Uri uri, CancellationToken cancellationToken) { Url = uri; return Task.FromResult(response); }
    }
    private sealed class BlockingClient : IAgentWebFetchClient
    {
        public async Task<AgentWebFetchResponse> GetAsync(Uri uri, CancellationToken cancellationToken)
        { await Task.Delay(System.Threading.Timeout.InfiniteTimeSpan, cancellationToken); throw new InvalidOperationException(); }
    }
    private sealed class SequenceClient(params AgentWebFetchResponse[] responses) : IAgentWebFetchClient
    {
        private readonly Queue<AgentWebFetchResponse> responses = new(responses);
        public List<Uri> Urls { get; } = [];
        public Task<AgentWebFetchResponse> GetAsync(Uri uri, CancellationToken cancellationToken)
        {
            Urls.Add(uri);
            return Task.FromResult(responses.Dequeue());
        }
    }
    private sealed class ThrowingClient : IAgentWebFetchClient
    { public Task<AgentWebFetchResponse> GetAsync(Uri uri, CancellationToken cancellationToken) => throw new HttpRequestException(); }
}
