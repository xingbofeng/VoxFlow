using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class ModelInstallTransitionTests
{
    [Fact]
    public void Happy_path_installation_transitions_are_legal()
    {
        ModelInstallPhase[] phases =
        [
            ModelInstallPhase.NotDownloaded,
            ModelInstallPhase.Queued,
            ModelInstallPhase.Downloading,
            ModelInstallPhase.Verifying,
            ModelInstallPhase.Installing,
            ModelInstallPhase.Prewarming,
            ModelInstallPhase.CanaryTesting,
            ModelInstallPhase.Ready,
        ];

        foreach (var transition in phases.Zip(phases.Skip(1)))
        {
            Assert.True(ModelInstallTransitions.CanMove(transition.First, transition.Second));
        }
    }

    [Fact]
    public void Pause_retry_and_delete_transitions_are_explicit()
    {
        Assert.True(ModelInstallTransitions.CanMove(
            ModelInstallPhase.Downloading,
            ModelInstallPhase.Paused));
        Assert.True(ModelInstallTransitions.CanMove(
            ModelInstallPhase.Paused,
            ModelInstallPhase.Downloading));
        Assert.True(ModelInstallTransitions.CanMove(
            ModelInstallPhase.Failed,
            ModelInstallPhase.Queued));
        Assert.True(ModelInstallTransitions.CanMove(
            ModelInstallPhase.Ready,
            ModelInstallPhase.Deleting));
        Assert.True(ModelInstallTransitions.CanMove(
            ModelInstallPhase.Deleting,
            ModelInstallPhase.NotDownloaded));
    }

    [Theory]
    [InlineData(ModelInstallPhase.Ready, ModelInstallPhase.Downloading)]
    [InlineData(ModelInstallPhase.NotDownloaded, ModelInstallPhase.Ready)]
    [InlineData(ModelInstallPhase.Deleting, ModelInstallPhase.Installing)]
    [InlineData(ModelInstallPhase.Downloading, ModelInstallPhase.Ready)]
    public void Invalid_model_installation_transitions_are_rejected(
        ModelInstallPhase current,
        ModelInstallPhase next)
    {
        Assert.False(ModelInstallTransitions.CanMove(current, next));
        Assert.Throws<InvalidOperationException>(() =>
            ModelInstallTransitions.EnsureCanMove(current, next));
    }
}
