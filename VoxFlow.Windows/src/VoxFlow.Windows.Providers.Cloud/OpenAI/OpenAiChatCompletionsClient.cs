using System.Net;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;

namespace VoxFlow.Windows.Providers.Cloud.OpenAI;

public enum OpenAiClientError
{
    NetworkFailure,
    HttpFailure,
    InterruptedStream,
    EmptyResponse,
    InvalidResponse,
}

public sealed class OpenAiClientException : Exception
{
    public OpenAiClientException(
        OpenAiClientError error,
        HttpStatusCode? statusCode = null,
        Exception? innerException = null)
        : base(CreateMessage(error, statusCode), innerException)
    {
        Error = error;
        StatusCode = statusCode;
    }

    public OpenAiClientError Error { get; }

    public HttpStatusCode? StatusCode { get; }

    private static string CreateMessage(
        OpenAiClientError error,
        HttpStatusCode? statusCode) => statusCode is null
            ? $"OpenAI streaming request failed ({error})."
            : $"OpenAI streaming request failed ({error}/{(int)statusCode.Value}).";
}

/// <summary>
/// Minimal Chat Completions SSE client used by conservative dictation cleanup.
/// The request shape follows the official OpenAI API reference:
/// https://platform.openai.com/docs/api-reference/chat/create
/// </summary>
public sealed class OpenAiChatCompletionsClient : IOpenAiConnectionTester
{
    private const int MaximumSseLineChars = 1024 * 1024;
    private const int MaximumOutputChars = 1024 * 1024;
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private const string ConservativeInstruction =
        "Conservatively clean up the dictated text. Preserve meaning, facts, language, " +
        "names, numbers, code, and formatting. Correct only obvious speech-recognition, " +
        "punctuation, spacing, and disfluency issues. Return only the corrected text.";

    private readonly HttpClient httpClient;

    public OpenAiChatCompletionsClient(HttpClient httpClient)
    {
        this.httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
    }

    public static Uri BuildChatCompletionsUri(Uri baseUri)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        if (!baseUri.IsAbsoluteUri
            || !string.Equals(baseUri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("An HTTPS OpenAI base URL is required.", nameof(baseUri));
        }

        var path = baseUri.AbsolutePath.TrimEnd('/');
        if (!path.EndsWith("/chat/completions", StringComparison.OrdinalIgnoreCase))
        {
            path = $"{path}/chat/completions";
        }

        var builder = new UriBuilder(baseUri)
        {
            Path = path,
            Query = string.Empty,
            Fragment = string.Empty,
        };
        return builder.Uri;
    }

    public async IAsyncEnumerable<string> StreamRefinementAsync(
        OpenAiClientConfiguration configuration,
        string input,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        await foreach (var snapshot in StreamChatAsync(
            configuration,
            ConservativeInstruction,
            input,
            cancellationToken).ConfigureAwait(false))
        {
            yield return snapshot;
        }
    }

    public async IAsyncEnumerable<string> StreamChatAsync(
        OpenAiClientConfiguration configuration,
        string systemInstruction,
        string input,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentException.ThrowIfNullOrWhiteSpace(systemInstruction);
        ArgumentException.ThrowIfNullOrWhiteSpace(input);
        using var request = CreateRequest(configuration, systemInstruction, input);
        HttpResponseMessage response;
        try
        {
            response = await httpClient.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (HttpRequestException exception)
        {
            throw new OpenAiClientException(
                OpenAiClientError.NetworkFailure,
                innerException: exception);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new OpenAiClientException(
                    OpenAiClientError.HttpFailure,
                    response.StatusCode);
            }

            await using var responseStream = await response.Content
                .ReadAsStreamAsync(cancellationToken)
                .ConfigureAwait(false);
            using var reader = new StreamReader(
                responseStream,
                StrictUtf8,
                detectEncodingFromByteOrderMarks: true,
                bufferSize: 4096,
                leaveOpen: false);
            List<string> dataLines = [];
            var cumulative = new StringBuilder();
            var sawDone = false;

            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var line = await reader.ReadLineAsync(cancellationToken)
                    .ConfigureAwait(false);
                if (line is not null && line.Length > MaximumSseLineChars)
                {
                    throw new OpenAiClientException(OpenAiClientError.InvalidResponse);
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
                    if (string.Equals(data.Trim(), "[DONE]", StringComparison.Ordinal))
                    {
                        sawDone = true;
                        break;
                    }

                    if (TryReadContentDelta(data, out var delta)
                        && !string.IsNullOrEmpty(delta))
                    {
                        if (cumulative.Length + delta.Length > MaximumOutputChars)
                        {
                            throw new OpenAiClientException(
                                OpenAiClientError.InvalidResponse);
                        }

                        cumulative.Append(delta);
                        yield return cumulative.ToString();
                    }
                }

                if (line is null)
                {
                    break;
                }
            }

            if (!sawDone)
            {
                throw new OpenAiClientException(OpenAiClientError.InterruptedStream);
            }

            if (cumulative.Length == 0)
            {
                throw new OpenAiClientException(OpenAiClientError.EmptyResponse);
            }
        }
    }

    public async ValueTask<OpenAiConnectionTestResult> TestAsync(
        OpenAiClientConfiguration configuration,
        CancellationToken cancellationToken)
    {
        try
        {
            var received = false;
            await foreach (var _ in StreamRefinementAsync(
                configuration,
                "Connection test. Return the word OK only.",
                cancellationToken))
            {
                received = true;
            }

            return received
                ? OpenAiConnectionTestResult.Success
                : new OpenAiConnectionTestResult(
                    false,
                    OpenAiConnectionTestError.ConnectionFailed);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return new OpenAiConnectionTestResult(
                false,
                OpenAiConnectionTestError.ConnectionFailed);
        }
    }

    public override string ToString() => "OpenAiChatCompletionsClient";

    private static HttpRequestMessage CreateRequest(
        OpenAiClientConfiguration configuration,
        string systemInstruction,
        string input)
    {
        var body = JsonSerializer.SerializeToUtf8Bytes(new
        {
            model = configuration.Model,
            messages = new object[]
            {
                new { role = "system", content = systemInstruction },
                new { role = "user", content = input },
            },
            stream = true,
        });
        var request = new HttpRequestMessage(
            HttpMethod.Post,
            BuildChatCompletionsUri(configuration.BaseUri))
        {
            Content = new ByteArrayContent(body),
        };
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json")
        {
            CharSet = "utf-8",
        };
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            configuration.ApiKey);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("text/event-stream"));
        return request;
    }

    private static bool TryReadContentDelta(string data, out string? delta)
    {
        delta = null;
        try
        {
            using var document = JsonDocument.Parse(data, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 32,
            });
            var root = document.RootElement;
            if (!root.TryGetProperty("choices", out var choices)
                || choices.ValueKind != JsonValueKind.Array
                || choices.GetArrayLength() == 0)
            {
                return false;
            }

            var choice = choices[0];
            if (!choice.TryGetProperty("delta", out var deltaObject)
                || deltaObject.ValueKind != JsonValueKind.Object
                || !deltaObject.TryGetProperty("content", out var content)
                || content.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            delta = content.GetString();
            return true;
        }
        catch (JsonException)
        {
            // A malformed non-terminal event is ignored. A stream containing no
            // valid content still fails closed as EmptyResponse at [DONE].
            return false;
        }
    }
}
