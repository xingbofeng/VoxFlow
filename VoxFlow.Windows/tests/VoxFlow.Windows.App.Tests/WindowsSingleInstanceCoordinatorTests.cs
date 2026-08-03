using VoxFlow.Windows.App.State;

namespace VoxFlow.Windows.App.Tests;

public sealed class WindowsSingleInstanceCoordinatorTests
{
    [Fact]
    public async Task Secondary_instance_signals_primary_and_does_not_take_ownership()
    {
        var identity = "VoxFlow.Tests." + Guid.NewGuid().ToString("N");
        using var activated = new ManualResetEventSlim();
        using var primary = WindowsSingleInstanceCoordinator.Start(
            identity,
            activated.Set);

        Assert.True(primary.IsPrimary);

        WindowsSingleInstanceCoordinator? secondary = null;
        await Task.Run(() =>
        {
            secondary = WindowsSingleInstanceCoordinator.Start(identity, () => { });
        });
        using (secondary)
        {
            Assert.NotNull(secondary);
            Assert.False(secondary.IsPrimary);
            Assert.True(secondary.ActivationSignaled);
        }

        Assert.True(activated.Wait(TimeSpan.FromSeconds(2)));
    }

    [Fact]
    public void Released_identity_can_become_primary_again()
    {
        var identity = "VoxFlow.Tests." + Guid.NewGuid().ToString("N");
        using (var first = WindowsSingleInstanceCoordinator.Start(identity, () => { }))
        {
            Assert.True(first.IsPrimary);
        }

        using var next = WindowsSingleInstanceCoordinator.Start(identity, () => { });
        Assert.True(next.IsPrimary);
    }
}
