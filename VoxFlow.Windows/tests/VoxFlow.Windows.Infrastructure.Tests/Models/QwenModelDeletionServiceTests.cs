using System.Security.Cryptography;
using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Models;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Models;

public sealed class QwenModelDeletionServiceTests
{
    [Fact]
    public async Task Delete_clears_all_variant_versions_staging_state_and_runtime_cache()
    {
        using var directory = new TemporaryDirectory();
        var localAppData = Path.Combine(directory.Path, "LocalAppData");
        var paths = new QwenModelDataPaths(localAppData);
        var manifest = Manifest();
        var oldVersion = paths.GetInstallDirectory(manifest.Variant, "old-revision");
        var currentVersion = paths.GetInstallDirectory(manifest.Variant, manifest.ModelRevision);
        var staging = paths.GetStagingDirectory(manifest.Variant, manifest.ModelRevision);
        Directory.CreateDirectory(oldVersion);
        Directory.CreateDirectory(currentVersion);
        Directory.CreateDirectory(staging);
        await File.WriteAllTextAsync(Path.Combine(oldVersion, "old.bin"), "old");
        await File.WriteAllTextAsync(Path.Combine(currentVersion, "model.bin"), "current");
        await File.WriteAllTextAsync(paths.GetDownloadStatePath(manifest.Variant, manifest.ModelRevision), "{}");
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        using var runner = new SqliteTransactionRunner(
            new SqliteConnectionFactory(databasePath, pooling: false));
        var repository = new SqliteModelInstallStateRepository(runner);
        await repository.SaveAsync(
            new ModelInstallRecord(
                manifest.Id,
                manifest.ModelRevision,
                ModelInstallPhase.Ready,
                manifest.TotalBytes,
                manifest.TotalBytes,
                currentVersion,
                null),
            CancellationToken.None);
        var runtimeCache = new CapturingRuntimeCache();
        var deletion = new QwenModelDeletionService(paths, repository, runtimeCache);

        await deletion.DeleteAsync(manifest, CancellationToken.None);

        Assert.False(Directory.Exists(Path.GetDirectoryName(currentVersion)!));
        Assert.False(Directory.Exists(Path.GetDirectoryName(staging)!));
        Assert.Null(await repository.LoadAsync(manifest.Id, CancellationToken.None));
        Assert.Equal([(manifest.Id, manifest.ModelRevision)], runtimeCache.Released);
    }

    private static QwenModelManifest Manifest()
    {
        byte[] bytes = [1];
        return new QwenModelManifest(
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
    }

    private sealed class CapturingRuntimeCache : IQwenModelRuntimeCache
    {
        public List<(string ModelId, string Revision)> Released { get; } = [];

        public ValueTask ReleaseAsync(
            string modelId,
            string revision,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Released.Add((modelId, revision));
            return ValueTask.CompletedTask;
        }
    }
}
