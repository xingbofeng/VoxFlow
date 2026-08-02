using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;
using System.Text.Json;

namespace VoxFlow.Windows.App.Tests;

public sealed class AgentHudPresentationMapperTests
{
    [Fact]
    public void Dictation_lifecycle_projects_to_the_complete_safe_agent_stage_set()
    {
        var machine = new DictationStateMachine();
        var generation = Guid.NewGuid();

        machine.Begin(generation);
        Assert.Equal(HudAgentStage.ReadingWindow,
            AgentHudPresentationMapper.FromDictation(machine.Snapshot, HudLiveContext.Empty).AgentStage);

        machine.Prepared();
        var recording = AgentHudPresentationMapper.FromDictation(machine.Snapshot, HudLiveContext.Empty);
        Assert.Equal(HudAgentStage.Recording, recording.AgentStage);
        Assert.True(recording.ShowsWaveform);
        Assert.Null(recording.Text);

        machine.StopRecording();
        Assert.Equal(HudAgentStage.Transcribing,
            AgentHudPresentationMapper.FromDictation(machine.Snapshot, HudLiveContext.Empty).AgentStage);

        Assert.True(machine.TryAcceptFinal(generation, "private spoken instruction"));
        var processing = AgentHudPresentationMapper.FromDictation(machine.Snapshot, HudLiveContext.Empty);
        Assert.Equal(HudAgentStage.Processing, processing.AgentStage);
        Assert.Null(processing.Text);
    }

    [Fact]
    public void Sidecar_events_only_expose_known_tool_labels_and_never_payloads()
    {
        var operating = AgentHudPresentationMapper.FromSidecarEvent(new BuiltinAgentSidecarEvent(
            "toolRequested",
            toolCall: ToolCall("read_file", "{\"path\":\"C:\\\\Users\\\\secret.txt\",\"apiKey\":\"sk-test-secret\"}")));
        var unknown = AgentHudPresentationMapper.FromSidecarEvent(new BuiltinAgentSidecarEvent(
            "toolRequested",
            toolCall: ToolCall("unknown_tool", "{\"secret\":\"sk-do-not-show\"}")));
        var waiting = AgentHudPresentationMapper.FromSidecarEvent(new BuiltinAgentSidecarEvent(
            "toolRequested",
            toolCall: ToolCall("ask_user_question", "{}")));

        Assert.Equal(HudAgentStage.Operating, operating.AgentStage);
        Assert.False(string.IsNullOrWhiteSpace(operating.Text));
        Assert.NotEqual("read_file", operating.Text);
        Assert.DoesNotContain("secret", operating.Text!, StringComparison.OrdinalIgnoreCase);
        Assert.Null(unknown.Text);
        Assert.Equal(HudAgentStage.WaitingForUser, waiting.AgentStage);
        Assert.Null(waiting.Text);

        var failed = AgentHudPresentationMapper.FromSidecarEvent(
            new BuiltinAgentSidecarEvent("error", reason: "C:\\private\\failure sk-hidden"));
        Assert.Equal(HudAgentStage.Failed, failed.AgentStage);
        Assert.Null(failed.Text);
    }

    [Fact]
    public void Summary_redacts_secret_path_and_raw_json_before_showing_it()
    {
        var summary = AgentHudPresentationMapper.CompletedSummary(
            "Saved sk-1234567890 to C:\\Users\\Admin\\token.txt; authorization: Bearer secret-value");
        var json = AgentHudPresentationMapper.CompletedSummary("{\"token\":\"sk-should-not-show\"}");

        Assert.Equal(HudAgentStage.Completed, summary.AgentStage);
        Assert.DoesNotContain("sk-1234567890", summary.Text!, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("C:\\Users", summary.Text!, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("secret-value", summary.Text!, StringComparison.OrdinalIgnoreCase);
        Assert.Null(json.Text);
    }

    [Fact]
    public void Agent_terminal_output_is_not_overwritten_by_late_dictation_completion()
    {
        HudPresentationSnapshot? presented = null;
        var sink = new HudDictationProgressSink(
            action => action(),
            snapshot => presented = snapshot,
            isAgentCompose: true);
        var machine = new DictationStateMachine();
        var generation = Guid.NewGuid();
        machine.Begin(generation);
        machine.Prepared();
        machine.StopRecording();
        Assert.True(machine.TryAcceptFinal(generation, "instruction"));

        sink.Publish(new DictationProgressUpdate(Snapshot: machine.Snapshot));
        sink.ShowAgentCopied();
        Assert.True(machine.TryProcessingCompleted(generation, "done"));
        Assert.True(machine.TryOutputCompleted(generation, new OutputResult(OutputResultKind.Copied)));
        sink.Publish(new DictationProgressUpdate(Snapshot: machine.Snapshot));

        Assert.NotNull(presented);
        Assert.Equal(HudAgentStage.Copied, presented.AgentStage);
        Assert.Equal(HudStatusChip.AgentCopied, presented.StatusChip);
    }

    [Theory]
    [InlineData(AgentComposeReadinessStatus.SidecarUnavailable, VoxFlowErrorCode.NativeRuntimeFailure)]
    [InlineData(AgentComposeReadinessStatus.AsrUnavailable, VoxFlowErrorCode.AsrNotConfigured)]
    [InlineData(AgentComposeReadinessStatus.DefaultProviderUnavailable, VoxFlowErrorCode.ProviderFailure)]
    [InlineData(AgentComposeReadinessStatus.AgentCapabilityUnavailable, VoxFlowErrorCode.ProviderFailure)]
    public void Pre_recording_readiness_failure_is_visible_without_a_recording_state(
        AgentComposeReadinessStatus status,
        VoxFlowErrorCode errorCode)
    {
        HudPresentationSnapshot? presented = null;
        var sink = new HudDictationProgressSink(
            action => action(),
            snapshot => presented = snapshot,
            isAgentCompose: true);

        sink.ShowAgentUnavailable(new AgentComposeReadinessResult(status));

        Assert.NotNull(presented);
        Assert.Equal(HudPresentationKind.Agent, presented.Kind);
        Assert.Equal(HudAgentStage.Failed, presented.AgentStage);
        Assert.Equal(errorCode, presented.ErrorCode);
        Assert.True(presented.IsVisible);
        Assert.False(presented.ShowsWaveform);
        Assert.False(string.IsNullOrWhiteSpace(presented.Text));
    }

    private static AgentToolCall ToolCall(string name, string arguments)
    {
        using var document = JsonDocument.Parse(arguments);
        return new AgentToolCall(Guid.NewGuid().ToString("N"), name, document.RootElement.Clone());
    }
}
