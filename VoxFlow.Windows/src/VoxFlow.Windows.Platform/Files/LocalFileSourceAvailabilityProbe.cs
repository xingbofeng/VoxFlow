using System.Security;
using VoxFlow.Windows.Application.FileTranscription;

namespace VoxFlow.Windows.Platform.Files;

public sealed class LocalFileSourceAvailabilityProbe : IFileSourceAvailabilityProbe
{
    public ValueTask<FileSourceAvailability> InspectAsync(
        string sourcePath,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        cancellationToken.ThrowIfCancellationRequested();

        if (!File.Exists(sourcePath))
        {
            return ValueTask.FromResult(FileSourceAvailability.Missing);
        }

        try
        {
            using var stream = new FileStream(
                sourcePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                bufferSize: 1,
                FileOptions.SequentialScan);
            return ValueTask.FromResult(FileSourceAvailability.Available);
        }
        catch (FileNotFoundException)
        {
            return ValueTask.FromResult(FileSourceAvailability.Missing);
        }
        catch (DirectoryNotFoundException)
        {
            return ValueTask.FromResult(FileSourceAvailability.Missing);
        }
        catch (UnauthorizedAccessException)
        {
            return ValueTask.FromResult(FileSourceAvailability.AccessDenied);
        }
        catch (SecurityException)
        {
            return ValueTask.FromResult(FileSourceAvailability.AccessDenied);
        }
        catch (IOException)
        {
            return ValueTask.FromResult(FileSourceAvailability.AccessDenied);
        }
    }
}
