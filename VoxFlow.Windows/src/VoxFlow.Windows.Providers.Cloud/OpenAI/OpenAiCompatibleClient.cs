using System.Net;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Providers.Cloud.OpenAI;

public enum OpenAiCompatibleClientError
{
    NetworkFailure,
    Timeout,
    HttpFailure,
    InterruptedStream,
    EmptyResponse,
    InvalidResponse,
}

public sealed class OpenAiCompatibleClientException : Exception
{
    public OpenAiCompatibleClientException(
        OpenAiCompatibleClientError error,
        HttpStatusCode? statusCode = null,
        Exception? innerException = null)
        : base(CreateSafeMessage(error, statusCode), innerException)
    {
        Error = error;
        StatusCode = statusCode;
    }

    public OpenAiCompatibleClientError Error { get; }

    public HttpStatusCode? StatusCode { get; }

    private static string CreateSafeMessage(
        OpenAiCompatibleClientError error,
        HttpStatusCode? statusCode) => statusCode is null
            ? $"OpenAI-compatible request failed ({error}); credential [REDACTED]."
            : $"OpenAI-compatible request failed ({error}/{(int)statusCode.Value}); credential [REDACTED].";
}

public sealed class OpenAiCompatibleClient
    : ILlmProviderClient
{
    private const int MaximumResponseBytes = 2 * 1024 * 1024;
    private const int MaximumSseLineChars = 1024 * 1024;
    private const int MaximumOutputChars = 1024 * 1024;
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);

    private readonly HttpClient httpClient;
    private readonly string userAgent;

    public OpenAiCompatibleClient(
        HttpClient httpClient,
        string? appVersion = null)
    {
        this.httpClient = httpClient
            ?? throw new ArgumentNullException(nameof(httpClient));
        userAgent = "VoxFlow/" + SanitizeVersion(appVersion);
    }

    public static Uri BuildChatCompletionsUri(Uri baseUri)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        var normalized = LlmProviderEndpoint.Normalize(baseUri.AbsoluteUri);
        var path = normalized.AbsolutePath.TrimEnd('/');
        var builder = new UriBuilder(normalized)
        {
            Path = path + "/chat/completions",
            Query = string.Empty,
            Fragment = string.Empty,
        };
        return builder.Uri;
    }

    public static Uri BuildModelsUri(Uri baseUri)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        var normalized = LlmProviderEndpoint.Normalize(baseUri.AbsoluteUri);
        var path = normalized.AbsolutePath.TrimEnd('/');
        path = path.EndsWith("/v1", StringComparison.OrdinalIgnoreCase)
            ? path + "/models"
            : path + "/v1/models";
        return new UriBuilder(normalized)
        {
            Path = path,
            Query = string.Empty,
            Fragment = string.Empty,
        }.Uri;
    }

    public async ValueTask<LlmCompletionResponse> CompleteAsync(
        LlmProviderClientConfiguration configuration,
        LlmCompletionRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();

        using var message = CreateCompletionRequest(
            configuration,
            request,
            userAgent);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeout.CancelAfter(configuration.Timeout);

        HttpResponseMessage response;
        try
        {
            response = await httpClient.SendAsync(
                    message,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeout.Token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException exception)
        {
            throw new OpenAiCompatibleClientException(
                OpenAiCompatibleClientError.Timeout,
                innerException: exception);
        }
        catch (HttpRequestException exception)
        {
            throw new OpenAiCompatibleClientException(
                OpenAiCompatibleClientError.NetworkFailure,
                innerException: exception);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new OpenAiCompatibleClientException(
                    OpenAiCompatibleClientError.HttpFailure,
                    response.StatusCode);
            }
            if (response.Content.Headers.ContentLength > MaximumResponseBytes)
            {
                throw new OpenAiCompatibleClientException(
                    OpenAiCompatibleClientError.InvalidResponse);
            }

            byte[] bytes;
            try
            {
                bytes = await response.Content.ReadAsByteArrayAsync(timeout.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException exception)
            {
                throw new OpenAiCompatibleClientException(
                    OpenAiCompatibleClientError.Timeout,
                    innerException: exception);
            }
            if (bytes.Length > MaximumResponseBytes)
            {
                throw new OpenAiCompatibleClientException(
                    OpenAiCompatibleClientError.InvalidResponse);
            }

            try
            {
                return ParseCompletion(
                    StrictUtf8.GetString(bytes),
                    configuration);
            }
            catch (OpenAiCompatibleClientException)
            {
                throw;
            }
            catch (Exception exception) when (exception is
                JsonException
                or DecoderFallbackException
                or ArgumentException
                or InvalidOperationException
                or OverflowException)
            {
                throw new OpenAiCompatibleClientException(
                    OpenAiCompatibleClientError.InvalidResponse,
                    innerException: exception);
            }
        }
    }

    public async IAsyncEnumerable<LlmStreamUpdate> StreamAsync(
        LlmProviderClientConfiguration configuration,
        LlmCompletionRequest request,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();

        using var message = CreateChatRequest(
            configuration,
            request,
            userAgent,
            stream: true,
            accept: "text/event-stream");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeout.CancelAfter(configuration.Timeout);

        HttpResponseMessage response;
        try
        {
            response = await httpClient.SendAsync(
                    message,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeout.Token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException exception)
        {
            throw new OpenAiCompatibleClientException(
                OpenAiCompatibleClientError.Timeout,
                innerException: exception);
        }
        catch (HttpRequestException exception)
        {
            throw new OpenAiCompatibleClientException(
                OpenAiCompatibleClientError.NetworkFailure,
                innerException: exception);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new OpenAiCompatibleClientException(
                    OpenAiCompatibleClientError.HttpFailure,
                    response.StatusCode);
            }

            Stream responseStream;
            try
            {
                responseStream = await response.Content
                    .ReadAsStreamAsync(timeout.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException exception)
            {
                throw new OpenAiCompatibleClientException(
                    OpenAiCompatibleClientError.Timeout,
                    innerException: exception);
            }

            await using (responseStream)
            using (var reader = new StreamReader(
                responseStream,
                StrictUtf8,
                detectEncodingFromByteOrderMarks: true,
                bufferSize: 4096,
                leaveOpen: false))
            {
                List<string> dataLines = [];
                var cumulative = new StringBuilder();
                AgentTokenUsage? lastUsage = null;
                var sawDone = false;

                while (true)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    string? line;
                    try
                    {
                        line = await reader.ReadLineAsync(timeout.Token)
                            .ConfigureAwait(false);
                    }
                    catch (OperationCanceledException) when (
                        cancellationToken.IsCancellationRequested)
                    {
                        throw;
                    }
                    catch (OperationCanceledException exception)
                    {
                        throw new OpenAiCompatibleClientException(
                            OpenAiCompatibleClientError.Timeout,
                            innerException: exception);
                    }
                    catch (DecoderFallbackException exception)
                    {
                        throw new OpenAiCompatibleClientException(
                            OpenAiCompatibleClientError.InvalidResponse,
                            innerException: exception);
                    }

                    if (line is not null && line.Length > MaximumSseLineChars)
                    {
                        throw new OpenAiCompatibleClientException(
                            OpenAiCompatibleClientError.InvalidResponse);
                    }
                    if (line is not null && line.Length != 0)
                    {
                        if (!line.StartsWith(':')
                            && line.StartsWith("data:", StringComparison.Ordinal))
                        {
                            var value = line[5..];
                            if (value.StartsWith(' '))
                            {
                                value = value[1..];
                            }
                            dataLines.Add(value);
                        }
                        continue;
                    }

                    if (dataLines.Count > 0)
                    {
                        var data = string.Join('\n', dataLines);
                        dataLines.Clear();
                        if (string.Equals(
                            data.Trim(),
                            "[DONE]",
                            StringComparison.Ordinal))
                        {
                            sawDone = true;
                            break;
                        }

                        var parsed = ParseStreamEvent(data);
                        if (parsed.TokenUsage is not null)
                        {
                            lastUsage = parsed.TokenUsage;
                        }
                        if (!string.IsNullOrEmpty(parsed.DeltaText))
                        {
                            if (cumulative.Length + parsed.DeltaText.Length
                                > MaximumOutputChars)
                            {
                                throw new OpenAiCompatibleClientException(
                                    OpenAiCompatibleClientError.InvalidResponse);
                            }
                            cumulative.Append(parsed.DeltaText);
                            yield return new LlmStreamUpdate(
                                parsed.DeltaText,
                                cumulative.ToString(),
                                isFinal: false,
                                tokenUsage: null);
                        }
                    }

                    if (line is null)
                    {
                        break;
                    }
                }

                if (!sawDone)
                {
                    throw new OpenAiCompatibleClientException(
                        OpenAiCompatibleClientError.InterruptedStream);
                }
                if (cumulative.Length == 0)
                {
                    throw new OpenAiCompatibleClientException(
                        OpenAiCompatibleClientError.EmptyResponse);
                }

                yield return new LlmStreamUpdate(
                    deltaText: string.Empty,
                    accumulatedText: cumulative.ToString(),
                    isFinal: true,
                    tokenUsage: lastUsage);
            }
        }
    }

    public async ValueTask<LlmModelDiscoveryResult> DiscoverModelsAsync(
        LlmProviderClientConfiguration configuration,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        cancellationToken.ThrowIfCancellationRequested();
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            BuildModelsUri(configuration.BaseUri));
        OpenAiCompatibleRequestHeaders.Apply(
            request,
            configuration.BaseUri,
            configuration.ApiKey,
            userAgent,
            "application/json");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeout.CancelAfter(configuration.Timeout);

        HttpResponseMessage response;
        try
        {
            response = await httpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeout.Token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException)
        {
            return FallbackModels(configuration, "models_request_timeout");
        }
        catch (HttpRequestException)
        {
            return FallbackModels(configuration, "models_request_failed");
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                return FallbackModels(
                    configuration,
                    "models_endpoint_unavailable");
            }
            if (response.Content.Headers.ContentLength > MaximumResponseBytes)
            {
                return FallbackModels(
                    configuration,
                    "models_response_unsupported");
            }

            byte[] bytes;
            try
            {
                bytes = await response.Content.ReadAsByteArrayAsync(timeout.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException)
            {
                return FallbackModels(configuration, "models_request_timeout");
            }
            if (bytes.Length > MaximumResponseBytes)
            {
                return FallbackModels(
                    configuration,
                    "models_response_unsupported");
            }

            IReadOnlyList<LlmModelDescriptor>? remote;
            try
            {
                remote = ParseModels(StrictUtf8.GetString(bytes));
            }
            catch (DecoderFallbackException)
            {
                remote = null;
            }
            if (remote is null || remote.Count == 0)
            {
                return FallbackModels(
                    configuration,
                    "models_response_unsupported");
            }

            return new LlmModelDiscoveryResult(
                MergeManual(configuration.Model, remote),
                LlmModelDiscoverySource.Remote);
        }
    }

    public async ValueTask<LlmConnectionTestResult> TestConnectionAsync(
        LlmProviderClientConfiguration configuration,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        var probeConfiguration = new LlmProviderClientConfiguration(
            configuration.ProviderId,
            configuration.BaseUri,
            configuration.Model,
            configuration.ApiKey,
            temperature: 0,
            configuration.Timeout);
        var request = new LlmCompletionRequest(
            [new LlmChatMessage(LlmMessageRole.User, "Reply exactly OK.")],
            maxOutputTokens: 32);
        var started = Stopwatch.GetTimestamp();
        try
        {
            _ = await CompleteAsync(
                    probeConfiguration,
                    request,
                    cancellationToken)
                .ConfigureAwait(false);
            return new LlmConnectionTestResult(
                LlmConnectionTestStatus.Succeeded,
                latencyMs: Math.Max(
                    0,
                    (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds),
                safeMessage: null);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OpenAiCompatibleClientException exception)
        {
            return new LlmConnectionTestResult(
                LlmConnectionTestStatus.Failed,
                latencyMs: null,
                safeMessage: ConnectionFailureMessage(exception));
        }
    }

    public async ValueTask<LlmAgentCapabilityTestResult> TestAgentCapabilityAsync(
        LlmProviderClientConfiguration configuration,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        cancellationToken.ThrowIfCancellationRequested();
        using var request = CreateAgentProbeRequest(configuration, userAgent);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken);
        timeout.CancelAfter(configuration.Timeout);

        HttpResponseMessage response;
        try
        {
            response = await httpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeout.Token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException)
        {
            return new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Error,
                "agent_timeout");
        }
        catch (HttpRequestException)
        {
            return new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Error,
                "agent_network_failure");
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                return new LlmAgentCapabilityTestResult(
                    LlmAgentCapabilityStatus.Error,
                    $"agent_http_{(int)response.StatusCode}");
            }
            if (response.Content.Headers.ContentLength > MaximumResponseBytes)
            {
                return new LlmAgentCapabilityTestResult(
                    LlmAgentCapabilityStatus.Error,
                    "agent_response_invalid");
            }

            byte[] bytes;
            try
            {
                bytes = await response.Content.ReadAsByteArrayAsync(timeout.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException)
            {
                return new LlmAgentCapabilityTestResult(
                    LlmAgentCapabilityStatus.Error,
                    "agent_timeout");
            }
            if (bytes.Length > MaximumResponseBytes)
            {
                return new LlmAgentCapabilityTestResult(
                    LlmAgentCapabilityStatus.Error,
                    "agent_response_invalid");
            }

            try
            {
                return ParseAgentCapability(StrictUtf8.GetString(bytes));
            }
            catch (DecoderFallbackException)
            {
                return new LlmAgentCapabilityTestResult(
                    LlmAgentCapabilityStatus.Error,
                    "agent_response_invalid");
            }
        }
    }

    public override string ToString() =>
        "OpenAiCompatibleClient { Credential = [REDACTED] }";

    internal static HttpRequestMessage CreateCompletionRequest(
        LlmProviderClientConfiguration configuration,
        LlmCompletionRequest request,
        string userAgent)
        => CreateChatRequest(
            configuration,
            request,
            userAgent,
            stream: false,
            accept: "application/json");

    private static HttpRequestMessage CreateChatRequest(
        LlmProviderClientConfiguration configuration,
        LlmCompletionRequest request,
        string userAgent,
        bool stream,
        string accept)
    {
        var messages = request.Messages.Select(message => new
        {
            role = ToStorage(message.Role),
            content = message.Content,
        }).ToArray();
        var body = new Dictionary<string, object?>
        {
            ["model"] = NormalizeModelId(configuration.Model),
            ["messages"] = messages,
            ["temperature"] = configuration.Temperature,
            ["stream"] = stream,
        };
        if (request.MaxOutputTokens is not null)
        {
            body["max_tokens"] = request.MaxOutputTokens.Value;
        }

        var content = new ByteArrayContent(
            JsonSerializer.SerializeToUtf8Bytes(body));
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json")
        {
            CharSet = "utf-8",
        };
        var message = new HttpRequestMessage(
            HttpMethod.Post,
            BuildChatCompletionsUri(configuration.BaseUri))
        {
            Content = content,
        };
        OpenAiCompatibleRequestHeaders.Apply(
            message,
            configuration.BaseUri,
            configuration.ApiKey,
            userAgent,
            accept);
        return message;
    }

    private static HttpRequestMessage CreateAgentProbeRequest(
        LlmProviderClientConfiguration configuration,
        string userAgent)
    {
        var body = new
        {
            model = NormalizeModelId(configuration.Model),
            messages = new[]
            {
                new
                {
                    role = "user",
                    content =
                        "Call voxflow_capability_probe with a short value. Do not perform any other action.",
                },
            },
            tools = new[]
            {
                new
                {
                    type = "function",
                    function = new
                    {
                        name = "voxflow_capability_probe",
                        description =
                            "A no-side-effect compatibility probe that only validates tool calling.",
                        parameters = new
                        {
                            type = "object",
                            properties = new
                            {
                                value = new { type = "string" },
                            },
                            required = new[] { "value" },
                            additionalProperties = false,
                        },
                    },
                },
            },
            tool_choice = "auto",
            temperature = 0,
            max_tokens = 64,
            stream = false,
        };
        var content = new ByteArrayContent(
            JsonSerializer.SerializeToUtf8Bytes(body));
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json")
        {
            CharSet = "utf-8",
        };
        var request = new HttpRequestMessage(
            HttpMethod.Post,
            BuildChatCompletionsUri(configuration.BaseUri))
        {
            Content = content,
        };
        OpenAiCompatibleRequestHeaders.Apply(
            request,
            configuration.BaseUri,
            configuration.ApiKey,
            userAgent,
            "application/json");
        return request;
    }

    private static LlmAgentCapabilityTestResult ParseAgentCapability(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 64,
            });
            var root = document.RootElement;
            if (!root.TryGetProperty("choices", out var choices)
                || choices.ValueKind != JsonValueKind.Array
                || choices.GetArrayLength() == 0
                || !choices[0].TryGetProperty("message", out var message)
                || message.ValueKind != JsonValueKind.Object)
            {
                return new LlmAgentCapabilityTestResult(
                    LlmAgentCapabilityStatus.Error,
                    "agent_response_invalid");
            }
            if (!message.TryGetProperty("tool_calls", out var calls)
                || calls.ValueKind == JsonValueKind.Null
                || (calls.ValueKind == JsonValueKind.Array
                    && calls.GetArrayLength() == 0))
            {
                return new LlmAgentCapabilityTestResult(
                    LlmAgentCapabilityStatus.Unsupported,
                    "tool_calls_missing");
            }
            if (calls.ValueKind != JsonValueKind.Array)
            {
                return new LlmAgentCapabilityTestResult(
                    LlmAgentCapabilityStatus.Error,
                    "tool_calls_invalid");
            }

            foreach (var call in calls.EnumerateArray())
            {
                if (!IsValidProbeCall(call))
                {
                    return new LlmAgentCapabilityTestResult(
                        LlmAgentCapabilityStatus.Error,
                        "tool_calls_invalid");
                }
            }
            return new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Supported,
                safeMessage: null);
        }
        catch (JsonException)
        {
            return new LlmAgentCapabilityTestResult(
                LlmAgentCapabilityStatus.Error,
                "agent_response_invalid");
        }
    }

    private static bool IsValidProbeCall(JsonElement call)
    {
        if (call.ValueKind != JsonValueKind.Object
            || !call.TryGetProperty("type", out var type)
            || type.ValueKind != JsonValueKind.String
            || type.GetString() != "function"
            || !call.TryGetProperty("function", out var function)
            || function.ValueKind != JsonValueKind.Object
            || !function.TryGetProperty("name", out var name)
            || name.ValueKind != JsonValueKind.String
            || name.GetString() != "voxflow_capability_probe"
            || !function.TryGetProperty("arguments", out var arguments)
            || arguments.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        try
        {
            using var parsed = JsonDocument.Parse(arguments.GetString()!);
            return parsed.RootElement.ValueKind == JsonValueKind.Object;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static string ConnectionFailureMessage(
        OpenAiCompatibleClientException exception) => exception.Error switch
    {
        OpenAiCompatibleClientError.HttpFailure when exception.StatusCode is not null =>
            $"connection_http_{(int)exception.StatusCode.Value}",
        OpenAiCompatibleClientError.Timeout => "connection_timeout",
        OpenAiCompatibleClientError.NetworkFailure => "connection_network_failure",
        OpenAiCompatibleClientError.EmptyResponse => "connection_empty_response",
        _ => "connection_invalid_response",
    };

    private static StreamEvent ParseStreamEvent(string data)
    {
        try
        {
            using var document = JsonDocument.Parse(data, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 64,
            });
            var root = document.RootElement;
            var usage = ReadTokenUsage(root);
            if (!root.TryGetProperty("choices", out var choices)
                || choices.ValueKind != JsonValueKind.Array
                || choices.GetArrayLength() == 0
                || !choices[0].TryGetProperty("delta", out var delta)
                || delta.ValueKind != JsonValueKind.Object
                || !delta.TryGetProperty("content", out var content)
                || content.ValueKind is not JsonValueKind.String)
            {
                return new StreamEvent(null, usage);
            }
            return new StreamEvent(content.GetString(), usage);
        }
        catch (JsonException)
        {
            // Match the macOS/legacy parser: malformed non-terminal provider
            // events are ignored. A stream with no valid text still fails at
            // DONE, and a missing DONE still fails as interrupted.
            return new StreamEvent(null, null);
        }
    }

    private static IReadOnlyList<LlmModelDescriptor>? ParseModels(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 32,
            });
            var root = document.RootElement;
            JsonElement entries;
            if (root.ValueKind == JsonValueKind.Array)
            {
                entries = root;
            }
            else if (root.ValueKind == JsonValueKind.Object
                && root.TryGetProperty("data", out var data)
                && data.ValueKind == JsonValueKind.Array)
            {
                entries = data;
            }
            else if (root.ValueKind == JsonValueKind.Object
                && root.TryGetProperty("models", out var models)
                && models.ValueKind == JsonValueKind.Array)
            {
                entries = models;
            }
            else
            {
                return null;
            }

            List<LlmModelDescriptor> parsed = [];
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var entry in entries.EnumerateArray())
            {
                string? id = null;
                string? displayName = null;
                string? ownedBy = null;
                if (entry.ValueKind == JsonValueKind.String)
                {
                    id = entry.GetString();
                }
                else if (entry.ValueKind == JsonValueKind.Object)
                {
                    id = FirstString(entry, "id", "name", "model");
                    displayName = FirstString(entry, "display_name", "displayName");
                    ownedBy = FirstString(entry, "owned_by", "ownedBy");
                }

                id = NormalizeOptionalModelId(id);
                if (id is null || !seen.Add(id))
                {
                    continue;
                }
                parsed.Add(new LlmModelDescriptor(id, displayName, ownedBy));
            }
            return parsed.ToArray();
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? FirstString(
        JsonElement element,
        params string[] names)
    {
        foreach (var name in names)
        {
            if (element.TryGetProperty(name, out var value)
                && value.ValueKind == JsonValueKind.String
                && !string.IsNullOrWhiteSpace(value.GetString()))
            {
                return value.GetString()!.Trim();
            }
        }
        return null;
    }

    private static string? NormalizeOptionalModelId(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }
        var normalized = value.Trim();
        if (normalized.Contains('\r', StringComparison.Ordinal)
            || normalized.Contains('\n', StringComparison.Ordinal))
        {
            return null;
        }
        return normalized.StartsWith("models/", StringComparison.Ordinal)
            ? normalized["models/".Length..]
            : normalized;
    }

    private static IReadOnlyList<LlmModelDescriptor> MergeManual(
        string manualModel,
        IReadOnlyList<LlmModelDescriptor> discovered)
    {
        var manual = NormalizeModelId(manualModel);
        List<LlmModelDescriptor> merged = [];
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var remoteManual = discovered.FirstOrDefault(model =>
            string.Equals(model.Id, manual, StringComparison.Ordinal));
        merged.Add(remoteManual ?? new LlmModelDescriptor(manual, null, null));
        _ = seen.Add(manual);
        foreach (var model in discovered)
        {
            if (seen.Add(model.Id))
            {
                merged.Add(model);
            }
        }
        return merged.ToArray();
    }

    private static LlmModelDiscoveryResult FallbackModels(
        LlmProviderClientConfiguration configuration,
        string safeMessage)
    {
        var catalog = LlmProviderTemplateCatalog.FallbackModelIds(
                configuration.BaseUri)
            .Select(model => new LlmModelDescriptor(model, null, null))
            .ToArray();
        var merged = MergeManual(configuration.Model, catalog);
        return new LlmModelDiscoveryResult(
            merged,
            catalog.Length > 0
                ? LlmModelDiscoverySource.CatalogFallback
                : LlmModelDiscoverySource.ManualOnly,
            safeMessage);
    }

    private static LlmCompletionResponse ParseCompletion(
        string json,
        LlmProviderClientConfiguration configuration)
    {
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 64,
        });
        var root = document.RootElement;
        if (!root.TryGetProperty("choices", out var choices)
            || choices.ValueKind != JsonValueKind.Array
            || choices.GetArrayLength() == 0
            || !choices[0].TryGetProperty("message", out var message)
            || message.ValueKind != JsonValueKind.Object)
        {
            throw new OpenAiCompatibleClientException(
                OpenAiCompatibleClientError.InvalidResponse);
        }

        var text = ReadMessageText(message);
        if (string.IsNullOrWhiteSpace(text))
        {
            throw new OpenAiCompatibleClientException(
                OpenAiCompatibleClientError.EmptyResponse);
        }

        var model = root.TryGetProperty("model", out var modelElement)
            && modelElement.ValueKind == JsonValueKind.String
            && !string.IsNullOrWhiteSpace(modelElement.GetString())
                ? modelElement.GetString()!.Trim()
                : configuration.Model;
        return new LlmCompletionResponse(
            text,
            configuration.ProviderId,
            model,
            ReadTokenUsage(root));
    }

    private static string? ReadMessageText(JsonElement message)
    {
        if (message.TryGetProperty("content", out var content))
        {
            if (content.ValueKind == JsonValueKind.String)
            {
                return content.GetString();
            }
            if (content.ValueKind == JsonValueKind.Array)
            {
                var builder = new StringBuilder();
                foreach (var block in content.EnumerateArray())
                {
                    if (block.ValueKind == JsonValueKind.Object
                        && block.TryGetProperty("text", out var text)
                        && text.ValueKind == JsonValueKind.String)
                    {
                        builder.Append(text.GetString());
                    }
                }
                if (builder.Length > 0)
                {
                    return builder.ToString();
                }
            }
            else if (content.ValueKind is not JsonValueKind.Null)
            {
                throw new OpenAiCompatibleClientException(
                    OpenAiCompatibleClientError.InvalidResponse);
            }
        }

        foreach (var propertyName in new[] { "reasoning_content", "reasoning" })
        {
            if (message.TryGetProperty(propertyName, out var reasoning)
                && reasoning.ValueKind == JsonValueKind.String
                && !string.IsNullOrEmpty(reasoning.GetString()))
            {
                return reasoning.GetString();
            }
        }
        return null;
    }

    private static AgentTokenUsage? ReadTokenUsage(JsonElement root)
    {
        if (!root.TryGetProperty("usage", out var usage)
            || usage.ValueKind != JsonValueKind.Object)
        {
            return null;
        }
        var input = ReadNullableCount(usage, "prompt_tokens")
            ?? ReadNullableCount(usage, "input_tokens");
        var output = ReadNullableCount(usage, "completion_tokens")
            ?? ReadNullableCount(usage, "output_tokens");
        var total = ReadNullableCount(usage, "total_tokens");
        return input is null && output is null && total is null
            ? null
            : new AgentTokenUsage(input, output, total);
    }

    private static int? ReadNullableCount(
        JsonElement parent,
        string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var value)
            || value.ValueKind == JsonValueKind.Null)
        {
            return null;
        }
        if (value.ValueKind != JsonValueKind.Number
            || !value.TryGetInt32(out var parsed)
            || parsed < 0)
        {
            throw new OpenAiCompatibleClientException(
                OpenAiCompatibleClientError.InvalidResponse);
        }
        return parsed;
    }

    internal static string NormalizeModelId(string model)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(model);
        var normalized = model.Trim();
        return normalized.StartsWith("models/", StringComparison.Ordinal)
            ? normalized["models/".Length..]
            : normalized;
    }

    private static string ToStorage(LlmMessageRole role) => role switch
    {
        LlmMessageRole.System => "system",
        LlmMessageRole.User => "user",
        LlmMessageRole.Assistant => "assistant",
        LlmMessageRole.Tool => "tool",
        _ => throw new ArgumentOutOfRangeException(nameof(role), role, null),
    };

    private static string SanitizeVersion(string? version)
    {
        var value = string.IsNullOrWhiteSpace(version) ? "dev" : version.Trim();
        var sanitized = new string(value.Select(character =>
            char.IsAsciiLetterOrDigit(character)
                || character is '.' or '-' or '_'
                    ? character
                    : '-').ToArray()).Trim('-', '.', '_');
        return sanitized.Length == 0 ? "dev" : sanitized;
    }

    private sealed record StreamEvent(
        string? DeltaText,
        AgentTokenUsage? TokenUsage);
}

internal static class OpenAiCompatibleRequestHeaders
{
    public static void Apply(
        HttpRequestMessage request,
        Uri baseUri,
        string? apiKey,
        string userAgent,
        string defaultAccept)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(baseUri);
        ArgumentException.ThrowIfNullOrWhiteSpace(userAgent);
        ArgumentException.ThrowIfNullOrWhiteSpace(defaultAccept);

        request.Headers.Accept.Clear();
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue(defaultAccept));
        request.Headers.UserAgent.Clear();
        _ = request.Headers.UserAgent.TryParseAdd(userAgent);
        if (!string.IsNullOrWhiteSpace(apiKey))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue(
                "Bearer",
                apiKey.Trim());
        }

        var host = baseUri.Host.ToLowerInvariant();
        if (host == "models.github.ai")
        {
            request.Headers.Accept.Clear();
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue(
                "application/vnd.github+json"));
            request.Headers.TryAddWithoutValidation(
                "X-GitHub-Api-Version",
                "2022-11-28");
        }
        if (host == "openrouter.ai")
        {
            request.Headers.TryAddWithoutValidation(
                "HTTP-Referer",
                "https://mashangxie.app");
            request.Headers.TryAddWithoutValidation("X-Title", "VoxFlow");
        }
    }
}
