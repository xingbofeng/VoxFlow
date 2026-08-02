using System.Runtime.CompilerServices;
using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.Application.SelectionTransform;

public sealed class SelectionTransformRequest
{
    public SelectionTransformRequest(
        Guid generation,
        string text,
        SelectionTransformOperation operation)
    {
        if (generation == Guid.Empty)
        {
            throw new ArgumentException("A non-empty generation is required.", nameof(generation));
        }
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        if (!Enum.IsDefined(operation))
        {
            throw new ArgumentOutOfRangeException(nameof(operation));
        }

        Generation = generation;
        Text = text;
        Operation = operation;
    }

    public Guid Generation { get; }

    public string Text { get; }

    public SelectionTransformOperation Operation { get; }
}

/// <summary>
/// Runs only the configured default OpenAI-compatible provider.  There is no
/// implicit provider failover: a missing default exits before network I/O and
/// an in-flight provider error preserves its already streamed partial text.
/// </summary>
public interface ISelectionTransformStreamingService
{
    IAsyncEnumerable<SelectionTransformEvent> TransformAsync(
        SelectionTransformRequest request,
        CancellationToken cancellationToken);
}

public sealed class SelectionTransformService : ISelectionTransformStreamingService
{
    private const double FixedTemperature = 0.2;
    private readonly IDefaultLlmProviderResolver defaultProvider;
    private readonly ILlmStreamingClient client;

    public SelectionTransformService(
        IDefaultLlmProviderResolver defaultProvider,
        ILlmStreamingClient client)
    {
        this.defaultProvider = defaultProvider
            ?? throw new ArgumentNullException(nameof(defaultProvider));
        this.client = client ?? throw new ArgumentNullException(nameof(client));
    }

    public async IAsyncEnumerable<SelectionTransformEvent> TransformAsync(
        SelectionTransformRequest request,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        var machine = new SelectionTransformStateMachine(request.Generation);
        yield return machine.Start();

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
            var cancelled = machine.Cancel(request.Generation);
            if (cancelled is not null)
            {
                yield return cancelled;
            }
            yield break;
        }
        if (resolverFailed)
        {
            yield return machine.Fail(request.Generation, "The default LLM provider is unavailable.")!;
            yield break;
        }

        if (configuredProvider is null)
        {
            yield return machine.Fail(request.Generation, "Configure a default LLM provider in Models > LLM.")!;
            yield break;
        }

        var provider = new LlmProviderClientConfiguration(
            configuredProvider.ProviderId,
            configuredProvider.BaseUri,
            configuredProvider.Model,
            configuredProvider.ApiKey,
            FixedTemperature,
            configuredProvider.Timeout);
        var prompt = TextTransformPromptCatalog.For(request.Operation);
        var completionRequest = new LlmCompletionRequest(
        [
            new LlmChatMessage(LlmMessageRole.System, prompt.SystemPrompt),
            new LlmChatMessage(LlmMessageRole.User, request.Text),
        ]);

        await using var enumerator = client.StreamAsync(provider, completionRequest, cancellationToken)
            .GetAsyncEnumerator(cancellationToken);
        var receivedFinal = false;
        while (true)
        {
            LlmStreamUpdate? update = null;
            var hasNext = false;
            var cancelled = false;
            var failed = false;
            try
            {
                hasNext = await enumerator.MoveNextAsync().ConfigureAwait(false);
                update = hasNext ? enumerator.Current : null;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                cancelled = true;
            }
            catch
            {
                failed = true;
            }

            if (cancelled)
            {
                var cancelledEvent = machine.Cancel(request.Generation);
                if (cancelledEvent is not null)
                {
                    yield return cancelledEvent;
                }
                yield break;
            }
            if (failed)
            {
                var failedEvent = machine.Fail(request.Generation, "The LLM provider request failed.");
                if (failedEvent is not null)
                {
                    yield return failedEvent;
                }
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

            var partial = machine.ApplySnapshot(request.Generation, update!.AccumulatedText);
            if (partial is not null)
            {
                yield return partial;
            }
            if (update.IsFinal)
            {
                receivedFinal = true;
                var completed = machine.Complete(request.Generation, update.AccumulatedText);
                if (completed is not null)
                {
                    yield return completed;
                }
            }
        }

        if (!receivedFinal)
        {
            if (string.IsNullOrWhiteSpace(machine.LatestText))
            {
                var failedEvent = machine.Fail(
                    request.Generation,
                    "The LLM provider returned no result.");
                if (failedEvent is not null)
                {
                    yield return failedEvent;
                }
                yield break;
            }
            var completed = machine.Complete(request.Generation, machine.LatestText);
            if (completed is not null)
            {
                yield return completed;
            }
        }
    }
}
