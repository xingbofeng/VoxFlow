using VoxFlow.Windows.App.Composition;
using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Tests;

public sealed class HudDictationProgressSinkTests
{
    [Fact]
    public void Recording_partial_is_dispatched_as_visible_HUD_text()
    {
        HudPresentationSnapshot? presented = null;
        var sink = new HudDictationProgressSink(
            action => action(),
            snapshot => presented = snapshot);
        var state = new DictationStateMachine();
        state.Begin(Guid.NewGuid());
        state.Prepared();

        sink.Publish(new DictationProgressUpdate(Snapshot: state.Snapshot));
        sink.Publish(new DictationProgressUpdate(PartialText: "正在听"));

        Assert.NotNull(presented);
        Assert.Equal(HudPresentationKind.Recording, presented.Kind);
        Assert.Equal("正在听", presented.Text);
        Assert.True(presented.IsVisible);
    }

    [Theory]
    [InlineData(DictationGuidance.ConfigureAsr, VoxFlowErrorCode.AsrNotConfigured)]
    [InlineData(DictationGuidance.PrepareSelectedProvider, VoxFlowErrorCode.ModelNotReady)]
    public void Provider_guidance_is_visible_instead_of_silently_ignored(
        DictationGuidance guidance,
        VoxFlowErrorCode expectedError)
    {
        HudPresentationSnapshot? presented = null;
        var sink = new HudDictationProgressSink(
            action => action(),
            snapshot => presented = snapshot);

        sink.Publish(new DictationProgressUpdate(Guidance: guidance));

        Assert.NotNull(presented);
        Assert.Equal(HudPresentationKind.Failed, presented.Kind);
        Assert.Equal(expectedError, presented.ErrorCode);
        Assert.True(presented.IsVisible);
        Assert.False(string.IsNullOrWhiteSpace(presented.Text));
    }

    [Fact]
    public void Stream_preview_can_hide_partial_text_and_reports_phase_changes()
    {
        HudPresentationSnapshot? presented = null;
        var phases = new List<DictationPhase>();
        var sink = new HudDictationProgressSink(
            action => action(),
            snapshot => presented = snapshot,
            showPartialText: () => false,
            phaseChanged: phases.Add);
        var state = new DictationStateMachine();
        state.Begin(Guid.NewGuid());
        state.Prepared();

        sink.Publish(new DictationProgressUpdate(Snapshot: state.Snapshot));
        sink.Publish(new DictationProgressUpdate(PartialText: "should stay private"));

        Assert.NotNull(presented);
        Assert.Equal(HudPresentationKind.Recording, presented.Kind);
        Assert.NotEqual("should stay private", presented.Text);
        Assert.Contains(DictationPhase.Recording, phases);
    }
}
