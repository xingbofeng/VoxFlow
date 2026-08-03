using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class FileTranscriptionSourceGuardTests
{
    [Theory]
    [InlineData(FileSourceAvailability.Missing)]
    [InlineData(FileSourceAvailability.AccessDenied)]
    public async Task Unavailable_source_returns_a_safe_error_without_mutating_existing_results(
        FileSourceAvailability availability)
    {
        var job = new FileTranscriptionJob(
            "job-1",
            @"C:\\Recordings\\moved.wav",
            "moved.wav",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1,
            status: FileTranscriptionJobStatus.PartiallyFailed,
            progress: 0.5,
            rawText: "existing raw text",
            finalText: "existing final text",
            segmentCount: 2,
            segmentCompleted: 1);
        var guard = new FileTranscriptionSourceGuard(new FakeSourceProbe(availability));

        var result = await guard.CheckAsync(job, CancellationToken.None);

        Assert.False(result.IsAvailable);
        Assert.Equal(FileTranscriptionErrorCode.SourceUnavailable, result.ErrorCode);
        Assert.Same(job, result.Job);
        Assert.Equal("existing final text", result.Job.FinalText);
        Assert.Equal(1, result.Job.SegmentCompleted);
    }

    [Fact]
    public async Task Available_source_allows_the_existing_job_to_continue()
    {
        var job = new FileTranscriptionJob(
            "job-1",
            @"C:\\Recordings\\meeting.wav",
            "meeting.wav",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1);
        var guard = new FileTranscriptionSourceGuard(
            new FakeSourceProbe(FileSourceAvailability.Available));

        var result = await guard.CheckAsync(job, CancellationToken.None);

        Assert.True(result.IsAvailable);
        Assert.Null(result.ErrorCode);
    }

    private sealed class FakeSourceProbe(FileSourceAvailability availability)
        : IFileSourceAvailabilityProbe
    {
        public ValueTask<FileSourceAvailability> InspectAsync(
            string sourcePath,
            CancellationToken cancellationToken) => ValueTask.FromResult(availability);
    }
}
