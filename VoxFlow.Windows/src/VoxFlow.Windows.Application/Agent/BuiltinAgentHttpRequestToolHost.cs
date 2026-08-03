using System.Net.Http;
using System.Text;
using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentHttpResponse(int StatusCode, string Body);

public interface IAgentHttpRequestClient
{
    Task<AgentHttpResponse> SendAsync(
        HttpMethod method,
        Uri uri,
        IReadOnlyDictionary<string, string> headers,
        string? body,
        CancellationToken cancellationToken);
}

public sealed class AgentHttpRequestClient(HttpClient client) : IAgentHttpRequestClient
{
    private readonly HttpClient client = client ?? throw new ArgumentNullException(nameof(client));

    public async Task<AgentHttpResponse> SendAsync(
        HttpMethod method,
        Uri uri,
        IReadOnlyDictionary<string, string> headers,
        string? body,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(method, uri);
        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8, "text/plain");
        }
        foreach (var header in headers)
        {
            if (!request.Headers.TryAddWithoutValidation(header.Key, header.Value))
            {
                _ = request.Content?.Headers.TryAddWithoutValidation(header.Key, header.Value);
            }
        }
        using var response = await client.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        return new AgentHttpResponse((int)response.StatusCode, responseBody);
    }
}

public sealed class BuiltinAgentHttpRequestToolHost
{
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(15);
    public const int MaximumResponseCharacters = 40_000;

    private static readonly IReadOnlyDictionary<string, HttpMethod> Methods =
        new Dictionary<string, HttpMethod>(StringComparer.OrdinalIgnoreCase)
        {
            ["GET"] = HttpMethod.Get,
            ["POST"] = HttpMethod.Post,
            ["PUT"] = HttpMethod.Put,
            ["PATCH"] = HttpMethod.Patch,
            ["DELETE"] = HttpMethod.Delete,
        };

    private readonly AgentToolAuthorizationPolicy authorization;
    private readonly IAgentHttpRequestClient client;
    private readonly TimeSpan timeout;

    public BuiltinAgentHttpRequestToolHost(
        AgentToolAuthorizationPolicy authorization,
        IAgentHttpRequestClient client,
        TimeSpan? timeout = null)
    {
        this.authorization = authorization ?? throw new ArgumentNullException(nameof(authorization));
        this.client = client ?? throw new ArgumentNullException(nameof(client));
        this.timeout = timeout ?? DefaultTimeout;
        if (this.timeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }
    }

    public async Task<AgentToolResult> ExecuteAsync(
        AgentToolCall call,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        if (!TryHttpsUrl(call.Arguments, out var uri))
        {
            return AgentToolResult.Failure(call.Name, "invalid_https_url");
        }
        if (!authorization.AllowsHttpRequest(uri))
        {
            return AgentToolResult.Failure(call.Name, "missing_explicit_user_intent");
        }
        var methodName = TryString(call.Arguments, "method", out var suppliedMethod)
            ? suppliedMethod.ToUpperInvariant()
            : "GET";
        if (!Methods.TryGetValue(methodName, out var method))
        {
            return AgentToolResult.Failure(call.Name, "unsupported_http_method");
        }
        if (!TryHeaders(call.Arguments, out var headers))
        {
            return AgentToolResult.Failure(call.Name, "invalid_headers");
        }
        var body = TryStringValue(call.Arguments, "body", out var suppliedBody)
            ? suppliedBody
            : null;

        using var timeoutCancellation = new CancellationTokenSource(timeout);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken, timeoutCancellation.Token);
        try
        {
            var response = await client.SendAsync(method, uri, headers, body, linked.Token)
                .ConfigureAwait(false);
            var truncated = response.Body.Length > MaximumResponseCharacters;
            return AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new
            {
                action = methodName,
                statusCode = response.StatusCode,
                body = truncated ? response.Body[..MaximumResponseCharacters] : response.Body,
                truncated,
            }));
        }
        catch (OperationCanceledException) when (timeoutCancellation.IsCancellationRequested
                                                 && !cancellationToken.IsCancellationRequested)
        {
            return AgentToolResult.Failure(call.Name, "http_timeout");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return AgentToolResult.Failure(call.Name, "http_request_failed");
        }
    }

    private static bool TryHttpsUrl(JsonElement arguments, out Uri uri)
    {
        uri = null!;
        if (!TryString(arguments, "url", out var value)
            || !Uri.TryCreate(value, UriKind.Absolute, out var parsed)
            || parsed is null
            || parsed.Scheme != Uri.UriSchemeHttps)
        {
            return false;
        }
        uri = parsed;
        return true;
    }

    private static bool TryHeaders(
        JsonElement arguments,
        out IReadOnlyDictionary<string, string> headers)
    {
        headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!arguments.TryGetProperty("headers", out var value))
        {
            return true;
        }
        if (value.ValueKind != JsonValueKind.Object)
        {
            return false;
        }
        foreach (var property in value.EnumerateObject())
        {
            if (string.IsNullOrWhiteSpace(property.Name)
                || property.Name.Contains('\r') || property.Name.Contains('\n')
                || property.Value.ValueKind != JsonValueKind.String)
            {
                return false;
            }
            var headerValue = property.Value.GetString() ?? string.Empty;
            if (headerValue.Contains('\r') || headerValue.Contains('\n'))
            {
                return false;
            }
            ((Dictionary<string, string>)headers)[property.Name] = headerValue;
        }
        return true;
    }

    private static bool TryString(JsonElement arguments, string name, out string value) =>
        TryStringValue(arguments, name, out value) && !string.IsNullOrWhiteSpace(value);

    private static bool TryStringValue(JsonElement arguments, string name, out string value)
    {
        value = string.Empty;
        if (arguments.ValueKind != JsonValueKind.Object
            || !arguments.TryGetProperty(name, out var property)
            || property.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        value = property.GetString() ?? string.Empty;
        return true;
    }
}
