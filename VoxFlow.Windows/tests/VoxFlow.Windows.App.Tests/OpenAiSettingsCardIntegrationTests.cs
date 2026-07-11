using VoxFlow.Windows.App.Shell;
using VoxFlow.Windows.Application.State;
using VoxFlow.Windows.Application.Text;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class OpenAiSettingsCardIntegrationTests
{
    [Fact]
    public async Task Save_and_confirmed_delete_refresh_the_shared_state_while_cancelled_delete_preserves_it()
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
        var textStore = Assert.IsAssignableFrom<ITextProcessingSettingsStore>(
            composition.TextSettingsStore);
        var settings = Assert.IsType<SettingsPageViewModel>(Activator.CreateInstance(
            typeof(SettingsPageViewModel),
            "Settings",
            "Configure VoxFlow",
            stateStore,
            textStore,
            composition.OpenAiSettingsService));
        await settings.InitializeAsync(CancellationToken.None);
        Assert.True(settings.TryNavigate("text"));
        dynamic card = Assert.IsType<TextSettingsPageViewModel>(settings.CurrentPage).OpenAi;

        await card.SaveAsync(
            string.Concat("fixture", "-openai-key"),
            "gpt-4.1-mini",
            true,
            CancellationToken.None);

        Assert.True((bool)card.IsConfigured);
        Assert.Equal("true", stateStore.Current.State.Settings["openai.configured"]);
        Assert.Equal("true", stateStore.Current.State.Settings["openai.enabled"]);

        Assert.False((bool)await card.DeleteAsync(false, CancellationToken.None));
        Assert.True((bool)card.IsConfigured);
        Assert.True((bool)await card.DeleteAsync(true, CancellationToken.None));
        Assert.False((bool)card.IsConfigured);
        Assert.Equal("false", stateStore.Current.State.Settings["openai.configured"]);
        Assert.Equal("false", stateStore.Current.State.Settings["openai.enabled"]);
    }
}
