using VoxFlow.Windows.App.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class FileTranscriptionPresentationTests
{
    [Theory]
    [InlineData(FileTranscriptionJobStatus.Queued, true, false, false, false)]
    [InlineData(FileTranscriptionJobStatus.Running, false, true, false, false)]
    [InlineData(FileTranscriptionJobStatus.Interrupted, false, false, true, true)]
    [InlineData(FileTranscriptionJobStatus.PartiallyFailed, false, false, true, true)]
    [InlineData(FileTranscriptionJobStatus.Completed, false, false, false, false)]
    [InlineData(FileTranscriptionJobStatus.Failed, false, false, false, true)]
    public void Job_card_exposes_macos_equivalent_status_and_actions(
        FileTranscriptionJobStatus status,
        bool canStart,
        bool canCancel,
        bool canContinue,
        bool canRetry)
    {
        var item = new FileTranscriptionJobPresentation(Job(status), []);

        Assert.False(string.IsNullOrWhiteSpace(item.StatusIcon));
        Assert.False(string.IsNullOrWhiteSpace(item.StatusTitle));
        Assert.Equal(canStart, item.CanStart);
        Assert.Equal(canCancel, item.CanCancel);
        Assert.Equal(canContinue, item.CanContinue);
        Assert.Equal(canRetry, item.CanRetry);
        Assert.True(item.CanDelete);
        Assert.Equal(
            status is FileTranscriptionJobStatus.Completed or FileTranscriptionJobStatus.PartiallyFailed,
            item.CanUseResult);
    }

    [Fact]
    public void Detail_projection_exposes_progress_result_translation_and_safe_segment_diagnostics()
    {
        var job = Job(FileTranscriptionJobStatus.PartiallyFailed);
        var segments = new[]
        {
            new FileTranscriptionSegment(
                "job-1", 0, 0, 30_000, FileTranscriptionSegmentStatus.Completed,
                AsrProviderId.Volcengine, "text"),
            new FileTranscriptionSegment(
                "job-1", 1, 28_500, 58_500, FileTranscriptionSegmentStatus.Failed,
                AsrProviderId.Volcengine,
                retryCount: 2,
                fallbackReason: SegmentFallbackReason.RetryAfterProviderError,
                errorCode: FileTranscriptionErrorCode.ProviderNetworkFailure),
        };

        var item = new FileTranscriptionJobPresentation(job, segments);

        Assert.Equal(50, item.ProgressPercent);
        Assert.Equal("final text", item.FinalText);
        Assert.Equal("translated text", item.TranslatedText);
        Assert.True(item.HasTranslation);
        Assert.Equal(2, item.Diagnostics.Count);
        Assert.All(item.Diagnostics, diagnostic =>
        {
            Assert.DoesNotContain("C:\\", diagnostic.Summary, StringComparison.Ordinal);
            Assert.DoesNotContain("key", diagnostic.Summary, StringComparison.OrdinalIgnoreCase);
        });
        Assert.Contains("2", item.MetadataLine, StringComparison.Ordinal);
    }

    private static FileTranscriptionJob Job(FileTranscriptionJobStatus status) => new(
        "job-1",
        @"C:\Recordings\meeting.mp4",
        "meeting.mp4",
        AsrProviderId.Volcengine,
        RecognitionLanguage.English,
        1,
        status: status,
        durationMs: 60_000,
        progress: status == FileTranscriptionJobStatus.PartiallyFailed ? 0.5 : 0,
        finalText: status is FileTranscriptionJobStatus.Completed
            or FileTranscriptionJobStatus.PartiallyFailed
            ? "final text"
            : null,
        errorCode: status == FileTranscriptionJobStatus.Failed
            ? FileTranscriptionErrorCode.ProviderFailure
            : null,
        segmentCount: 2,
        segmentCompleted: 1,
        translationStatus: status == FileTranscriptionJobStatus.PartiallyFailed
            ? FileTranscriptionTranslationStatus.Completed
            : FileTranscriptionTranslationStatus.NotRequested,
        translatedText: status == FileTranscriptionJobStatus.PartiallyFailed
            ? "translated text"
            : null,
        translationTargetLanguage: status == FileTranscriptionJobStatus.PartiallyFailed
            ? "zh-Hans"
            : null);
}
