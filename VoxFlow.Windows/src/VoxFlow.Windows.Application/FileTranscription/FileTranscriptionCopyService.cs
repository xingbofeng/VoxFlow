using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public enum FileTranscriptionCopyResult
{
    Succeeded,
    ResultUnavailable,
    ClipboardFailure,
}

public sealed class FileTranscriptionCopyService(ITextClipboardWriter clipboard)
{
    private readonly ITextClipboardWriter clipboard = clipboard
        ?? throw new ArgumentNullException(nameof(clipboard));

    public FileTranscriptionCopyResult Copy(FileTranscriptionJob job)
    {
        ArgumentNullException.ThrowIfNull(job);
        if (job.Status is not (FileTranscriptionJobStatus.Completed
            or FileTranscriptionJobStatus.PartiallyFailed)
            || string.IsNullOrWhiteSpace(job.FinalText))
        {
            return FileTranscriptionCopyResult.ResultUnavailable;
        }

        try
        {
            clipboard.WriteText(job.FinalText);
            return FileTranscriptionCopyResult.Succeeded;
        }
        catch
        {
            return FileTranscriptionCopyResult.ClipboardFailure;
        }
    }
}
