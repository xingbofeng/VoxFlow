using VoxFlow.Windows.Application.Models;

namespace VoxFlow.Windows.Infrastructure.Models;

public sealed class QwenModelDeletionService
{
    private readonly QwenModelDataPaths paths;
    private readonly IModelInstallStateRepository stateRepository;
    private readonly IQwenModelRuntimeCache runtimeCache;
    private readonly IModelInstallStatePublisher? statePublisher;

    public QwenModelDeletionService(
        QwenModelDataPaths paths,
        IModelInstallStateRepository stateRepository,
        IQwenModelRuntimeCache runtimeCache,
        IModelInstallStatePublisher? statePublisher = null)
    {
        this.paths = paths ?? throw new ArgumentNullException(nameof(paths));
        this.stateRepository = stateRepository
            ?? throw new ArgumentNullException(nameof(stateRepository));
        this.runtimeCache = runtimeCache
            ?? throw new ArgumentNullException(nameof(runtimeCache));
        this.statePublisher = statePublisher;
    }

    public async Task DeleteAsync(
        QwenModelManifest manifest,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        await runtimeCache.ReleaseAsync(
            manifest.Id,
            manifest.ModelRevision,
            cancellationToken).ConfigureAwait(false);

        DeleteDirectoryIfPresent(paths.GetVariantInstallRoot(manifest.Variant));
        DeleteDirectoryIfPresent(paths.GetVariantStagingRoot(manifest.Variant));
        await stateRepository.DeleteAsync(manifest.Id, cancellationToken).ConfigureAwait(false);
        statePublisher?.Publish(
            manifest,
            new ModelInstallRecord(
                manifest.Id,
                manifest.ModelRevision,
                Domain.ModelInstallPhase.NotDownloaded,
                0,
                manifest.TotalBytes,
                null,
                null));
    }

    private static void DeleteDirectoryIfPresent(string path)
    {
        if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }
    }
}
