using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Models;

public sealed class QwenModelLifecycleOperations : IQwenModelOperations
{
    private readonly QwenModelDataPaths paths;
    private readonly IModelDiskSpaceProbe diskSpace;
    private readonly ResumableModelPackageDownloader packageDownloader;
    private readonly QwenModelInstaller installer;
    private readonly QwenModelReadinessService readiness;
    private readonly QwenModelDeletionService deletion;
    private readonly IModelInstallStateRepository stateRepository;
    private readonly IModelInstallStatePublisher statePublisher;
    private readonly QwenModelStateSynchronizer? stateSynchronizer;

    public QwenModelLifecycleOperations(
        QwenModelDataPaths paths,
        IModelDiskSpaceProbe diskSpace,
        ResumableModelPackageDownloader packageDownloader,
        QwenModelInstaller installer,
        QwenModelReadinessService readiness,
        QwenModelDeletionService deletion,
        IModelInstallStateRepository stateRepository,
        IModelInstallStatePublisher statePublisher,
        QwenModelStateSynchronizer? stateSynchronizer = null)
    {
        this.paths = paths ?? throw new ArgumentNullException(nameof(paths));
        this.diskSpace = diskSpace ?? throw new ArgumentNullException(nameof(diskSpace));
        this.packageDownloader = packageDownloader
            ?? throw new ArgumentNullException(nameof(packageDownloader));
        this.installer = installer ?? throw new ArgumentNullException(nameof(installer));
        this.readiness = readiness ?? throw new ArgumentNullException(nameof(readiness));
        this.deletion = deletion ?? throw new ArgumentNullException(nameof(deletion));
        this.stateRepository = stateRepository
            ?? throw new ArgumentNullException(nameof(stateRepository));
        this.statePublisher = statePublisher
            ?? throw new ArgumentNullException(nameof(statePublisher));
        this.stateSynchronizer = stateSynchronizer;
    }

    public async Task<ModelInstallRecord> DownloadAsync(
        QwenModelManifest manifest,
        bool userInitiated,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        var existing = await stateRepository.LoadAsync(manifest.Id, cancellationToken)
            .ConfigureAwait(false);
        var current = NormalizeExisting(existing, manifest);

        if (!userInitiated)
        {
            statePublisher.Publish(manifest, current);
            return current;
        }

        if (!manifest.RuntimeGate.IsPublishable)
        {
            current = new ModelInstallRecord(
                manifest.Id,
                manifest.ModelRevision,
                ModelInstallPhase.RuntimeUnsupported,
                current.BytesDownloaded,
                manifest.TotalBytes,
                current.InstallPath,
                "runtime_provenance_blocked");
            await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
            return current;
        }

        if (current.Phase == ModelInstallPhase.Ready)
        {
            statePublisher.Publish(manifest, current);
            return current;
        }

        var installDirectory = paths.GetInstallDirectory(
            manifest.Variant,
            manifest.ModelRevision);
        if (Directory.Exists(installDirectory))
        {
            var installedIntegrity = await installer.VerifyExistingAsync(
                manifest,
                installDirectory,
                cancellationToken).ConfigureAwait(false);
            if (installedIntegrity.IsValid)
            {
                DeleteDirectoryIfPresent(paths.GetStagingDirectory(
                    manifest.Variant,
                    manifest.ModelRevision));
                current = new ModelInstallRecord(
                    manifest.Id,
                    manifest.ModelRevision,
                    ModelInstallPhase.Installing,
                    manifest.TotalBytes,
                    manifest.TotalBytes,
                    installDirectory,
                    null);
                await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
                return await readiness.EvaluateAsync(
                    manifest,
                    installDirectory,
                    cancellationToken).ConfigureAwait(false);
            }

            Directory.Delete(installDirectory, recursive: true);
            current = NewNotDownloaded(manifest);
            await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
        }

        var preflight = QwenModelDownloadPreflight.Evaluate(
            manifest,
            userInitiated: true,
            diskSpace.GetAvailableBytes(paths.ModelsRoot));
        if (!preflight.CanStart)
        {
            current = MoveToQueued(current, manifest);
            await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
            current = current.MoveTo(
                ModelInstallPhase.InsufficientSpace,
                errorCode: preflight.ErrorCode);
            await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
            return current;
        }

        if (current.Phase == ModelInstallPhase.Paused)
        {
            current = current.MoveTo(ModelInstallPhase.Downloading, errorCode: null);
        }
        else if (current.Phase != ModelInstallPhase.Downloading)
        {
            current = MoveToQueued(current, manifest);
            await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
            current = current.MoveTo(ModelInstallPhase.Downloading, errorCode: null);
        }

        await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
        var progressGate = new object();
        var progressState = current;
        var stagingDirectory = paths.GetStagingDirectory(
            manifest.Variant,
            manifest.ModelRevision);
        var download = packageDownloader.StartAsync(
            manifest,
            stagingDirectory,
            downloadedBytes =>
            {
                lock (progressGate)
                {
                    if (progressState.Phase != ModelInstallPhase.Downloading
                        || downloadedBytes == progressState.BytesDownloaded)
                    {
                        return;
                    }

                    progressState = new ModelInstallRecord(
                        manifest.Id,
                        manifest.ModelRevision,
                        ModelInstallPhase.Downloading,
                        Math.Min(downloadedBytes, manifest.TotalBytes),
                        manifest.TotalBytes,
                        null,
                        null);
                    SaveAsync(manifest, progressState, CancellationToken.None)
                        .AsTask()
                        .GetAwaiter()
                        .GetResult();
                }
            });
        using var cancellationRegistration = cancellationToken.Register(() =>
            _ = packageDownloader.CancelAsync(manifest.Id, manifest.ModelRevision));
        var downloadResult = await download.ConfigureAwait(false);
        lock (progressGate)
        {
            current = progressState;
        }

        if (downloadResult.Outcome is ModelPackageDownloadOutcome.Paused
            or ModelPackageDownloadOutcome.Cancelled)
        {
            current = current.MoveTo(
                ModelInstallPhase.Paused,
                bytesDownloaded: downloadResult.BytesDownloaded);
            await SaveAsync(manifest, current, CancellationToken.None).ConfigureAwait(false);
            return current;
        }

        cancellationToken.ThrowIfCancellationRequested();
        current = current.MoveTo(
            ModelInstallPhase.Verifying,
            bytesDownloaded: manifest.TotalBytes);
        await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
        var install = await installer.InstallAsync(
            manifest,
            stagingDirectory,
            installDirectory,
            cancellationToken).ConfigureAwait(false);
        if (install.Phase != ModelInstallPhase.Installing)
        {
            current = current.MoveTo(
                install.Phase,
                errorCode: install.ErrorCode);
            await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
            return current;
        }

        current = current.MoveTo(
            ModelInstallPhase.Installing,
            installPath: install.InstallPath);
        await SaveAsync(manifest, current, cancellationToken).ConfigureAwait(false);
        return await readiness.EvaluateAsync(
            manifest,
            install.InstallPath!,
            cancellationToken).ConfigureAwait(false);
    }

    public Task<ModelInstallRecord> RetryAsync(
        QwenModelManifest manifest,
        CancellationToken cancellationToken) =>
        DownloadAsync(manifest, userInitiated: true, cancellationToken);

    public Task PauseAsync(QwenModelManifest manifest)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        return packageDownloader.PauseAsync(manifest.Id, manifest.ModelRevision);
    }

    public Task CancelAsync(QwenModelManifest manifest)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        return packageDownloader.CancelAsync(manifest.Id, manifest.ModelRevision);
    }

    public Task DeleteAsync(
        QwenModelManifest manifest,
        CancellationToken cancellationToken) =>
        deletion.DeleteAsync(manifest, cancellationToken);

    public void Select(string modelId)
    {
        if (stateSynchronizer is null)
        {
            throw new InvalidOperationException(
                "Qwen model selection requires the shared state synchronizer.");
        }

        stateSynchronizer.Select(modelId);
    }

    private async ValueTask SaveAsync(
        QwenModelManifest manifest,
        ModelInstallRecord state,
        CancellationToken cancellationToken)
    {
        await stateRepository.SaveAsync(state, cancellationToken).ConfigureAwait(false);
        statePublisher.Publish(manifest, state);
    }

    private static ModelInstallRecord NormalizeExisting(
        ModelInstallRecord? existing,
        QwenModelManifest manifest)
    {
        if (existing is null
            || !string.Equals(existing.Version, manifest.ModelRevision, StringComparison.Ordinal))
        {
            return NewNotDownloaded(manifest);
        }

        return existing;
    }

    private static ModelInstallRecord MoveToQueued(
        ModelInstallRecord current,
        QwenModelManifest manifest)
    {
        if (current.Phase == ModelInstallPhase.RuntimeUnsupported
            && manifest.RuntimeGate.IsPublishable)
        {
            current = NewNotDownloaded(manifest);
        }

        if (current.Phase == ModelInstallPhase.NotDownloaded
            || current.Phase is ModelInstallPhase.InsufficientSpace
                or ModelInstallPhase.Corrupted
                or ModelInstallPhase.Failed)
        {
            return current.MoveTo(ModelInstallPhase.Queued, errorCode: null);
        }

        throw new InvalidOperationException(
            $"A download cannot start while model state is {current.Phase}.");
    }

    private static ModelInstallRecord NewNotDownloaded(QwenModelManifest manifest) => new(
        manifest.Id,
        manifest.ModelRevision,
        ModelInstallPhase.NotDownloaded,
        0,
        manifest.TotalBytes,
        null,
        null);

    private static void DeleteDirectoryIfPresent(string path)
    {
        if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }
    }
}
