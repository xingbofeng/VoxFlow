using System.Net;
using System.Runtime.CompilerServices;
using VoxFlow.Windows.Application.Llm;

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
        => OpenAiCompatibleClient.BuildChatCompletionsUri(baseUri);

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
        var generic = new OpenAiCompatibleClient(httpClient, "dev");
        var provider = new LlmProviderClientConfiguration(
            providerId: "openai-legacy-adapter",
            configuration.BaseUri,
            configuration.Model,
            configuration.ApiKey,
            temperature: 0,
            timeout: TimeSpan.FromSeconds(300));
        var request = new LlmCompletionRequest(
        [
            new LlmChatMessage(LlmMessageRole.System, systemInstruction),
            new LlmChatMessage(LlmMessageRole.User, input),
        ]);

        await using var enumerator = generic.StreamAsync(
                provider,
                request,
                cancellationToken)
            .GetAsyncEnumerator(cancellationToken);
        while (true)
        {
            bool hasNext;
            try
            {
                hasNext = await enumerator.MoveNextAsync().ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (
                cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OpenAiCompatibleClientException exception)
            {
                throw new OpenAiClientException(
                    MapError(exception.Error),
                    exception.StatusCode,
                    innerException: exception);
            }

            if (!hasNext)
            {
                break;
            }
            if (!enumerator.Current.IsFinal)
            {
                yield return enumerator.Current.AccumulatedText;
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

    private static OpenAiClientError MapError(
        OpenAiCompatibleClientError error) => error switch
    {
        OpenAiCompatibleClientError.NetworkFailure => OpenAiClientError.NetworkFailure,
        OpenAiCompatibleClientError.Timeout => OpenAiClientError.NetworkFailure,
        OpenAiCompatibleClientError.HttpFailure => OpenAiClientError.HttpFailure,
        OpenAiCompatibleClientError.InterruptedStream => OpenAiClientError.InterruptedStream,
        OpenAiCompatibleClientError.EmptyResponse => OpenAiClientError.EmptyResponse,
        OpenAiCompatibleClientError.InvalidResponse => OpenAiClientError.InvalidResponse,
        _ => throw new ArgumentOutOfRangeException(nameof(error), error, null),
    };
}
