using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.FileTranscription;

public enum FileSourceAvailability
{
    Available,
    Missing,
    AccessDenied,
}

public interface IFileSourceAvailabilityProbe
{
    ValueTask<FileSourceAvailability> InspectAsync(
        string sourcePath,
        CancellationToken cancellationToken);
}

public sealed record FileTranscriptionSourceCheckResult(
    FileTranscriptionJob Job,
    bool IsAvailable,
    FileTranscriptionErrorCode? ErrorCode);

public sealed class FileTranscriptionSourceGuard
{
    private readonly IFileSourceAvailabilityProbe probe;

    public FileTranscriptionSourceGuard(IFileSourceAvailabilityProbe probe)
    {
        this.probe = probe ?? throw new ArgumentNullException(nameof(probe));
    }

    public async ValueTask<FileTranscriptionSourceCheckResult> CheckAsync(
        FileTranscriptionJob job,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(job);
        var availability = await probe
            .InspectAsync(job.SourcePath, cancellationToken)
            .ConfigureAwait(false);
        if (!Enum.IsDefined(availability))
        {
            throw new InvalidDataException("The file source probe returned an unknown availability state.");
        }

        return new FileTranscriptionSourceCheckResult(
            job,
            availability == FileSourceAvailability.Available,
            availability == FileSourceAvailability.Available
                ? null
                : FileTranscriptionErrorCode.SourceUnavailable);
    }
}
