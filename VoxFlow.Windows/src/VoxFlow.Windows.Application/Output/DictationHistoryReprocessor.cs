using VoxFlow.Windows.Application.Dictation;

namespace VoxFlow.Windows.Application.Output;

/// <summary>Runs an existing history row through the same text-processing
/// pipeline used by live dictation.</summary>
public sealed class DictationHistoryReprocessor : IHistoryReprocessor
{
    private readonly IDictationTextPostProcessor processor;

    public DictationHistoryReprocessor(IDictationTextPostProcessor processor)
    {
        this.processor = processor ?? throw new ArgumentNullException(nameof(processor));
    }

    public ValueTask<string> ReprocessAsync(
        string rawText,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(rawText);
        return processor.ProcessAsync(
            rawText,
            NullProgress<string>.Instance,
            cancellationToken);
    }

    private sealed class NullProgress<T> : IProgress<T>
    {
        public static NullProgress<T> Instance { get; } = new();

        public void Report(T value)
        {
        }
    }
}
