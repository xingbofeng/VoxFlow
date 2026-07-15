using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Models;

public sealed record ModelDownloadPreflightResult(
    bool CanStart,
    ModelInstallPhase Phase,
    long RequiredBytes,
    string? ErrorCode);

public static class QwenModelDownloadPreflight
{
    private const long MinimumStagingReserveBytes = 256L * 1024 * 1024;

    public static long RequiredFreeBytes(QwenModelManifest manifest)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        var reserve = Math.Max(
            MinimumStagingReserveBytes,
            checked((manifest.TotalBytes + 19) / 20));
        return checked(manifest.TotalBytes + reserve);
    }

    public static ModelDownloadPreflightResult Evaluate(
        QwenModelManifest manifest,
        bool userInitiated,
        long availableBytes)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        if (availableBytes < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(availableBytes));
        }

        var requiredBytes = RequiredFreeBytes(manifest);
        if (!userInitiated)
        {
            return new ModelDownloadPreflightResult(
                false,
                ModelInstallPhase.NotDownloaded,
                requiredBytes,
                "manual_download_required");
        }

        if (availableBytes < requiredBytes)
        {
            return new ModelDownloadPreflightResult(
                false,
                ModelInstallPhase.InsufficientSpace,
                requiredBytes,
                "insufficient_space");
        }

        return new ModelDownloadPreflightResult(
            true,
            ModelInstallPhase.Queued,
            requiredBytes,
            null);
    }
}
