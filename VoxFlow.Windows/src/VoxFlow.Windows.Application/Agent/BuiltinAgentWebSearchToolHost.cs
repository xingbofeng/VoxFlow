using System.Net.Http;
using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentWebSearchResponse(int StatusCode, string Body);
public interface IAgentWebSearchClient { Task<AgentWebSearchResponse> SearchAsync(string query, CancellationToken cancellationToken); }

public sealed class AgentWebSearchClient : IAgentWebSearchClient, IDisposable
{
    private readonly HttpClient client = new() { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
    public async Task<AgentWebSearchResponse> SearchAsync(string query, CancellationToken cancellationToken)
    {
        var uri = new UriBuilder("https://api.duckduckgo.com/") { Query = $"q={Uri.EscapeDataString(query)}&format=json&no_html=1&skip_disambig=1" }.Uri;
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
        request.Headers.TryAddWithoutValidation("User-Agent", "VoxFlow-Agent/1.0");
        using var response = await client.SendAsync(request, cancellationToken).ConfigureAwait(false);
        return new((int)response.StatusCode, await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false));
    }
    public void Dispose() => client.Dispose();
}

public sealed class BuiltinAgentWebSearchToolHost
{
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(20);
    private readonly IAgentWebSearchClient client;
    private readonly TimeSpan timeout;
    public BuiltinAgentWebSearchToolHost(IAgentWebSearchClient client, TimeSpan? timeout = null)
    { this.client = client ?? throw new ArgumentNullException(nameof(client)); this.timeout = timeout ?? DefaultTimeout; }

    public async Task<AgentToolResult> ExecuteAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        if (!TryString(call.Arguments, "query", out var query) || query.Length < 2) return AgentToolResult.Failure(call.Name, "missing_query");
        if (!TryDomains(call.Arguments, "allowed_domains", out var allowed) || !TryDomains(call.Arguments, "blocked_domains", out var blocked)) return AgentToolResult.Failure(call.Name, "invalid_domain_filters");
        if (allowed.Count > 0 && blocked.Count > 0) return AgentToolResult.Failure(call.Name, "conflicting_domain_filters");
        var limit = 8;
        if (call.Arguments.TryGetProperty("num_results", out var count))
        {
            if (count.ValueKind != JsonValueKind.Number || !count.TryGetInt32(out limit)) return AgentToolResult.Failure(call.Name, "invalid_num_results");
            limit = Math.Clamp(limit, 1, 20);
        }
        using var timeoutCancellation = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCancellation.Token);
        var startedAt = TimeProvider.System.GetTimestamp();
        try
        {
            var response = await client.SearchAsync(query, linked.Token).ConfigureAwait(false);
            if (response.StatusCode is < 200 or >= 300) return AgentToolResult.Failure(call.Name, "web_search_http_error");
            var hits = ParseHits(response.Body).Where(hit => allowed.Count > 0 ? allowed.Contains(hit.Domain) : !blocked.Contains(hit.Domain)).Take(limit).ToArray();
            object[] results = hits.Length == 0
                ? ["No search results found."]
                : [new { tool_use_id = call.Id, content = hits.Select(hit => new { title = hit.Title, url = hit.Url, snippet = hit.Snippet }).ToArray() }];
            return AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new { query, results, durationSeconds = (int)TimeProvider.System.GetElapsedTime(startedAt).TotalSeconds }));
        }
        catch (JsonException) { return AgentToolResult.Failure(call.Name, "invalid_search_response"); }
        catch (OperationCanceledException) when (timeoutCancellation.IsCancellationRequested && !cancellationToken.IsCancellationRequested) { return AgentToolResult.Failure(call.Name, "web_search_timeout"); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch { return AgentToolResult.Failure(call.Name, "web_search_failed"); }
    }

    private static IEnumerable<SearchHit> ParseHits(string body)
    {
        using var document = JsonDocument.Parse(body);
        if (document.RootElement.ValueKind != JsonValueKind.Object) throw new JsonException();
        foreach (var hit in ReadArray(document.RootElement, "results")) if (TryHit(hit, out var result)) yield return result;
        foreach (var topic in FlattenTopics(ReadArray(document.RootElement, "RelatedTopics"))) if (TryHit(topic, out var result)) yield return result;
    }
    private static IEnumerable<JsonElement> ReadArray(JsonElement root, string name) => root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Array ? value.EnumerateArray().ToArray() : [];
    private static IEnumerable<JsonElement> FlattenTopics(IEnumerable<JsonElement> topics)
    { foreach (var topic in topics) { if (topic.TryGetProperty("Topics", out var nested) && nested.ValueKind == JsonValueKind.Array) foreach (var item in FlattenTopics(nested.EnumerateArray().ToArray())) yield return item; else yield return topic; } }
    private static bool TryHit(JsonElement item, out SearchHit hit)
    {
        hit = default!;
        var title = string.Empty;
        var url = string.Empty;
        var hasModern = TryString(item, "title", out title) && TryString(item, "url", out url);
        if (!hasModern && !TryString(item, "FirstURL", out url)) return false;
        if (!hasModern) { _ = TryString(item, "Text", out title); title = title.Length == 0 ? url : title.Split(" - ", 2)[0]; }
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || string.IsNullOrEmpty(uri.Host)) return false;
        _ = TryString(item, hasModern ? "snippet" : "Text", out var snippet);
        hit = new(title, url, snippet, NormalizeDomain(uri.Host)); return true;
    }
    private static bool TryDomains(JsonElement args, string name, out HashSet<string> domains)
    {
        domains = new(StringComparer.OrdinalIgnoreCase);
        if (!args.TryGetProperty(name, out var value)) return true;
        if (value.ValueKind != JsonValueKind.Array) return false;
        foreach (var item in value.EnumerateArray()) { if (item.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(item.GetString())) return false; domains.Add(NormalizeDomain(item.GetString()!)); }
        return true;
    }
    private static bool TryString(JsonElement args, string name, out string text)
    { text = string.Empty; return args.ValueKind == JsonValueKind.Object && args.TryGetProperty(name, out var item) && item.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(text = item.GetString() ?? string.Empty); }
    private static string NormalizeDomain(string domain) => domain.Trim().TrimEnd('.').StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? domain.Trim().TrimEnd('.')[4..].ToLowerInvariant() : domain.Trim().TrimEnd('.').ToLowerInvariant();
    private sealed record SearchHit(string Title, string Url, string? Snippet, string Domain);
}
