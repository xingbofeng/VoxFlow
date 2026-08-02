namespace VoxFlow.Windows.Application.Models;

public interface IModelDiskSpaceProbe
{
    long GetAvailableBytes(string path);
}

public interface IQwenModelOperations
{
    Task<ModelInstallRecord> DownloadAsync(
        QwenModelManifest manifest,
        bool userInitiated,
        CancellationToken cancellationToken);

    Task<ModelInstallRecord> RetryAsync(
        QwenModelManifest manifest,
        CancellationToken cancellationToken);

    Task PauseAsync(QwenModelManifest manifest);

    Task CancelAsync(QwenModelManifest manifest);

    Task DeleteAsync(
        QwenModelManifest manifest,
        CancellationToken cancellationToken);

    void Select(string modelId);
}
