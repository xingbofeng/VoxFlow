using VoxFlow.Windows.Application.Dictation;

namespace VoxFlow.Windows.Application.Text;

public sealed class ConfigurableTextProcessingPipeline : IDictationTextPostProcessor
{
    private readonly ITextProcessingSettingsStore settingsStore;
    private readonly IDictationTextPostProcessor llmProcessor;
    private readonly IGlossaryStore? glossaryStore;
    private readonly Func<bool> codingContextProvider;

    public ConfigurableTextProcessingPipeline(
        ITextProcessingSettingsStore settingsStore,
        IDictationTextPostProcessor llmProcessor,
        IGlossaryStore? glossaryStore = null,
        Func<bool>? codingContextProvider = null)
    {
        this.settingsStore = settingsStore
            ?? throw new ArgumentNullException(nameof(settingsStore));
        this.llmProcessor = llmProcessor
            ?? throw new ArgumentNullException(nameof(llmProcessor));
        this.glossaryStore = glossaryStore;
        this.codingContextProvider = codingContextProvider ?? (() => false);
    }

    public async ValueTask<string> ProcessAsync(
        string text,
        IProgress<string> streamingProgress,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(streamingProgress);
        var settings = await settingsStore.LoadAsync(cancellationToken)
            .ConfigureAwait(false);
        if (!settings.Enabled)
        {
            return text;
        }

        var isCodingContext = codingContextProvider();
        var preSettings = settings with
        {
            PunctuationOptimization = false,
            LongSentenceBreaking = false,
            CjkLatinSpacing = false,
            AutoCapitalization = false,
        };
        var preprocessed = DeterministicTextProcessor.Process(
            text,
            preSettings,
            isCodingContext);
        string refined;
        try
        {
            refined = await llmProcessor.ProcessAsync(
                    preprocessed,
                    streamingProgress,
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            refined = preprocessed;
        }

        if (string.IsNullOrWhiteSpace(refined))
        {
            refined = preprocessed;
        }

        if (glossaryStore is not null)
        {
            var glossary = await glossaryStore.LoadAsync(cancellationToken)
                .ConfigureAwait(false);
            refined = GlossaryTextProcessor.Apply(refined, glossary);
        }

        var postSettings = settings with
        {
            SmartNumberRecognition = false,
            FillerWordFiltering = false,
        };
        var final = DeterministicTextProcessor.Process(
            refined,
            postSettings,
            isCodingContext);
        ReportSafely(streamingProgress, final);
        return final;
    }

    private static void ReportSafely(IProgress<string> progress, string value)
    {
        try
        {
            progress.Report(value);
        }
        catch
        {
            // Presentation progress does not own the output transaction.
        }
    }
}
