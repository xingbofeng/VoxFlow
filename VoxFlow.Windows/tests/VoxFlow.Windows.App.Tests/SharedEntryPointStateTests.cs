using VoxFlow.Windows.App.Tray;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class SharedEntryPointStateTests
{
    [Fact]
    public void Provider_and_OpenAI_changes_publish_one_snapshot_to_home_settings_tray_and_HUD()
    {
        var store = new VoxFlowStateStore();
        dynamic projection = Create(
            "VoxFlow.Windows.App.State.SharedAppStateProjection",
            store);
        dynamic coordinator = Create(
            "VoxFlow.Windows.App.State.SettingsStateCoordinator",
            store);
        dynamic home = Create(
            "VoxFlow.Windows.App.State.HomeStateObserver",
            projection);
        dynamic settings = Create(
            "VoxFlow.Windows.App.State.SettingsStateObserver",
            projection);
        dynamic hud = Create(
            "VoxFlow.Windows.App.State.HudStateObserver",
            projection);

        coordinator.RecordCloudProvider(
            AsrProviderId.TencentCloud,
            true,
            true);
        coordinator.SelectAsr(AsrProviderId.TencentCloud, null);
        coordinator.RecordOpenAi(true, true);

        var expectedVersion = store.Current.Version;
        Assert.Equal(expectedVersion, (long)home.ObservedVersion);
        Assert.Equal(expectedVersion, (long)settings.ObservedVersion);
        Assert.Equal(expectedVersion, (long)hud.ObservedVersion);

        var tray = ((ITrayMenuStateSource)projection).Read();
        Assert.Equal(AsrProviderId.TencentCloud, tray.SelectedAsr!.Provider);
        Assert.True(tray.AsrChoices.Single(choice =>
            choice.Provider == AsrProviderId.TencentCloud).IsReady);
        Assert.True(tray.OpenAiConfigured);
        Assert.True(tray.OpenAiEnabled);
    }

    [Fact]
    public void Deleting_the_current_provider_clears_selection_without_choosing_a_fallback()
    {
        var store = new VoxFlowStateStore();
        dynamic projection = Create(
            "VoxFlow.Windows.App.State.SharedAppStateProjection",
            store);
        dynamic coordinator = Create(
            "VoxFlow.Windows.App.State.SettingsStateCoordinator",
            store);
        coordinator.RecordCloudProvider(AsrProviderId.AliyunDashScope, true, true);
        coordinator.SelectAsr(AsrProviderId.AliyunDashScope, null);

        coordinator.RecordCloudProvider(AsrProviderId.AliyunDashScope, false, false);

        var tray = ((ITrayMenuStateSource)projection).Read();
        Assert.Null(tray.SelectedAsr);
        Assert.False(tray.AsrChoices.Single(choice =>
            choice.Provider == AsrProviderId.AliyunDashScope).IsConfigured);
        Assert.DoesNotContain(tray.AsrChoices, choice =>
            choice.IsReady && choice.Provider != AsrProviderId.AliyunDashScope);
    }

    private static object Create(string typeName, params object[] arguments)
    {
        var type = typeof(MainWindow).Assembly.GetType(typeName);
        Assert.NotNull(type);
        var instance = Activator.CreateInstance(type, arguments);
        Assert.NotNull(instance);
        return instance;
    }
}
