using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Platform.Files;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Platform.Tests;

public sealed class LocalFileSourceAvailabilityProbeTests
{
    [Fact]
    public async Task Existing_readable_file_is_available_and_missing_file_is_not()
    {
        using var directory = new TemporaryDirectory();
        var readablePath = Path.Combine(directory.Path, "audio.wav");
        await File.WriteAllBytesAsync(readablePath, [1, 2, 3]);
        var probe = new LocalFileSourceAvailabilityProbe();

        var available = await probe.InspectAsync(readablePath, CancellationToken.None);
        var missing = await probe.InspectAsync(
            Path.Combine(directory.Path, "missing.wav"),
            CancellationToken.None);

        Assert.Equal(FileSourceAvailability.Available, available);
        Assert.Equal(FileSourceAvailability.Missing, missing);
    }
}
