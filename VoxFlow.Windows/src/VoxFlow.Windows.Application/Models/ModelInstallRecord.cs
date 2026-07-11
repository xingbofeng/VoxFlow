using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Models;

public sealed record ModelInstallRecord
{
    public ModelInstallRecord(
        string modelId,
        string version,
        ModelInstallPhase phase,
        long bytesDownloaded,
        long totalBytes,
        string? installPath,
        string? errorCode)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(modelId);
        ArgumentException.ThrowIfNullOrWhiteSpace(version);

        if (bytesDownloaded < 0 || totalBytes < 0 || bytesDownloaded > totalBytes)
        {
            throw new ArgumentOutOfRangeException(
                nameof(bytesDownloaded),
                "Downloaded bytes must be within the model total.");
        }

        ModelId = modelId;
        Version = version;
        Phase = phase;
        BytesDownloaded = bytesDownloaded;
        TotalBytes = totalBytes;
        InstallPath = installPath;
        ErrorCode = errorCode;
    }

    public string ModelId { get; }

    public string Version { get; }

    public ModelInstallPhase Phase { get; }

    public long BytesDownloaded { get; }

    public long TotalBytes { get; }

    public string? InstallPath { get; }

    public string? ErrorCode { get; }

    public ModelInstallRecord MoveTo(
        ModelInstallPhase phase,
        long? bytesDownloaded = null,
        string? installPath = null,
        string? errorCode = null)
    {
        ModelInstallTransitions.EnsureCanMove(Phase, phase);
        return new ModelInstallRecord(
            ModelId,
            Version,
            phase,
            bytesDownloaded ?? BytesDownloaded,
            TotalBytes,
            installPath ?? InstallPath,
            errorCode);
    }
}

public interface IModelInstallStateRepository
{
    ValueTask<ModelInstallRecord?> LoadAsync(
        string modelId,
        CancellationToken cancellationToken);

    ValueTask SaveAsync(
        ModelInstallRecord state,
        CancellationToken cancellationToken);

    ValueTask DeleteAsync(
        string modelId,
        CancellationToken cancellationToken);
}

public interface IQwenModelRuntimeCache
{
    ValueTask ReleaseAsync(
        string modelId,
        string revision,
        CancellationToken cancellationToken);
}
