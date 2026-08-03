using VoxFlow.Windows.Application.Dictation;

namespace VoxFlow.Windows.Application.Llm;

public enum LlmRefinerAvailability
{
    NotConfigured,
    Disabled,
    Ready,
}

public interface IStreamingTextRefiner
{
    ValueTask<LlmRefinerAvailability> GetAvailabilityAsync(
        CancellationToken cancellationToken);

    IAsyncEnumerable<string> RefineAsync(
        string text,
        CancellationToken cancellationToken);
}

/// <summary>
/// Commits only a completed LLM stream. Provider, transport, parsing, or empty
/// response failures return the authoritative ASR final unchanged; cancellation
/// remains cancellation so no streamed preview can become output text.
/// </summary>
public sealed class ConservativeLlmTextPostProcessor : IDictationTextPostProcessor
{
    private readonly IStreamingTextRefiner refiner;

    public ConservativeLlmTextPostProcessor(IStreamingTextRefiner refiner)
    {
        this.refiner = refiner ?? throw new ArgumentNullException(nameof(refiner));
    }

    public async ValueTask<string> ProcessAsync(
        string text,
        IProgress<string> streamingProgress,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(streamingProgress);
        try
        {
            var availability = await refiner.GetAvailabilityAsync(cancellationToken)
                .ConfigureAwait(false);
            if (availability != LlmRefinerAvailability.Ready)
            {
                return text;
            }

            string? final = null;
            await foreach (var snapshot in refiner
                .RefineAsync(text, cancellationToken)
                .WithCancellation(cancellationToken)
                .ConfigureAwait(false))
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (string.IsNullOrWhiteSpace(snapshot))
                {
                    continue;
                }

                final = snapshot;
                ReportSafely(streamingProgress, snapshot);
            }

            if (!string.IsNullOrWhiteSpace(final))
            {
                return final;
            }

            ReportSafely(streamingProgress, text);
            return text;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            ReportSafely(streamingProgress, text);
            return text;
        }
    }

    private static void ReportSafely(IProgress<string> progress, string value)
    {
        try
        {
            progress.Report(value);
        }
        catch
        {
            // Presentation progress cannot turn a successful/fallback processing
            // result into a failed dictation.
        }
    }
}
