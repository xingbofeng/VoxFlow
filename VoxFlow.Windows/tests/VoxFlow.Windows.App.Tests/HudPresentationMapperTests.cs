using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class HudPresentationMapperTests
{
    [Fact]
    public void Preparing_recording_partial_and_waiting_final_map_to_distinct_hud_states()
    {
        var machine = new DictationStateMachine();
        var generation = Guid.NewGuid();
        machine.Begin(generation);

        var preparing = HudPresentationMapper.Map(machine.Snapshot, HudLiveContext.Empty);
        Assert.Equal(HudPresentationKind.Preparing, preparing.Kind);
        Assert.True(preparing.IsVisible);
        Assert.True(preparing.ShowsSpinner);
        Assert.False(preparing.ShowsWaveform);

        machine.Prepared();
        var recording = HudPresentationMapper.Map(
            machine.Snapshot,
            new HudLiveContext(PartialText: "partial words"));
        Assert.Equal(HudPresentationKind.Recording, recording.Kind);
        Assert.Equal("partial words", recording.Text);
        Assert.True(recording.ShowsWaveform);
        Assert.False(recording.ShowsSpinner);
        Assert.Equal(2, recording.MaximumTextLines);

        machine.StopRecording();
        var waiting = HudPresentationMapper.Map(
            machine.Snapshot,
            new HudLiveContext(PartialText: "latest partial"));
        Assert.Equal(HudPresentationKind.WaitingForFinal, waiting.Kind);
        Assert.Equal("latest partial", waiting.Text);
        Assert.True(waiting.ShowsSpinner);
    }

    [Fact]
    public void Llm_stream_writing_and_completed_states_keep_the_latest_authoritative_text()
    {
        var machine = ProcessingMachine(out var generation);

        var processing = HudPresentationMapper.Map(
            machine.Snapshot,
            new HudLiveContext(LlmStreamingText: "improved stream"));
        Assert.Equal(HudPresentationKind.Processing, processing.Kind);
        Assert.Equal("improved stream", processing.Text);
        Assert.Equal(HudStatusChip.Improving, processing.StatusChip);
        Assert.True(processing.ShowsSpinner);

        Assert.True(machine.TryProcessingCompleted(generation, "improved final"));
        var writing = HudPresentationMapper.Map(machine.Snapshot, HudLiveContext.Empty);
        Assert.Equal(HudPresentationKind.Writing, writing.Kind);
        Assert.Equal("improved final", writing.Text);
        Assert.Equal(HudStatusChip.Writing, writing.StatusChip);

        Assert.True(machine.TryOutputCompleted(
            generation,
            new OutputResult(OutputResultKind.Inserted)));
        var completed = HudPresentationMapper.Map(machine.Snapshot, HudLiveContext.Empty);
        Assert.Equal(HudPresentationKind.Completed, completed.Kind);
        Assert.Equal("improved final", completed.Text);
        Assert.Equal(HudStatusChip.Completed, completed.StatusChip);
        Assert.Equal(TimeSpan.FromSeconds(10), completed.AutoDismissAfter);
        Assert.False(completed.ShowsSpinner);
    }

    [Fact]
    public void Failed_state_exposes_only_safe_error_classification()
    {
        var machine = new DictationStateMachine();
        var generation = Guid.NewGuid();
        machine.Begin(generation);
        Assert.True(machine.TryFail(
            generation,
            new VoxFlowError(VoxFlowErrorCode.AuthenticationFailed, AsrProviderId.TencentCloud)));

        var failed = HudPresentationMapper.Map(machine.Snapshot, HudLiveContext.Empty);

        Assert.Equal(HudPresentationKind.Failed, failed.Kind);
        Assert.Equal(HudStatusChip.Failed, failed.StatusChip);
        Assert.Equal(VoxFlowErrorCode.AuthenticationFailed, failed.ErrorCode);
        Assert.Equal(TimeSpan.FromSeconds(4), failed.AutoDismissAfter);
        Assert.Null(failed.Text);
    }

    [Fact]
    public void Temporary_action_overrides_idle_or_session_presentation_then_auto_dismisses()
    {
        var action = new HudTransientAction(
            HudActionKind.Copied,
            "copied output",
            TimeSpan.FromSeconds(2));

        var snapshot = HudPresentationMapper.Map(
            DictationSnapshot.Idle,
            new HudLiveContext(TransientAction: action));

        Assert.Equal(HudPresentationKind.TransientAction, snapshot.Kind);
        Assert.Equal(HudStatusChip.Copied, snapshot.StatusChip);
        Assert.Equal("copied output", snapshot.Text);
        Assert.Equal(TimeSpan.FromSeconds(2), snapshot.AutoDismissAfter);
        Assert.True(snapshot.IsVisible);
    }

    [Fact]
    public void Idle_without_a_temporary_action_is_hidden()
    {
        var snapshot = HudPresentationMapper.Map(
            DictationSnapshot.Idle,
            HudLiveContext.Empty);

        Assert.Equal(HudPresentationKind.Hidden, snapshot.Kind);
        Assert.False(snapshot.IsVisible);
        Assert.Null(snapshot.Text);
    }

    private static DictationStateMachine ProcessingMachine(out Guid generation)
    {
        var machine = new DictationStateMachine();
        generation = Guid.NewGuid();
        machine.Begin(generation);
        machine.Prepared();
        machine.StopRecording();
        Assert.True(machine.TryAcceptFinal(generation, "authoritative ASR"));
        return machine;
    }
}
