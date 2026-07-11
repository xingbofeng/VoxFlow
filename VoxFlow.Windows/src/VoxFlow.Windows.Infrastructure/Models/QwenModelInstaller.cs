using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Models;

public interface IVolumeIdentity
{
    string GetIdentity(string path);
}

public sealed class PathRootVolumeIdentity : IVolumeIdentity
{
    public string GetIdentity(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        return Path.GetPathRoot(Path.GetFullPath(path))
            ?? throw new InvalidOperationException("The model path has no volume identity.");
    }
}

public sealed record QwenModelInstallResult(
    ModelInstallPhase Phase,
    string? InstallPath,
    string? ErrorCode);

public sealed class QwenModelInstaller
{
    private readonly QwenModelIntegrityVerifier integrityVerifier;
    private readonly IVolumeIdentity volumeIdentity;

    public QwenModelInstaller(
        QwenModelIntegrityVerifier integrityVerifier,
        IVolumeIdentity? volumeIdentity = null)
    {
        this.integrityVerifier = integrityVerifier
            ?? throw new ArgumentNullException(nameof(integrityVerifier));
        this.volumeIdentity = volumeIdentity ?? new PathRootVolumeIdentity();
    }

    public async Task<QwenModelInstallResult> InstallAsync(
        QwenModelManifest manifest,
        string stagingDirectory,
        string installDirectory,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        ArgumentException.ThrowIfNullOrWhiteSpace(stagingDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(installDirectory);
        var fullStagingDirectory = Path.GetFullPath(stagingDirectory);
        var payloadDirectory = Path.Combine(fullStagingDirectory, "payload");
        var fullInstallDirectory = Path.GetFullPath(installDirectory);

        var integrity = await integrityVerifier.VerifyAsync(
            manifest,
            payloadDirectory,
            cancellationToken).ConfigureAwait(false);
        if (!integrity.IsValid)
        {
            return new QwenModelInstallResult(
                ModelInstallPhase.Corrupted,
                null,
                integrity.ErrorCode);
        }

        var stagingVolume = volumeIdentity.GetIdentity(payloadDirectory);
        var installVolume = volumeIdentity.GetIdentity(fullInstallDirectory);
        if (!string.Equals(stagingVolume, installVolume, StringComparison.OrdinalIgnoreCase))
        {
            return new QwenModelInstallResult(
                ModelInstallPhase.Failed,
                null,
                "same_volume_required");
        }

        if (Directory.Exists(fullInstallDirectory) || File.Exists(fullInstallDirectory))
        {
            return new QwenModelInstallResult(
                ModelInstallPhase.Failed,
                null,
                "install_destination_exists");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(fullInstallDirectory)!);
        Directory.Move(payloadDirectory, fullInstallDirectory);
        if (Directory.Exists(fullStagingDirectory))
        {
            Directory.Delete(fullStagingDirectory, recursive: true);
        }

        return new QwenModelInstallResult(
            ModelInstallPhase.Installing,
            fullInstallDirectory,
            null);
    }
}
