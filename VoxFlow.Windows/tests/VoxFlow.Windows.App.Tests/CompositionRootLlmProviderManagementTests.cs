using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.App.Tests;

public sealed class CompositionRootLlmProviderManagementTests
{
    [Fact]
    public void Provider_management_is_created_only_for_the_interactive_feature_graph()
    {
        using var directory = new TemporaryDirectory();
        var rootType = typeof(MainWindow).Assembly.GetType(
            "VoxFlow.Windows.App.Composition.WindowsAppCompositionRoot");
        Assert.NotNull(rootType);

        dynamic disabled = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            Path.Combine(directory.Path, "disabled.db"),
            null)!);
        using ((IDisposable)disabled)
        {
            Assert.Null(disabled.LlmProviderManagement);
        }

        dynamic enabled = Assert.IsAssignableFrom<IDisposable>(Activator.CreateInstance(
            rootType,
            Path.Combine(directory.Path, "enabled.db"),
            null,
            new WindowsInteractiveFeatureFlags(
                selectionTransformEnabled: true,
                builtinAgentEnabled: true))!);
        using ((IDisposable)enabled)
        {
            Assert.IsAssignableFrom<ILlmProviderManagementService>(
                enabled.LlmProviderManagement);
        }
    }
}
