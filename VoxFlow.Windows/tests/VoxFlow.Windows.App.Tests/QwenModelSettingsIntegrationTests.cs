using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class QwenModelSettingsIntegrationTests
{
    [Fact]
    public void Audited_provenance_projects_undownloaded_Qwen_cards_as_visible_but_not_selectable()
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
        var projection = Assert.IsType<QwenModelEntryPointProjection>(
            (object)composition.QwenModels);

        Assert.Equal(2, projection.Current.Settings.Count);
        Assert.Same(projection.Current.Settings, projection.Current.Home);
        Assert.Same(projection.Current.Settings, projection.Current.Menu);
        Assert.All(projection.Current.Settings, card =>
        {
            Assert.False(card.IsReady);
            Assert.False(card.IsSelectable);
            Assert.Equal(VoxFlow.Windows.Domain.ModelInstallPhase.NotDownloaded, card.Phase);
            Assert.Null(card.ErrorCode);
        });
    }
}
