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

        var savedCredentials = await composition.CloudAsrSettings.LoadAsync(
            CancellationToken.None);
        Assert.Equal("••••••••", savedCredentials.Tencent.AppId.Mask);
        Assert.Equal("••••••••", savedCredentials.Tencent.SecretId.Mask);
        Assert.Equal("••••••••", savedCredentials.Tencent.SecretKey.Mask);
        Assert.Equal("••••••••", savedCredentials.Aliyun.ApiKey.Mask);
        Assert.Equal("••••••••", savedCredentials.Volcengine.AppId.Mask);
        Assert.Equal("••••••••", savedCredentials.Volcengine.AccessToken.Mask);
        Assert.Equal("••••••••", savedCredentials.Volcengine.SecretKey.Mask);

        var configured = ((ITrayMenuStateSource)projection).Read();
        Assert.All(
            configured.AsrChoices.Where(choice => choice.Provider != AsrProviderId.Qwen),
            choice =>
            {
                Assert.True(choice.IsConfigured);
                Assert.True(choice.IsReady);
            });
        // The last saved cloud provider is auto-selected for dictation.
        Assert.Equal(AsrProviderId.Volcengine, configured.SelectedAsr?.Provider);

        await composition.CloudAsrSettings.DeleteAsync(
            AsrProviderId.AliyunDashScope,
            CancellationToken.None);

        var afterDelete = ((ITrayMenuStateSource)projection).Read();
        Assert.False(afterDelete.AsrChoices.Single(choice =>
            choice.Provider == AsrProviderId.AliyunDashScope).IsConfigured);
        Assert.Equal(AsrProviderId.Volcengine, afterDelete.SelectedAsr?.Provider);
    }

    [Fact]
    public async Task Saving_tencent_auto_selects_it_as_the_active_asr_provider()
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

        var snapshot = ((ITrayMenuStateSource)projection).Read();
        Assert.Equal(AsrProviderId.TencentCloud, snapshot.SelectedAsr?.Provider);
        var tencent = snapshot.AsrChoices.Single(choice =>
            choice.Provider == AsrProviderId.TencentCloud);
        Assert.True(tencent.IsConfigured);
        Assert.True(tencent.IsReady);

        // Selection must survive process restart via SQLite.
        await composition.BootstrapAsrAsync(CancellationToken.None);
        using var second = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            Path.Combine(directory.Path, "voxflow.db"),
            null)!);
        dynamic secondComposition = second;
        await secondComposition.BootstrapAsrAsync(CancellationToken.None);
        var restored = Assert.IsType<VoxFlowStateStore>(secondComposition.StateStore)
            .Current.State.Settings;
        Assert.Equal(
            nameof(AsrProviderId.TencentCloud),
            restored["asr.selected.provider"]);
    }

    [Fact]
    public async Task Bootstrap_restores_saved_provider_when_multiple_cloud_providers_are_ready()
    {
        using var directory = new TemporaryDirectory();
        var rootType = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.WindowsAppCompositionRoot");
        Assert.NotNull(rootType);
        using var first = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            Path.Combine(directory.Path, "voxflow.db"),
            null)!);
        dynamic firstComposition = first;

        await firstComposition.CloudAsrSettings.SaveTencentAsync(
            "fixture-app",
            "fixture-id",
            "fixture-secret",
            CancellationToken.None);
        await firstComposition.CloudAsrSettings.SaveAliyunAsync(
            "fixture-aliyun-key",
            CancellationToken.None);
        var selected = Assert.IsType<VoxFlowStateStore>(firstComposition.StateStore)
            .Current.State.Settings;
        Assert.Equal(
            nameof(AsrProviderId.AliyunDashScope),
            selected["asr.selected.provider"]);

        using var second = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            Path.Combine(directory.Path, "voxflow.db"),
            null)!);
        dynamic secondComposition = second;
        await secondComposition.BootstrapAsrAsync(CancellationToken.None);

        var restored = Assert.IsType<VoxFlowStateStore>(secondComposition.StateStore)
            .Current.State.Settings;
        Assert.Equal(
            nameof(AsrProviderId.AliyunDashScope),
            restored["asr.selected.provider"]);
    }
}
