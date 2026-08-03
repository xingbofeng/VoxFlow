using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests.Models;

public sealed class QwenModelDownloadPreflightTests
{
    private static readonly QwenModelManifest Manifest = new(
        "qwen3-asr-0.6b",
        "Qwen 0.6B",
        QwenVariant.Qwen06B,
        "model-revision",
        "runtime-revision",
        1_000,
        [new QwenModelFile("model.bin", new Uri("https://models.invalid/model.bin"), 1_000, new string('a', 64))],
        new QwenRuntimePublicationGate(true, null));

    [Fact]
    public void Download_does_not_start_without_an_explicit_user_action()
    {
        var result = QwenModelDownloadPreflight.Evaluate(
            Manifest,
            userInitiated: false,
            availableBytes: long.MaxValue);

        Assert.False(result.CanStart);
        Assert.Equal(ModelInstallPhase.NotDownloaded, result.Phase);
        Assert.Equal("manual_download_required", result.ErrorCode);
    }

    [Fact]
    public void Space_preflight_blocks_transfer_and_reports_required_capacity()
    {
        var requiredBytes = QwenModelDownloadPreflight.RequiredFreeBytes(Manifest);

        var result = QwenModelDownloadPreflight.Evaluate(
            Manifest,
            userInitiated: true,
            availableBytes: requiredBytes - 1);

        Assert.False(result.CanStart);
        Assert.Equal(ModelInstallPhase.InsufficientSpace, result.Phase);
        Assert.Equal(requiredBytes, result.RequiredBytes);
        Assert.Equal("insufficient_space", result.ErrorCode);
    }

    [Fact]
    public void Explicit_download_with_capacity_enters_the_queue()
    {
        var requiredBytes = QwenModelDownloadPreflight.RequiredFreeBytes(Manifest);

        var result = QwenModelDownloadPreflight.Evaluate(
            Manifest,
            userInitiated: true,
            availableBytes: requiredBytes);

        Assert.True(result.CanStart);
        Assert.Equal(ModelInstallPhase.Queued, result.Phase);
        Assert.Null(result.ErrorCode);
    }
}
