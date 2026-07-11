using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class FileTranscriptionDomainTests
{
    [Fact]
    public void File_job_preserves_the_provider_and_language_selected_when_enqueued()
    {
        var job = new FileTranscriptionJob(
            id: "job-1",
            sourcePath: @"C:\\Recordings\\meeting.mp4",
            displayName: "meeting.mp4",
            provider: AsrProviderId.TencentCloud,
            language: RecognitionLanguage.ChineseMandarin,
            createdAtUnixMs: 1_700_000_000_000);

        Assert.Equal(FileTranscriptionJobStatus.Queued, job.Status);
        Assert.Equal(AsrProviderId.TencentCloud, job.Provider);
        Assert.Equal(RecognitionLanguage.ChineseMandarin, job.Language);
        Assert.Equal("meeting.mp4", job.DisplayName);
        Assert.Equal(@"C:\\Recordings\\meeting.mp4", job.SourcePath);
    }

    [Fact]
    public void Segment_requires_a_valid_non_negative_time_range()
    {
        var segment = new FileTranscriptionSegment(
            jobId: "job-1",
            index: 0,
            startMs: 0,
            endMs: 30_000,
            status: FileTranscriptionSegmentStatus.Pending,
            provider: AsrProviderId.TencentCloud);

        Assert.Equal(FileTranscriptionSegmentStatus.Pending, segment.Status);
        Assert.Equal(AsrProviderId.TencentCloud, segment.Provider);
        Assert.Throws<ArgumentOutOfRangeException>(() => new FileTranscriptionSegment(
            "job-1", 0, -1, 30_000, FileTranscriptionSegmentStatus.Pending, AsrProviderId.Qwen));
        Assert.Throws<ArgumentOutOfRangeException>(() => new FileTranscriptionSegment(
            "job-1", 0, 30_000, 29_999, FileTranscriptionSegmentStatus.Pending, AsrProviderId.Qwen));
    }

    [Fact]
    public void Completed_and_failed_jobs_enforce_their_result_invariants()
    {
        Assert.Throws<ArgumentException>(() => new FileTranscriptionJob(
            "job-1",
            @"C:\\Recordings\\meeting.wav",
            "meeting.wav",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1,
            status: FileTranscriptionJobStatus.Completed));

        Assert.Throws<ArgumentException>(() => new FileTranscriptionJob(
            "job-1",
            @"C:\\Recordings\\meeting.wav",
            "meeting.wav",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1,
            status: FileTranscriptionJobStatus.Failed,
            errorCode: null));
    }

    [Fact]
    public void File_transcription_values_round_trip_with_stable_wire_names()
    {
        var job = new FileTranscriptionJob(
            "job-1",
            @"C:\\Recordings\\meeting.wav",
            "meeting.wav",
            AsrProviderId.AliyunDashScope,
            RecognitionLanguage.ChineseMandarin,
            1,
            status: FileTranscriptionJobStatus.Completed,
            progress: 1,
            rawText: "原始文本",
            finalText: "最终文本",
            translationStatus: FileTranscriptionTranslationStatus.Failed,
            translationErrorCode: FileTranscriptionErrorCode.TranslationFailure,
            translationUpdatedAtUnixMs: 2,
            updatedAtUnixMs: 2,
            completedAtUnixMs: 2);

        var json = JsonSerializer.Serialize(job, DomainJson.Options);
        var restored = JsonSerializer.Deserialize<FileTranscriptionJob>(json, DomainJson.Options);

        Assert.Equal(job, restored);
        Assert.Contains("\"status\":\"completed\"", json, StringComparison.Ordinal);
        Assert.Contains("\"translationStatus\":\"failed\"", json, StringComparison.Ordinal);
        Assert.Contains("\"provider\":\"aliyun_dashscope_asr\"", json, StringComparison.Ordinal);
    }

    [Fact]
    public void Invalid_enum_ranges_timestamps_and_translation_states_are_rejected()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new FileTranscriptionJob(
            "job-1",
            @"C:\\Recordings\\meeting.wav",
            "meeting.wav",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1,
            status: (FileTranscriptionJobStatus)999));
        Assert.Throws<ArgumentOutOfRangeException>(() => new FileTranscriptionJob(
            "job-1",
            @"C:\\Recordings\\meeting.wav",
            "meeting.wav",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1,
            updatedAtUnixMs: -1));
        Assert.Throws<ArgumentException>(() => new FileTranscriptionJob(
            "job-1",
            @"C:\\Recordings\\meeting.wav",
            "meeting.wav",
            AsrProviderId.Qwen,
            RecognitionLanguage.Automatic,
            1,
            translationStatus: FileTranscriptionTranslationStatus.Failed));
        Assert.Throws<ArgumentOutOfRangeException>(() => new FileTranscriptionSegment(
            "job-1", 0, 1, 1, FileTranscriptionSegmentStatus.Pending, AsrProviderId.Qwen));
    }

    [Fact]
    public void Windows_p3_exposes_only_the_existing_four_providers_and_segmented_pcm_mode()
    {
        Assert.Equal(
        [
            AsrProviderId.Qwen,
            AsrProviderId.TencentCloud,
            AsrProviderId.AliyunDashScope,
            AsrProviderId.Volcengine,
        ], Enum.GetValues<AsrProviderId>());
        Assert.Equal(
            [FileTranscriptionProviderMode.SegmentedPcm],
            Enum.GetValues<FileTranscriptionProviderMode>());
    }

    [Theory]
    [MemberData(nameof(FileTranscriptionWireNames))]
    public void File_transcription_enums_have_explicit_stable_wire_names(
        Enum value,
        string wireName)
    {
        Assert.Equal(
            $"\"{wireName}\"",
            JsonSerializer.Serialize(value, value.GetType(), DomainJson.Options));
    }

    public static TheoryData<Enum, string> FileTranscriptionWireNames => new()
    {
        { FileTranscriptionJobStatus.Queued, "queued" },
        { FileTranscriptionJobStatus.Running, "running" },
        { FileTranscriptionJobStatus.Interrupted, "interrupted" },
        { FileTranscriptionJobStatus.Completed, "completed" },
        { FileTranscriptionJobStatus.PartiallyFailed, "partiallyFailed" },
        { FileTranscriptionJobStatus.Cancelled, "cancelled" },
        { FileTranscriptionJobStatus.Failed, "failed" },
        { FileTranscriptionSegmentStatus.Pending, "pending" },
        { FileTranscriptionSegmentStatus.Running, "running" },
        { FileTranscriptionSegmentStatus.Completed, "completed" },
        { FileTranscriptionSegmentStatus.Failed, "failed" },
        { FileTranscriptionSegmentStatus.Interrupted, "interrupted" },
        { FileTranscriptionSegmentStatus.Cancelled, "cancelled" },
        { FileTranscriptionProviderMode.SegmentedPcm, "segmentedPcm" },
        { SegmentFallbackReason.None, "none" },
        { SegmentFallbackReason.RetryAfterEmptyResult, "retryAfterEmptyResult" },
        { SegmentFallbackReason.RetryAfterDuplicateResult, "retryAfterDuplicateResult" },
        { SegmentFallbackReason.RetryAfterProviderError, "retryAfterProviderError" },
        { FileTranscriptionTranslationStatus.NotRequested, "notRequested" },
        { FileTranscriptionTranslationStatus.Pending, "pending" },
        { FileTranscriptionTranslationStatus.Running, "running" },
        { FileTranscriptionTranslationStatus.Completed, "completed" },
        { FileTranscriptionTranslationStatus.Failed, "failed" },
        { FileTranscriptionExportFormat.Text, "text" },
        { FileTranscriptionExportFormat.Markdown, "markdown" },
        { FileTranscriptionExportFormat.Srt, "srt" },
        { FileTranscriptionExportFormat.TranslatedText, "translatedText" },
        { FileTranscriptionExportFormat.TranslatedMarkdown, "translatedMarkdown" },
        { FileTranscriptionExportFormat.BilingualMarkdown, "bilingualMarkdown" },
        { FileTranscriptionErrorCode.ProviderUnavailable, "providerUnavailable" },
        { FileTranscriptionErrorCode.ProviderAuthenticationFailed, "providerAuthenticationFailed" },
        { FileTranscriptionErrorCode.ProviderQuotaExceeded, "providerQuotaExceeded" },
        { FileTranscriptionErrorCode.ProviderAudioFormatInvalid, "providerAudioFormatInvalid" },
        { FileTranscriptionErrorCode.ProviderModelNotReady, "providerModelNotReady" },
        { FileTranscriptionErrorCode.ProviderNetworkFailure, "providerNetworkFailure" },
        { FileTranscriptionErrorCode.SegmentTimedOut, "segmentTimedOut" },
    };
}
