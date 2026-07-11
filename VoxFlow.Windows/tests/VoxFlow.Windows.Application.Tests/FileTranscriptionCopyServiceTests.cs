using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Application.Output;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionCopyServiceTests
{
    [Theory]
    [InlineData(FileTranscriptionJobStatus.Completed)]
    [InlineData(FileTranscriptionJobStatus.PartiallyFailed)]
    public void Copies_final_text_for_completed_and_partially_failed_jobs(
        FileTranscriptionJobStatus status)
    {
        var clipboard = new CapturingClipboard();
        var service = new FileTranscriptionCopyService(clipboard);

        var result = service.Copy(Job(status, "final text"));

        Assert.Equal(FileTranscriptionCopyResult.Succeeded, result);
        Assert.Equal("final text", clipboard.Text);
    }

    [Theory]
    [InlineData(FileTranscriptionJobStatus.Queued)]
    [InlineData(FileTranscriptionJobStatus.Running)]
    [InlineData(FileTranscriptionJobStatus.Failed)]
    [InlineData(FileTranscriptionJobStatus.Cancelled)]
    public void Copy_is_unavailable_without_a_terminal_successful_result(
        FileTranscriptionJobStatus status)
    {
        var clipboard = new CapturingClipboard();
        var service = new FileTranscriptionCopyService(clipboard);

        Assert.Equal(
            FileTranscriptionCopyResult.ResultUnavailable,
            service.Copy(Job(status, finalText: null)));
        Assert.Null(clipboard.Text);
    }

    [Fact]
    public void Clipboard_failure_returns_feedback_without_throwing()
    {
        var service = new FileTranscriptionCopyService(new ThrowingClipboard());

        var result = service.Copy(Job(FileTranscriptionJobStatus.Completed, "text"));

        Assert.Equal(FileTranscriptionCopyResult.ClipboardFailure, result);
    }

    private static FileTranscriptionJob Job(
        FileTranscriptionJobStatus status,
        string? finalText) => new(
            "job-1",
            @"C:\Recordings\meeting.wav",
            "meeting.wav",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1,
            status: status,
            finalText: finalText,
            errorCode: status == FileTranscriptionJobStatus.Failed
                ? FileTranscriptionErrorCode.ProviderFailure
                : null);

    private sealed class CapturingClipboard : ITextClipboardWriter
    {
        public string? Text { get; private set; }
        public void WriteText(string text) => Text = text;
    }

    private sealed class ThrowingClipboard : ITextClipboardWriter
    {
        public void WriteText(string text) => throw new InvalidOperationException("clipboard busy");
    }
}
