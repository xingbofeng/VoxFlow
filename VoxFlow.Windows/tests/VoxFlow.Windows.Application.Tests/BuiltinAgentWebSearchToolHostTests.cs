using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentWebSearchToolHostTests
{
    [Fact]
    public async Task Parses_duckduckgo_shape_and_applies_allowed_domain_filter()
    {
        var client = new FakeClient("""{"results":[{"title":"Swift Concurrency","url":"https://docs.swift.org/book","snippet":"Structured concurrency."},{"title":"Blocked","url":"https://blocked.example/post"}]}""");
        var result = await Host(client).ExecuteAsync(Call("Swift concurrency", new { allowed_domains = new[] { "www.docs.swift.org" }, num_results = 5 }), CancellationToken.None);

        Assert.True(result.Ok);
        var content = result.Result!.Value.GetProperty("results")[0].GetProperty("content");
        Assert.Single(content.EnumerateArray());
        Assert.Equal("Swift Concurrency", content[0].GetProperty("title").GetString());
        Assert.Equal("Swift concurrency", client.Query);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(21)]
    public async Task Result_count_is_clamped_between_one_and_twenty(int count)
    {
        var body = "{\"results\":[" + string.Join(',', Enumerable.Range(0, 25).Select(i => $"{{\"title\":\"{i}\",\"url\":\"https://example{i}.test\"}}")) + "]}";
        var result = await Host(new FakeClient(body)).ExecuteAsync(Call("query", new { num_results = count }), CancellationToken.None);

        var content = result.Result!.Value.GetProperty("results")[0].GetProperty("content");
        Assert.Equal(count == 0 ? 1 : 20, content.GetArrayLength());
    }

    [Fact]
    public async Task Conflicting_filters_and_missing_query_are_rejected()
    {
        var conflicting = await Host(new FakeClient("{}")).ExecuteAsync(Call("query", new { allowed_domains = new[] { "a.test" }, blocked_domains = new[] { "b.test" } }), CancellationToken.None);
        var missing = await Host(new FakeClient("{}")).ExecuteAsync(new AgentToolCall("search-1", "web_search", JsonSerializer.SerializeToElement(new { query = "x" })), CancellationToken.None);

        Assert.Equal("conflicting_domain_filters", conflicting.Error?.Code);
        Assert.Equal("missing_query", missing.Error?.Code);
    }

    [Fact]
    public async Task No_results_and_http_failures_have_stable_results()
    {
        var empty = await Host(new FakeClient("{\"RelatedTopics\":[]}")).ExecuteAsync(Call("query", new { }), CancellationToken.None);
        var failure = await Host(new FakeClient("{}", 503)).ExecuteAsync(Call("query", new { }), CancellationToken.None);

        Assert.Equal("No search results found.", empty.Result!.Value.GetProperty("results")[0].GetString());
        Assert.Equal("web_search_http_error", failure.Error?.Code);
    }

    private static BuiltinAgentWebSearchToolHost Host(IAgentWebSearchClient client) => new(client, TimeSpan.FromSeconds(1));
    private static AgentToolCall Call(string query, object extra) => new("search-1", "web_search", JsonSerializer.SerializeToElement(new Dictionary<string, object?> { ["query"] = query }.Concat(extra.GetType().GetProperties().ToDictionary(p => p.Name, p => p.GetValue(extra))).ToDictionary(x => x.Key, x => x.Value)));
    private sealed class FakeClient(string body, int status = 200) : IAgentWebSearchClient
    { public string? Query { get; private set; } public Task<AgentWebSearchResponse> SearchAsync(string query, CancellationToken cancellationToken) { Query = query; return Task.FromResult(new AgentWebSearchResponse(status, body)); } }
}
