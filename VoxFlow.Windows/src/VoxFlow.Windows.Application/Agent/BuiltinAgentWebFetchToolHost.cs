using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentWebFetchResponse(int StatusCode, string ContentType, string Body, Uri? RedirectUri = null);

public interface IAgentWebFetchClient
{
    Task<AgentWebFetchResponse> GetAsync(Uri uri, CancellationToken cancellationToken);
}

/// <summary>Dedicated client with redirects disabled so the tool host can make
/// cross-host redirects visible to the model instead of silently following them.</summary>
public sealed class AgentWebFetchClient : IAgentWebFetchClient, IDisposable
{
    private readonly HttpClient client = new(new HttpClientHandler { AllowAutoRedirect = false })
    {
        Timeout = System.Threading.Timeout.InfiniteTimeSpan,
    };

    public async Task<AgentWebFetchResponse> GetAsync(Uri uri, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.TryAddWithoutValidation("Accept", "text/markdown, text/html, text/plain, */*");
        request.Headers.TryAddWithoutValidation("User-Agent", "VoxFlow-Agent/1.0");
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
            .ConfigureAwait(false);
        var location = response.Headers.Location is { } relative ? new Uri(uri, relative) : null;
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        return new((int)response.StatusCode, response.Content.Headers.ContentType?.MediaType ?? string.Empty, body, location);
    }

    public void Dispose() => client.Dispose();
}

public sealed class BuiltinAgentWebFetchToolHost
{
    public const int MaximumResultCharacters = 100_000;
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(60);
    private readonly AgentToolAuthorizationPolicy authorization;
    private readonly IAgentWebFetchClient client;
    private readonly TimeSpan timeout;

    public BuiltinAgentWebFetchToolHost(AgentToolAuthorizationPolicy authorization, IAgentWebFetchClient client, TimeSpan? timeout = null)
    {
        this.authorization = authorization ?? throw new ArgumentNullException(nameof(authorization));
        this.client = client ?? throw new ArgumentNullException(nameof(client));
        this.timeout = timeout ?? DefaultTimeout;
    }

    public async Task<AgentToolResult> ExecuteAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        if (!TryUrl(call.Arguments, out var url)) return AgentToolResult.Failure(call.Name, "invalid_url");
        if (!TryNonEmptyString(call.Arguments, "prompt", out _)) return AgentToolResult.Failure(call.Name, "invalid_prompt");
        if (!authorization.AllowsWebFetch(url)) return AgentToolResult.Failure(call.Name, "missing_explicit_user_intent");
        using var timeoutCancellation = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCancellation.Token);
        var startedAt = TimeProvider.System.GetTimestamp();
        try
        {
            var currentUrl = url;
            for (var redirects = 0; redirects < 5; redirects++)
            {
                var response = await client.GetAsync(currentUrl, linked.Token).ConfigureAwait(false);
                if (response.StatusCode is >= 300 and < 400 && response.RedirectUri is { } redirect)
                {
                    if (!IsPermittedRedirect(currentUrl, redirect))
                    {
                        var warning = $"REDIRECT DETECTED: The URL redirects to a different host.\n\nOriginal URL: {currentUrl.AbsoluteUri}\nRedirect URL: {redirect.AbsoluteUri}\nStatus: {response.StatusCode}\n\nTo complete your request, use web_fetch again with the redirect URL.";
                        return Success(call.Name, currentUrl, response.StatusCode, warning, TimeProvider.System.GetElapsedTime(startedAt));
                    }
                    currentUrl = redirect;
                    continue;
                }
                return Success(call.Name, currentUrl, response.StatusCode, ExtractText(response.Body, response.ContentType), TimeProvider.System.GetElapsedTime(startedAt));
            }
            return AgentToolResult.Failure(call.Name, "web_fetch_redirect_limit");
        }
        catch (OperationCanceledException) when (timeoutCancellation.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            return AgentToolResult.Failure(call.Name, "web_fetch_timeout");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch { return AgentToolResult.Failure(call.Name, "web_fetch_failed"); }
    }

    private static AgentToolResult Success(string name, Uri url, int statusCode, string text, TimeSpan duration)
    {
        var truncated = text.Length > MaximumResultCharacters;
        var result = truncated ? text[..MaximumResultCharacters] : text;
        return AgentToolResult.Success(name, JsonSerializer.SerializeToElement(new
        {
            bytes = Encoding.UTF8.GetByteCount(result), code = statusCode, result,
            durationMs = (int)duration.TotalMilliseconds, url = url.AbsoluteUri, truncated,
        }));
    }

    internal static bool IsPermittedRedirect(Uri original, Uri redirect) => original.Scheme == redirect.Scheme
        && original.Port == redirect.Port && string.IsNullOrEmpty(redirect.UserInfo)
        && string.Equals(RemoveWww(original.Host), RemoveWww(redirect.Host), StringComparison.OrdinalIgnoreCase);

    internal static string ExtractText(string body, string contentType)
    {
        if (!contentType.Contains("html", StringComparison.OrdinalIgnoreCase)
            && !body.Contains("<html", StringComparison.OrdinalIgnoreCase)) return body.Trim();
        var text = Regex.Replace(body, @"(?is)<(script|style)\b[^>]*>.*?</\1>", string.Empty);
        for (var level = 1; level <= 6; level++) text = Regex.Replace(text, $@"(?is)<h{level}\b[^>]*>(.*?)</h{level}>", new string('#', level) + " $1\n");
        text = Regex.Replace(text, @"(?is)</p\s*>", "\n\n");
        text = Regex.Replace(text, @"(?is)<br\s*/?>", "\n");
        text = Regex.Replace(text, @"(?is)<[^>]+>", string.Empty);
        text = text.Replace("&nbsp;", " ").Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">").Replace("&quot;", "\"");
        text = Regex.Replace(text, @"(?m)[ \t]+$", string.Empty);
        return Regex.Replace(text, @"\n{3,}", "\n\n").Trim();
    }

    private static bool TryUrl(JsonElement args, out Uri url)
    {
        url = null!;
        if (!TryNonEmptyString(args, "url", out var value) || !Uri.TryCreate(value, UriKind.Absolute, out var parsed)
            || parsed is null || parsed.Scheme is not ("http" or "https") || !string.IsNullOrEmpty(parsed.UserInfo)) return false;
        url = parsed; return true;
    }
    private static bool TryNonEmptyString(JsonElement args, string name, out string value)
    {
        value = string.Empty;
        return args.ValueKind == JsonValueKind.Object && args.TryGetProperty(name, out var item)
            && item.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(value = item.GetString() ?? string.Empty);
    }
    private static string RemoveWww(string host) => host.StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? host[4..] : host;
}
