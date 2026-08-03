using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Platform.Files;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class FileTranscriptionExportDestinationTests
{
    [Fact]
    public async Task Writes_utf8_content_to_the_path_chosen_by_the_windows_save_adapter()
    {
        using var directory = new TemporaryDirectory();
        var path = Path.Combine(directory.Path, "result.md");
        var destination = new WindowsFileTranscriptionExportDestination(
            new FixedPathSelector(path));
        var document = new FileTranscriptionExportDocument(
            "suggested.md",
            "中文 result",
            "md");

        var result = await destination.SaveAsync(document, CancellationToken.None);

        Assert.Equal(FileTranscriptionExportResult.Saved, result);
        Assert.Equal("中文 result", await File.ReadAllTextAsync(path));
    }

    [Fact]
    public async Task Cancelled_save_dialog_does_not_write_a_file()
    {
        var destination = new WindowsFileTranscriptionExportDestination(
            new FixedPathSelector(null));

        var result = await destination.SaveAsync(
            new FileTranscriptionExportDocument("result.txt", "text", "txt"),
            CancellationToken.None);

        Assert.Equal(FileTranscriptionExportResult.Cancelled, result);
    }

    private sealed class FixedPathSelector(string? path)
        : IFileTranscriptionSavePathSelector
    {
        public string? SelectPath(FileTranscriptionExportDocument document) => path;
    }
}
