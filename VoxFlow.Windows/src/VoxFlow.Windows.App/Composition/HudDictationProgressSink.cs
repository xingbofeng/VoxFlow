using VoxFlow.Windows.App.Hud;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Composition;

public sealed class HudDictationProgressSink : IDictationProgressSink
{
    private readonly Action<Action> dispatch;
    private readonly Action<HudPresentationSnapshot> present;
    private readonly bool isAgentCompose;
    private readonly Action<DictationPhase>? agentPhaseChanged;
    private readonly Func<bool> showPartialText;
    private readonly Action<DictationPhase>? phaseChanged;
    private DictationSnapshot snapshot = new DictationStateMachine().Snapshot;
    private string? partialText;
    private string? processingText;
    private bool agentTerminalPresentationShown;

    public HudDictationProgressSink(
        Action<Action> dispatch,
        Action<HudPresentationSnapshot> present,
        bool isAgentCompose = false,
        Action<DictationPhase>? agentPhaseChanged = null,
        Func<bool>? showPartialText = null,
        Action<DictationPhase>? phaseChanged = null)
    {
        this.dispatch = dispatch ?? throw new ArgumentNullException(nameof(dispatch));
        this.present = present ?? throw new ArgumentNullException(nameof(present));
        this.isAgentCompose = isAgentCompose;
        this.agentPhaseChanged = agentPhaseChanged;
        this.showPartialText = showPartialText ?? (() => true);
        this.phaseChanged = phaseChanged;
    }

    public void Publish(DictationProgressUpdate update)
    {
        ArgumentNullException.ThrowIfNull(update);
        dispatch(() => Apply(update));
    }

    /// <summary>Shows the short target-context acquisition phase before audio
    /// begins. The Agent HUD never displays captured UI text.</summary>
    public void ShowAgentReadingWindow()
    {
        EnsureAgentCompose();
        dispatch(() => present(AgentHudPresentationMapper.ReadingWindow()));
    }

    /// <summary>Receives a normalized sidecar event. Only the safe projection
    /// from <see cref="AgentHudPresentationMapper"/> reaches the WPF view.</summary>
    public void PublishAgentSidecarEvent(BuiltinAgentSidecarEvent runtimeEvent)
    {
        ArgumentNullException.ThrowIfNull(runtimeEvent);
        EnsureAgentCompose();
        dispatch(() =>
        {
            if (!agentTerminalPresentationShown)
            {
                present(AgentHudPresentationMapper.FromSidecarEvent(runtimeEvent));
            }
        });
    }

    public void ShowAgentCopied()
    {
        EnsureAgentCompose();
        dispatch(() =>
        {
            agentTerminalPresentationShown = true;
            present(AgentHudPresentationMapper.Copied());
        });
    }

    public void ShowAgentSummary(string? summary)
    {
        EnsureAgentCompose();
        dispatch(() =>
        {
            agentTerminalPresentationShown = true;
            present(AgentHudPresentationMapper.CompletedSummary(summary));
        });
    }

    /// <summary>Projects the pre-recording Agent dependency gate to the same
    /// HUD used by hotkey and tray starts. No microphone session has started
    /// when this method is called.</summary>
    public void ShowAgentUnavailable(AgentComposeReadinessResult readiness)
    {
        ArgumentNullException.ThrowIfNull(readiness);
        EnsureAgentCompose();
        var (message, errorCode) = readiness.Status switch
        {
            AgentComposeReadinessStatus.SidecarUnavailable =>
                (L10n.Localize("TrayAgentRuntimeUnavailable"), VoxFlowErrorCode.NativeRuntimeFailure),
            AgentComposeReadinessStatus.AsrUnavailable =>
                (OutputFailurePresentation.From(
                    new VoxFlowError(VoxFlowErrorCode.AsrNotConfigured),
                    llmFallback: false).Message,
                    VoxFlowErrorCode.AsrNotConfigured),
            AgentComposeReadinessStatus.DefaultProviderUnavailable or
                AgentComposeReadinessStatus.AgentCapabilityUnavailable =>
                (L10n.Localize("TrayAgentProviderUnavailable"), VoxFlowErrorCode.ProviderFailure),
            AgentComposeReadinessStatus.Ready =>
                throw new ArgumentException("A ready Agent cannot be presented as unavailable.", nameof(readiness)),
            _ => throw new ArgumentOutOfRangeException(nameof(readiness), readiness.Status, null),
        };
        dispatch(() => present(new HudPresentationSnapshot(
            HudPresentationKind.Agent,
            IsVisible: true,
            Text: message,
            HudStatusChip.Failed,
            HudPresentationTone.Failure,
            ShowsWaveform: false,
            ShowsSpinner: false,
            MaximumTextLines: 2,
            AutoDismissAfter: TimeSpan.FromSeconds(4),
            ErrorCode: errorCode,
            AgentStage: HudAgentStage.Failed)));
    }

    private void Apply(DictationProgressUpdate update)
    {
        if (update.Guidance != DictationGuidance.None)
        {
            PresentGuidance(update.Guidance);
            return;
        }

        if (update.Snapshot is not null)
        {
            snapshot = update.Snapshot;
            phaseChanged?.Invoke(snapshot.Phase);
            if (isAgentCompose)
            {
                agentPhaseChanged?.Invoke(snapshot.Phase);
            }
            if (snapshot.Phase is DictationPhase.Idle or DictationPhase.Preparing)
            {
                partialText = null;
                processingText = null;
                if (snapshot.Phase == DictationPhase.Idle)
                {
                    agentTerminalPresentationShown = false;
                }
            }
        }
        if (update.PartialText is not null)
        {
            partialText = showPartialText() ? update.PartialText : null;
        }
        if (update.ProcessingText is not null)
        {
            processingText = update.ProcessingText;
        }

        if (isAgentCompose)
        {
            if (!agentTerminalPresentationShown)
            {
                present(AgentHudPresentationMapper.FromDictation(
                    snapshot,
                    new HudLiveContext(partialText, processingText)));
            }
            return;
        }

        present(HudPresentationMapper.Map(snapshot, new HudLiveContext(partialText, processingText)));
    }

    private void PresentGuidance(DictationGuidance guidance)
    {
        var errorCode = guidance switch
        {
            DictationGuidance.ConfigureAsr => VoxFlowErrorCode.AsrNotConfigured,
            DictationGuidance.PrepareSelectedProvider => VoxFlowErrorCode.ModelNotReady,
            _ => throw new ArgumentOutOfRangeException(nameof(guidance), guidance, null),
        };
        var message = OutputFailurePresentation.From(
            new VoxFlowError(errorCode),
            llmFallback: false).Message;
        present(new HudPresentationSnapshot(
            isAgentCompose ? HudPresentationKind.Agent : HudPresentationKind.Failed,
            IsVisible: true,
            Text: message,
            HudStatusChip.Failed,
            HudPresentationTone.Failure,
            ShowsWaveform: false,
            ShowsSpinner: false,
            MaximumTextLines: 2,
            AutoDismissAfter: TimeSpan.FromSeconds(4),
            ErrorCode: errorCode,
            AgentStage: isAgentCompose ? HudAgentStage.Failed : null));
    }

    private void EnsureAgentCompose()
    {
        if (!isAgentCompose)
        {
            throw new InvalidOperationException("Agent HUD events require an Agent Compose progress sink.");
        }
    }
}
