using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionExportServiceTests
{
    [Theory]
    [InlineData(FileTranscriptionExportFormat.Text, "recording--.mp4.txt", "original text")]
    [InlineData(FileTranscriptionExportFormat.Markdown, "recording--.mp4.md", "# recording<>.mp4\n\noriginal text")]
    [InlineData(FileTranscriptionExportFormat.TranslatedText, "recording--.mp4.translated.txt", "译文")]
    [InlineData(FileTranscriptionExportFormat.TranslatedMarkdown, "recording--.mp4.translated.md", "# recording<>.mp4\n\n译文")]
    [InlineData(FileTranscriptionExportFormat.BilingualMarkdown, "recording--.mp4.bilingual.md", "## 原文\n\noriginal text\n\n## 译文\n\n译文")]
    public async Task Builds_text_exports_with_sanitized_windows_file_names(
        FileTranscriptionExportFormat format,
        string expectedName,
        string expectedContentFragment)
    {
        var destination = new CapturingDestination();
        var service = new FileTranscriptionExportService(
            new EmptySegmentRepository(),
            destination,
            new FileTranscriptionExportLabels("原文", "译文"));

        var result = await service.ExportAsync(
            Job(displayName: "recording<>.mp4"),
            format,
            CancellationToken.None);

        Assert.Equal(FileTranscriptionExportResult.Saved, result);
        Assert.Equal(expectedName, destination.Document!.SuggestedFileName);
        Assert.Contains(expectedContentFragment, destination.Document.Content, StringComparison.Ordinal);
        Assert.DoesNotContain('<', destination.Document.SuggestedFileName);
        Assert.DoesNotContain('>', destination.Document.SuggestedFileName);
    }

    [Theory]
    [InlineData(FileTranscriptionExportFormat.TranslatedText)]
    [InlineData(FileTranscriptionExportFormat.TranslatedMarkdown)]
    [InlineData(FileTranscriptionExportFormat.BilingualMarkdown)]
    public async Task Translation_exports_require_a_persisted_translation(
        FileTranscriptionExportFormat format)
    {
        var service = new FileTranscriptionExportService(
            new EmptySegmentRepository(),
            new CapturingDestination(),
            new FileTranscriptionExportLabels("Original", "Translation"));

        var exception = await Assert.ThrowsAsync<FileTranscriptionExportException>(async () =>
            await service.ExportAsync(
                Job(translatedText: null),
                format,
                CancellationToken.None));

        Assert.Equal(FileTranscriptionExportError.TranslationUnavailable, exception.Error);
    }

    [Fact]
    public async Task Srt_is_rebuilt_from_persisted_completed_segments_and_skips_failures()
    {
        var repository = new InMemorySegmentRepository(
        [
            new FileTranscriptionSegment(
                "job-1", 1, 28_500, 58_500, FileTranscriptionSegmentStatus.Failed,
                AsrProviderId.Qwen,
                retryCount: 2,
                errorCode: FileTranscriptionErrorCode.ProviderFailure),
            new FileTranscriptionSegment(
                "job-1", 0, 0, 30_000, FileTranscriptionSegmentStatus.Completed,
                AsrProviderId.Qwen,
                "first"),
            new FileTranscriptionSegment(
                "job-1", 2, 57_000, 60_123, FileTranscriptionSegmentStatus.Completed,
                AsrProviderId.Qwen,
                "last"),
        ]);
        var destination = new CapturingDestination();
        var service = new FileTranscriptionExportService(
            repository,
            destination,
            new FileTranscriptionExportLabels("Original", "Translation"));

        await service.ExportAsync(Job(), FileTranscriptionExportFormat.Srt, CancellationToken.None);

        Assert.Equal(
            "1\r\n00:00:00,000 --> 00:00:30,000\r\nfirst\r\n\r\n" +
            "2\r\n00:00:57,000 --> 00:01:00,123\r\nlast",
            destination.Document!.Content);
        Assert.Equal("recording.wav.srt", destination.Document.SuggestedFileName);
    }

    private static FileTranscriptionJob Job(
        string displayName = "recording.wav",
        string? translatedText = "译文") => new(
            "job-1",
            @"C:\Recordings\recording.wav",
            displayName,
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1,
            status: FileTranscriptionJobStatus.Completed,
            progress: 1,
            finalText: "original text",
            translationStatus: translatedText is null
                ? FileTranscriptionTranslationStatus.NotRequested
                : FileTranscriptionTranslationStatus.Completed,
            translatedText: translatedText,
            translationTargetLanguage: translatedText is null ? null : "zh-Hans");

    private sealed class CapturingDestination : IFileTranscriptionExportDestination
    {
        public FileTranscriptionExportDocument? Document { get; private set; }

        public ValueTask<FileTranscriptionExportResult> SaveAsync(
            FileTranscriptionExportDocument document,
            CancellationToken cancellationToken)
        {
            Document = document;
            return ValueTask.FromResult(FileTranscriptionExportResult.Saved);
        }
    }

    private sealed class EmptySegmentRepository : IFileTranscriptionSegmentRepository
    {
        public void Upsert(FileTranscriptionSegment segment) => throw new NotSupportedException();
        public IReadOnlyList<FileTranscriptionSegment> ListByJob(string jobId) => [];
        public int DeleteByJob(string jobId) => throw new NotSupportedException();
        public int MarkRunningAsInterrupted() => throw new NotSupportedException();
    }

    private sealed class InMemorySegmentRepository(IReadOnlyList<FileTranscriptionSegment> segments)
        : IFileTranscriptionSegmentRepository
    {
        public void Upsert(FileTranscriptionSegment segment) => throw new NotSupportedException();
        public IReadOnlyList<FileTranscriptionSegment> ListByJob(string jobId) =>
            segments.Where(segment => segment.JobId == jobId).OrderBy(segment => segment.Index).ToArray();
        public int DeleteByJob(string jobId) => throw new NotSupportedException();
        public int MarkRunningAsInterrupted() => throw new NotSupportedException();
    }
}
