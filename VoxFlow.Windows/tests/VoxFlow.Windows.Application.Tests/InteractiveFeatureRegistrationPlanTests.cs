using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class InteractiveFeatureRegistrationPlanTests
{
    [Fact]
    public void Disabled_is_the_default_and_produces_no_registrations()
    {
        var flags = WindowsInteractiveFeatureFlags.Disabled;
        var plan = InteractiveFeatureRegistrationPlan.Create(flags);

        Assert.False(flags.SelectionTransformEnabled);
        Assert.False(flags.BuiltinAgentEnabled);
        Assert.False(flags.AnyEnabled);
        Assert.Empty(plan.WorkflowKinds);
        Assert.Empty(plan.HotkeyActionIds);
        Assert.Empty(plan.TrayCommandIds);
        Assert.False(plan.RequiresWorkflowDatabase);
    }

    [Fact]
    public void Disabled_dependency_gate_never_invokes_feature_factories()
    {
        var gate = new InteractiveFeatureDependencyGate(
            WindowsInteractiveFeatureFlags.Disabled);
        var selectionCalls = 0;
        var agentCalls = 0;

        var selection = gate.CreateSelectionDependency(() =>
        {
            selectionCalls++;
            return new object();
        });
        var agent = gate.CreateAgentDependency(() =>
        {
            agentCalls++;
            return new object();
        });

        Assert.Null(selection);
        Assert.Null(agent);
        Assert.Equal(0, selectionCalls);
        Assert.Equal(0, agentCalls);
    }

    [Fact]
    public void Enabled_plan_contains_only_the_approved_workflows_and_entry_ids()
    {
        var plan = InteractiveFeatureRegistrationPlan.Create(
            new WindowsInteractiveFeatureFlags(
                selectionTransformEnabled: true,
                builtinAgentEnabled: true));

        Assert.Equal(
            [
                InteractiveWorkflowKind.SelectionTranslation,
                InteractiveWorkflowKind.SelectionSummary,
                InteractiveWorkflowKind.AgentCompose,
            ],
            plan.WorkflowKinds);
        Assert.Equal(
            ["selection.translate", "selection.summary", "agent.compose"],
            plan.HotkeyActionIds);
        Assert.Equal(
            ["selection.translate", "selection.summary", "agent.compose"],
            plan.TrayCommandIds);
        Assert.True(plan.RequiresWorkflowDatabase);
    }
}
