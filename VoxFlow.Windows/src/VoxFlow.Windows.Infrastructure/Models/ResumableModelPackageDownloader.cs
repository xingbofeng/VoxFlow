using System.Text.Json;
using VoxFlow.Windows.Application.Models;

namespace VoxFlow.Windows.Infrastructure.Models;

public enum ModelPackageDownloadOutcome
{
    Completed,
    Paused,
    Cancelled,
}

public sealed record ModelPackageDownloadResult(
    ModelPackageDownloadOutcome Outcome,
    long BytesDownloaded,
    long TotalBytes);

public sealed class ResumableModelPackageDownloader
{
    private const long StateCheckpointIntervalBytes = 1024 * 1024;
    private const int StateReplaceAttempts = 6;
    private readonly object gate = new();
    private readonly Dictionary<string, ActiveTransfer> activeTransfers = [];
    private readonly ResumableModelFileDownloader fileDownloader;

    public ResumableModelPackageDownloader(ResumableModelFileDownloader fileDownloader)
    {
        this.fileDownloader = fileDownloader
            ?? throw new ArgumentNullException(nameof(fileDownloader));
    }

    public Task<ModelPackageDownloadResult> StartAsync(
        QwenModelManifest manifest,
        string stagingDirectory,
        Action<long>? progress = null)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        ArgumentException.ThrowIfNullOrWhiteSpace(stagingDirectory);
        var key = GetKey(manifest.Id, manifest.ModelRevision);

        lock (gate)
        {
            if (activeTransfers.TryGetValue(key, out var existing))
            {
                existing.AddProgressObserver(progress);
                return existing.Task;
            }

            var transfer = new ActiveTransfer();
            transfer.AddProgressObserver(progress);
            activeTransfers.Add(key, transfer);
            transfer.Task = Task.Run(() => RunAndRemoveAsync(
                key,
                transfer,
                manifest,
                Path.GetFullPath(stagingDirectory)));
            return transfer.Task;
        }
    }

    public Task PauseAsync(string modelId, string revision) =>
        StopAsync(modelId, revision, ModelPackageDownloadOutcome.Paused);

    public Task CancelAsync(string modelId, string revision) =>
        StopAsync(modelId, revision, ModelPackageDownloadOutcome.Cancelled);

    private async Task StopAsync(
        string modelId,
        string revision,
        ModelPackageDownloadOutcome outcome)
    {
        ActiveTransfer? transfer;
        lock (gate)
        {
            activeTransfers.TryGetValue(GetKey(modelId, revision), out transfer);
            if (transfer is not null)
            {
                transfer.StopOutcome = outcome;
                transfer.Cancellation.Cancel();
            }
        }

        if (transfer is not null)
        {
            _ = await transfer.Task.ConfigureAwait(false);
        }
    }

    private async Task<ModelPackageDownloadResult> RunAndRemoveAsync(
        string key,
        ActiveTransfer transfer,
        QwenModelManifest manifest,
        string stagingDirectory)
    {
        try
        {
            return await RunAsync(transfer, manifest, stagingDirectory).ConfigureAwait(false);
        }
        finally
        {
            lock (gate)
            {
                if (activeTransfers.TryGetValue(key, out var current)
                    && ReferenceEquals(current, transfer))
                {
                    activeTransfers.Remove(key);
                }
            }

            transfer.Cancellation.Dispose();
        }
    }

    private async Task<ModelPackageDownloadResult> RunAsync(
        ActiveTransfer transfer,
        QwenModelManifest manifest,
        string stagingDirectory)
    {
        var payloadRoot = Path.Combine(stagingDirectory, "payload");
        var statePath = Path.Combine(stagingDirectory, ".download-state.json");
        Directory.CreateDirectory(payloadRoot);
        var completedBeforeCurrentFile = 0L;
        var lastPersistedBytes = 0L;
        SaveState(statePath, manifest, completedBeforeCurrentFile, "downloading");
        transfer.PublishProgress(completedBeforeCurrentFile);

        try
        {
            foreach (var file in manifest.Files)
            {
                var destination = ResolvePayloadPath(payloadRoot, file.Name);
                var result = await fileDownloader.DownloadAsync(
                    file,
                    destination,
                    currentFileBytes =>
                    {
                        var downloadedBytes = checked(
                            completedBeforeCurrentFile + currentFileBytes);
                        transfer.PublishProgress(downloadedBytes);
                        if (downloadedBytes - lastPersistedBytes
                            < StateCheckpointIntervalBytes)
                        {
                            return;
                        }

                        SaveState(
                            statePath,
                            manifest,
                            downloadedBytes,
                            "downloading");
                        lastPersistedBytes = downloadedBytes;
                    },
                    transfer.Cancellation.Token).ConfigureAwait(false);
                completedBeforeCurrentFile = checked(
                    completedBeforeCurrentFile + result.BytesDownloaded);
                SaveState(
                    statePath,
                    manifest,
                    completedBeforeCurrentFile,
                    "downloading");
                lastPersistedBytes = completedBeforeCurrentFile;
                transfer.PublishProgress(completedBeforeCurrentFile);
            }

            SaveState(statePath, manifest, completedBeforeCurrentFile, "completed");
            transfer.PublishProgress(completedBeforeCurrentFile);
            return new ModelPackageDownloadResult(
                ModelPackageDownloadOutcome.Completed,
                completedBeforeCurrentFile,
                manifest.TotalBytes);
        }
        catch (OperationCanceledException) when (transfer.Cancellation.IsCancellationRequested)
        {
            var downloaded = CountPayloadBytes(payloadRoot);
            SaveState(
                statePath,
                manifest,
                downloaded,
                transfer.StopOutcome == ModelPackageDownloadOutcome.Paused
                    ? "paused"
                    : "cancelled");
            transfer.PublishProgress(downloaded);
            return new ModelPackageDownloadResult(
                transfer.StopOutcome,
                downloaded,
                manifest.TotalBytes);
        }
    }

    private static string ResolvePayloadPath(string payloadRoot, string relativeName)
    {
        var path = Path.GetFullPath(Path.Combine(
            payloadRoot,
            relativeName.Replace('/', Path.DirectorySeparatorChar)));
        var rootWithSeparator = payloadRoot.EndsWith(Path.DirectorySeparatorChar)
            ? payloadRoot
            : payloadRoot + Path.DirectorySeparatorChar;
        if (!path.StartsWith(rootWithSeparator, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Model file escapes the staging payload directory.");
        }

        return path;
    }

    private static long CountPayloadBytes(string payloadRoot) => Directory.Exists(payloadRoot)
        ? Directory.EnumerateFiles(payloadRoot, "*", SearchOption.AllDirectories)
            .Sum(path => new FileInfo(path).Length)
        : 0;

    private static void SaveState(
        string statePath,
        QwenModelManifest manifest,
        long downloadedBytes,
        string status)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(statePath)!);
        var temporaryPath = string.Concat(
            statePath,
            ".tmp-",
            Guid.NewGuid().ToString("N"));
        var json = JsonSerializer.Serialize(new DownloadState(
            manifest.Id,
            manifest.ModelRevision,
            status,
            downloadedBytes,
            manifest.TotalBytes));
        try
        {
            File.WriteAllText(temporaryPath, json);
            for (var attempt = 1; ; attempt++)
            {
                try
                {
                    File.Move(temporaryPath, statePath, overwrite: true);
                    break;
                }
                catch (Exception exception) when (
                    exception is IOException or UnauthorizedAccessException
                    && attempt < StateReplaceAttempts)
                {
                    Thread.Sleep(TimeSpan.FromMilliseconds(15 * attempt));
                }
            }
        }
        finally
        {
            try
            {
                File.Delete(temporaryPath);
            }
            catch (IOException)
            {
                // A stale checkpoint temp file is safe to ignore and can be
                // removed by the next model-store maintenance pass.
            }
            catch (UnauthorizedAccessException)
            {
                // Antivirus can briefly retain a completed temp file.
            }
        }
    }

    private static string GetKey(string modelId, string revision)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(modelId);
        ArgumentException.ThrowIfNullOrWhiteSpace(revision);
        return $"{modelId}\n{revision}";
    }

    private sealed record DownloadState(
        string ModelId,
        string Revision,
        string Status,
        long DownloadedBytes,
        long TotalBytes);

    private sealed class ActiveTransfer
    {
        private readonly object observerGate = new();
        private readonly List<Action<long>> progressObservers = [];

        public CancellationTokenSource Cancellation { get; } = new();

        public ModelPackageDownloadOutcome StopOutcome { get; set; } =
            ModelPackageDownloadOutcome.Cancelled;

        public Task<ModelPackageDownloadResult> Task { get; set; } = null!;

        public void AddProgressObserver(Action<long>? observer)
        {
            if (observer is null)
            {
                return;
            }

            lock (observerGate)
            {
                progressObservers.Add(observer);
            }
        }

        public void PublishProgress(long downloadedBytes)
        {
            Action<long>[] observers;
            lock (observerGate)
            {
                observers = [.. progressObservers];
            }

            foreach (var observer in observers)
            {
                observer(downloadedBytes);
            }
        }
    }
}
