namespace VoxFlow.Windows.Application.Text;

public sealed record DeterministicTextProcessingSettings
{
    public const int CurrentSchemaVersion = 1;
    private const int MaximumThreshold = 1000;
    private int longSentenceWordThreshold;
    private int longSentenceCjkThreshold;
    private int punctuationCjkThreshold;
    private int punctuationWordThreshold;

    public DeterministicTextProcessingSettings(
        bool Enabled = true,
        bool SmartNumberRecognition = true,
        bool PunctuationOptimization = true,
        bool LongSentenceBreaking = false,
        bool FillerWordFiltering = true,
        bool CjkLatinSpacing = true,
        bool AutoCapitalization = true,
        int LongSentenceWordThreshold = 8,
        int LongSentenceCjkThreshold = 12,
        int PunctuationCjkThreshold = 3,
        int PunctuationWordThreshold = 4,
        int SchemaVersion = CurrentSchemaVersion)
    {
        if (SchemaVersion <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(SchemaVersion));
        }

        this.Enabled = Enabled;
        this.SmartNumberRecognition = SmartNumberRecognition;
        this.PunctuationOptimization = PunctuationOptimization;
        this.LongSentenceBreaking = LongSentenceBreaking;
        this.FillerWordFiltering = FillerWordFiltering;
        this.CjkLatinSpacing = CjkLatinSpacing;
        this.AutoCapitalization = AutoCapitalization;
        this.LongSentenceWordThreshold = LongSentenceWordThreshold;
        this.LongSentenceCjkThreshold = LongSentenceCjkThreshold;
        this.PunctuationCjkThreshold = PunctuationCjkThreshold;
        this.PunctuationWordThreshold = PunctuationWordThreshold;
        this.SchemaVersion = SchemaVersion;
    }

    public static DeterministicTextProcessingSettings Default { get; } = new();

    public bool Enabled { get; init; }

    public bool SmartNumberRecognition { get; init; }

    public bool PunctuationOptimization { get; init; }

    public bool LongSentenceBreaking { get; init; }

    public bool FillerWordFiltering { get; init; }

    public bool CjkLatinSpacing { get; init; }

    public bool AutoCapitalization { get; init; }

    public int LongSentenceWordThreshold
    {
        get => longSentenceWordThreshold;
        init => longSentenceWordThreshold = ValidateThreshold(
            value,
            nameof(LongSentenceWordThreshold));
    }

    public int LongSentenceCjkThreshold
    {
        get => longSentenceCjkThreshold;
        init => longSentenceCjkThreshold = ValidateThreshold(
            value,
            nameof(LongSentenceCjkThreshold));
    }

    public int PunctuationCjkThreshold
    {
        get => punctuationCjkThreshold;
        init => punctuationCjkThreshold = ValidateThreshold(
            value,
            nameof(PunctuationCjkThreshold));
    }

    public int PunctuationWordThreshold
    {
        get => punctuationWordThreshold;
        init => punctuationWordThreshold = ValidateThreshold(
            value,
            nameof(PunctuationWordThreshold));
    }

    public int SchemaVersion { get; init; }

    private static int ValidateThreshold(int value, string parameterName)
    {
        if (value is < 1 or > MaximumThreshold)
        {
            throw new ArgumentOutOfRangeException(parameterName);
        }

        return value;
    }
}

public interface ITextProcessingSettingsStore
{
    ValueTask<DeterministicTextProcessingSettings> LoadAsync(
        CancellationToken cancellationToken);

    ValueTask SaveAsync(
        DeterministicTextProcessingSettings settings,
        CancellationToken cancellationToken);
}
