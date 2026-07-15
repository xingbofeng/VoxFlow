using VoxFlow.Windows.Infrastructure.Models;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Models;

public sealed class SystemModelDiskSpaceProbeTests
{
    [Fact]
    public void Existing_model_volume_reports_available_capacity()
    {
        using var directory = new TemporaryDirectory();
        var probe = new SystemModelDiskSpaceProbe();

        var availableBytes = probe.GetAvailableBytes(directory.Path);

        Assert.True(availableBytes > 0);
    }
}
