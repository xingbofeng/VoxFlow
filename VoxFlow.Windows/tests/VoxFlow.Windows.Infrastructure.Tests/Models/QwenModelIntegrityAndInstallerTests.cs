using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Models;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Models;

public sealed class QwenModelIntegrityAndInstallerTests
{
    [Fact]
    public async Task Size_and_sha256_must_both_match_the_manifest()
    {
        using var directory = new TemporaryDirectory();
        var manifest = Manifest([1, 2, 3, 4]);
        var payloadRoot = Path.Combine(directory.Path, "payload");
        Directory.CreateDirectory(payloadRoot);
        await File.WriteAllBytesAsync(Path.Combine(payloadRoot, "model.bin"), [1, 2, 3, 4]);
        var verifier = new QwenModelIntegrityVerifier();

        var valid = await verifier.VerifyAsync(manifest, payloadRoot, CancellationToken.None);

        Assert.True(valid.IsValid);
        await File.WriteAllBytesAsync(Path.Combine(payloadRoot, "model.bin"), [1, 2, 3, 9]);
        var wrongHash = await verifier.VerifyAsync(manifest, payloadRoot, CancellationToken.None);
        Assert.False(wrongHash.IsValid);
        Assert.Equal("sha256_mismatch", wrongHash.ErrorCode);
        await File.WriteAllBytesAsync(Path.Combine(payloadRoot, "model.bin"), [1, 2, 3]);
        var wrongSize = await verifier.VerifyAsync(manifest, payloadRoot, CancellationToken.None);
        Assert.False(wrongSize.IsValid);
        Assert.Equal("size_mismatch", wrongSize.ErrorCode);
    }

    [Fact]
    public async Task Corrupt_staging_never_pollutes_an_existing_ready_revision()
    {
        using var directory = new TemporaryDirectory();
        var manifest = Manifest([1, 2, 3, 4]);
        var oldInstall = Path.Combine(directory.Path, "installed", "old-revision");
        Directory.CreateDirectory(oldInstall);
        await File.WriteAllTextAsync(Path.Combine(oldInstall, "sentinel.txt"), "ready");
        var staging = Path.Combine(directory.Path, "staging");
        Directory.CreateDirectory(Path.Combine(staging, "payload"));
        await File.WriteAllBytesAsync(Path.Combine(staging, "payload", "model.bin"), [9, 9, 9, 9]);
        var destination = Path.Combine(directory.Path, "installed", manifest.ModelRevision);
        var installer = new QwenModelInstaller(new QwenModelIntegrityVerifier());

        var result = await installer.InstallAsync(
            manifest,
            staging,
            destination,
            CancellationToken.None);

        Assert.Equal(ModelInstallPhase.Corrupted, result.Phase);
        Assert.Equal("sha256_mismatch", result.ErrorCode);
        Assert.Equal("ready", await File.ReadAllTextAsync(Path.Combine(oldInstall, "sentinel.txt")));
        Assert.False(Directory.Exists(destination));
        Assert.True(Directory.Exists(Path.Combine(staging, "payload")));
    }

    [Fact]
    public async Task Verified_payload_is_moved_as_one_directory_on_the_same_volume()
    {
        using var directory = new TemporaryDirectory();
        var manifest = Manifest([1, 2, 3, 4]);
        var staging = Path.Combine(directory.Path, ".staging", manifest.ModelRevision);
        Directory.CreateDirectory(Path.Combine(staging, "payload"));
        await File.WriteAllBytesAsync(Path.Combine(staging, "payload", "model.bin"), [1, 2, 3, 4]);
        await File.WriteAllTextAsync(Path.Combine(staging, ".download-state.json"), "{}");
        var destination = Path.Combine(directory.Path, "installed", manifest.ModelRevision);
        var installer = new QwenModelInstaller(new QwenModelIntegrityVerifier());

        var result = await installer.InstallAsync(
            manifest,
            staging,
            destination,
            CancellationToken.None);

        Assert.Equal(ModelInstallPhase.Installing, result.Phase);
        Assert.Equal(destination, result.InstallPath);
        Assert.Equal(new byte[] { 1, 2, 3, 4 }, await File.ReadAllBytesAsync(Path.Combine(destination, "model.bin")));
        Assert.False(Directory.Exists(staging));
    }

    [Fact]
    public async Task Cross_volume_install_is_refused_before_moving_payload()
    {
        using var directory = new TemporaryDirectory();
        var manifest = Manifest([1, 2, 3, 4]);
        var staging = Path.Combine(directory.Path, "staging");
        Directory.CreateDirectory(Path.Combine(staging, "payload"));
        await File.WriteAllBytesAsync(Path.Combine(staging, "payload", "model.bin"), [1, 2, 3, 4]);
        var destination = Path.Combine(directory.Path, "installed", manifest.ModelRevision);
        var installer = new QwenModelInstaller(
            new QwenModelIntegrityVerifier(),
            new DifferentVolumeIdentity());

        var result = await installer.InstallAsync(
            manifest,
            staging,
            destination,
            CancellationToken.None);

        Assert.Equal(ModelInstallPhase.Failed, result.Phase);
        Assert.Equal("same_volume_required", result.ErrorCode);
        Assert.True(Directory.Exists(Path.Combine(staging, "payload")));
        Assert.False(Directory.Exists(destination));
    }

    private static QwenModelManifest Manifest(byte[] bytes) => new(
        "qwen3-asr-0.6b",
        "Qwen 0.6B",
        QwenVariant.Qwen06B,
        "revision",
        "runtime",
        bytes.Length,
        [new QwenModelFile(
            "model.bin",
            new Uri("https://models.invalid/model.bin"),
            bytes.Length,
            Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant())],
        new QwenRuntimePublicationGate(true, null));

    private sealed class DifferentVolumeIdentity : IVolumeIdentity
    {
        public string GetIdentity(string path) => path.Contains("staging", StringComparison.Ordinal)
            ? "staging-volume"
            : "install-volume";
    }
}
