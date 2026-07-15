namespace VoxFlow.Windows.Application.Output;

public interface ITextClipboardWriter
{
    void WriteText(string text);
}

public interface IHistoryReprocessor
{
    ValueTask<string> ReprocessAsync(
        string rawText,
        CancellationToken cancellationToken);
}
