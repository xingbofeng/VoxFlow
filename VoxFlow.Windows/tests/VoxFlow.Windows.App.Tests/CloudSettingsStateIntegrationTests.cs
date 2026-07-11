using VoxFlow.Windows.App.State;
using VoxFlow.Windows.App.Tray;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class CloudSettingsStateIntegrationTests
{
    [Fact]
    public async Task Saving_and_deleting_each_cloud_provider_refreshes_the_shared_snapshot_without_fallback()
    {
        using var directory = new TemporaryDirectory();
        var rootType = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.WindowsAppCompositionRoot");
        Assert.NotNull(rootType);
        using var root = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            Path.Combine(directory.Path, "voxflow.db"),
            null)!);
        dynamic composition = root;
        var stateStore = Assert.IsType<VoxFlowStateStore>(composition.StateStore);
        using var projection = new SharedAppStateProjection(stateStore);

        await composition.CloudAsrSettings.SaveTencentAsync(
            "fixture-app",
            "fixture-id",
            "fixture-secret",
            CancellationToken.None);
        await composition.CloudAsrSettings.SaveAliyunAsync(
            "fixture-aliyun-key",
            CancellationToken.None);
        await composition.CloudAsrSettings.SaveVolcengineAsync(
            "fixture-volc-app",
            "fixture-access",
            "fixture-volc-secret",
            CancellationToken.None);

        var configured = ((ITrayMenuStateSource)projection).Read();
        Assert.All(
            configured.AsrChoices.Where(choice => choice.Provider != AsrProviderId.Qwen),
            choice =>
            {
                Assert.True(choice.IsConfigured);
                Assert.False(choice.IsReady);
            });

        await composition.CloudAsrSettings.DeleteAsync(
            AsrProviderId.AliyunDashScope,
            CancellationToken.None);

        var afterDelete = ((ITrayMenuStateSource)projection).Read();
        Assert.False(afterDelete.AsrChoices.Single(choice =>
            choice.Provider == AsrProviderId.AliyunDashScope).IsConfigured);
        Assert.Null(afterDelete.SelectedAsr);
    }
}
