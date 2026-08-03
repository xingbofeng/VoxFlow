using System.Runtime.CompilerServices;
using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.Application.Screenshot;

public sealed class ScreenshotTransformService : IScreenshotTransformStreamingService
{
    private const double FixedTemperature = 0.2;

    private readonly IDefaultLlmProviderResolver defaultProvider;
    private readonly ILlmStreamingClient client;
    private readonly IScreenshotTransformCache cache;

    public ScreenshotTransformService(
        IDefaultLlmProviderResolver defaultProvider,
        ILlmStreamingClient client,
        IScreenshotTransformCache cache)
    {
        this.defaultProvider = defaultProvider
            ?? throw new ArgumentNullException(nameof(defaultProvider));
        this.client = client ?? throw new ArgumentNullException(nameof(client));
        this.cache = cache ?? throw new ArgumentNullException(nameof(cache));
    }

    public async IAsyncEnumerable<ScreenshotTransformEvent> TransformAsync(
        ScreenshotTransformRequest request,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        yield return new ScreenshotTransformStarted(
            request.RunId,
            request.ScreenshotId,
            request.Operation);

        if (cancellationToken.IsCancellationRequested)
        {
            yield return Cancelled(request, string.Empty);
            yield break;
        }

        if (cache.TryGet(request, out var cached))
        {
            yield return new ScreenshotTransformCompleted(
                request.RunId,
                request.ScreenshotId,
                request.Operation,
                cached,
                fromCache: true);
            yield break;
        }

        LlmProviderClientConfiguration? configuredProvider = null;
        var resolverCancelled = false;
        var resolverFailed = false;
        try
        {
            configuredProvider = await defaultProvider.ResolveDefaultAsync(cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            resolverCancelled = true;
        }
        catch
        {
            resolverFailed = true;
        }
        if (resolverCancelled)
        {
            yield return Cancelled(request, string.Empty);
            yield break;
        }
        if (resolverFailed)
        {
            yield return Failed(request, "screenshot.transform.provider_unavailable", string.Empty);
            yield break;
        }
        if (configuredProvider is null)
        {
            yield return Failed(request, "screenshot.transform.provider_not_configured", string.Empty);
            yield break;
        }

        var provider = new LlmProviderClientConfiguration(
            configuredProvider.ProviderId,
            configuredProvider.BaseUri,
            configuredProvider.Model,
            configuredProvider.ApiKey,
            FixedTemperature,
            configuredProvider.Timeout);
        var prompt = ScreenshotTransformPromptCatalog.For(request.Operation);
        var completionRequest = new LlmCompletionRequest(
        [
            new LlmChatMessage(LlmMessageRole.System, prompt.SystemPrompt),
            new LlmChatMessage(LlmMessageRole.User, request.SourceText),
        ], prompt.MaxOutputTokens);
        var latestText = string.Empty;
        var receivedFinal = false;

        await using var enumerator = client.StreamAsync(provider, completionRequest, cancellationToken)
            .GetAsyncEnumerator(cancellationToken);
        while (true)
        {
            LlmStreamUpdate? update = null;
            var hasNext = false;
            var streamCancelled = false;
            var streamFailed = false;
            try
            {
                hasNext = await enumerator.MoveNextAsync().ConfigureAwait(false);
                update = hasNext ? enumerator.Current : null;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                streamCancelled = true;
            }
            catch
            {
                streamFailed = true;
            }
            if (streamCancelled)
            {
                yield return Cancelled(request, latestText);
                yield break;
            }
            if (streamFailed)
            {
                yield return Failed(request, "screenshot.transform.request_failed", latestText);
                yield break;
            }
            if (cancellationToken.IsCancellationRequested)
            {
                yield return Cancelled(request, latestText);
                yield break;
            }

            if (!hasNext)
            {
                break;
            }
            if (receivedFinal)
            {
                continue;
            }
            if (!string.Equals(latestText, update!.AccumulatedText, StringComparison.Ordinal))
            {
                latestText = update.AccumulatedText;
                yield return new ScreenshotTransformPartial(
                    request.RunId,
                    request.ScreenshotId,
                    request.Operation,
                    latestText);
            }
            if (update.IsFinal)
            {
                receivedFinal = true;
                var finalText = NormalizeFinal(request.Operation, update.AccumulatedText);
                if (string.IsNullOrWhiteSpace(finalText))
                {
                    yield return Failed(request, "screenshot.transform.empty_result", latestText);
                    yield break;
                }
                if (cancellationToken.IsCancellationRequested)
                {
                    yield return Cancelled(request, latestText);
                    yield break;
                }
                cache.Store(request, finalText);
                yield return new ScreenshotTransformCompleted(
                    request.RunId,
                    request.ScreenshotId,
                    request.Operation,
                    finalText,
                    fromCache: false);
            }
        }

        if (receivedFinal)
        {
            yield break;
        }
        var completedText = NormalizeFinal(request.Operation, latestText);
        if (string.IsNullOrWhiteSpace(completedText))
        {
            yield return Failed(request, "screenshot.transform.empty_result", latestText);
            yield break;
        }
        if (cancellationToken.IsCancellationRequested)
        {
            yield return Cancelled(request, latestText);
            yield break;
        }
        cache.Store(request, completedText);
        yield return new ScreenshotTransformCompleted(
            request.RunId,
            request.ScreenshotId,
            request.Operation,
            completedText,
            fromCache: false);
    }

    private static ScreenshotTransformCancelled Cancelled(
        ScreenshotTransformRequest request,
        string partialText) => new(
            request.RunId,
            request.ScreenshotId,
            request.Operation,
            partialText);

    private static ScreenshotTransformFailed Failed(
        ScreenshotTransformRequest request,
        string safeMessage,
        string partialText) => new(
            request.RunId,
            request.ScreenshotId,
            request.Operation,
            safeMessage,
            partialText);

    private static string NormalizeFinal(
        ScreenshotTransformOperation operation,
        string text)
    {
        var trimmed = text.Trim();
        if (operation != ScreenshotTransformOperation.Summary)
        {
            return trimmed;
        }
        return string.Join(
            '\n',
            trimmed.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Take(3));
    }
}
