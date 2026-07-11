using System.Text;
using VoxFlow.Windows.Application.FileTranscription;

namespace VoxFlow.Windows.Platform.Files;

public interface IFileTranscriptionSavePathSelector
{
    string? SelectPath(FileTranscriptionExportDocument document);
}

public sealed class WindowsFileTranscriptionSavePathSelector
    : IFileTranscriptionSavePathSelector
{
    public string? SelectPath(FileTranscriptionExportDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);
        using var dialog = new System.Windows.Forms.SaveFileDialog
        {
            AddExtension = true,
            CheckPathExists = true,
            DefaultExt = document.Extension,
            FileName = document.SuggestedFileName,
            Filter = $"{document.Extension.ToUpperInvariant()} (*.{document.Extension})|*.{document.Extension}",
            OverwritePrompt = true,
            RestoreDirectory = true,
        };
        return dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK
            ? dialog.FileName
            : null;
    }
}

public sealed class WindowsFileTranscriptionExportDestination
    : IFileTranscriptionExportDestination
{
    private static readonly UTF8Encoding Utf8WithoutByteOrderMark = new(false);
    private readonly IFileTranscriptionSavePathSelector pathSelector;

    public WindowsFileTranscriptionExportDestination(
        IFileTranscriptionSavePathSelector? pathSelector = null)
    {
        this.pathSelector = pathSelector
            ?? new WindowsFileTranscriptionSavePathSelector();
    }

    public async ValueTask<FileTranscriptionExportResult> SaveAsync(
        FileTranscriptionExportDocument document,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(document);
        cancellationToken.ThrowIfCancellationRequested();
        var path = pathSelector.SelectPath(document);
        if (string.IsNullOrWhiteSpace(path))
        {
            return FileTranscriptionExportResult.Cancelled;
        }

        await File.WriteAllTextAsync(
            path,
            document.Content,
            Utf8WithoutByteOrderMark,
            cancellationToken).ConfigureAwait(false);
        return FileTranscriptionExportResult.Saved;
    }
}
