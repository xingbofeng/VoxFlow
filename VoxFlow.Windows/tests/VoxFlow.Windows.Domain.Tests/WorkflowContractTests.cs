using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Domain.Tests;

public sealed class WorkflowContractTests
{
    [Fact]
    public void Workflow_task_kinds_match_the_persisted_contract()
    {
        Assert.Equal(
            [
                WorkflowTaskKind.SelectionTranslation,
                WorkflowTaskKind.SelectionSummary,
                WorkflowTaskKind.AgentCompose,
            ],
            Enum.GetValues<WorkflowTaskKind>());

        Assert.Equal(
            ["\"selectionTranslation\"", "\"selectionSummary\"", "\"agentCompose\""],
            Enum.GetValues<WorkflowTaskKind>()
                .Select(value => JsonSerializer.Serialize(value, DomainJson.Options)));
    }

    [Fact]
    public void Workflow_task_stages_match_the_persisted_contract()
    {
        Assert.Equal(
            [
                WorkflowTaskStage.CapturingSelection,
                WorkflowTaskStage.Recording,
                WorkflowTaskStage.Transcribing,
                WorkflowTaskStage.CollectingContext,
                WorkflowTaskStage.Processing,
                WorkflowTaskStage.WaitingForUser,
                WorkflowTaskStage.Operating,
                WorkflowTaskStage.Outputting,
                WorkflowTaskStage.Completed,
            ],
            Enum.GetValues<WorkflowTaskStage>());
    }

    [Fact]
    public void Workflow_task_statuses_match_the_persisted_contract()
    {
        Assert.Equal(
            [
                WorkflowTaskStatus.Pending,
                WorkflowTaskStatus.Running,
                WorkflowTaskStatus.PartiallyCompleted,
                WorkflowTaskStatus.Completed,
                WorkflowTaskStatus.Failed,
                WorkflowTaskStatus.Cancelled,
                WorkflowTaskStatus.Interrupted,
            ],
            Enum.GetValues<WorkflowTaskStatus>());
    }

    [Fact]
    public void Interactive_workflow_kinds_include_dictation_without_persisting_it_as_a_workflow_task()
    {
        Assert.Equal(
            [
                InteractiveWorkflowKind.Dictation,
                InteractiveWorkflowKind.SelectionTranslation,
                InteractiveWorkflowKind.SelectionSummary,
                InteractiveWorkflowKind.AgentCompose,
                InteractiveWorkflowKind.Screenshot,
            ],
            Enum.GetValues<InteractiveWorkflowKind>());
        Assert.DoesNotContain(
            "dictation",
            Enum.GetValues<WorkflowTaskKind>()
                .Select(value => JsonSerializer.Serialize(value, DomainJson.Options)));
        Assert.DoesNotContain(
            "screenshot",
            Enum.GetValues<WorkflowTaskKind>()
                .Select(value => JsonSerializer.Serialize(value, DomainJson.Options)));
    }
}
