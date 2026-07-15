using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Hud;

public enum HudPresentationKind
{
    Hidden,
    Preparing,
    Recording,
    WaitingForFinal,
    Processing,
    Writing,
    Completed,
    Failed,
    TransientAction,
    Agent,
}

public enum HudStatusChip
{
    None,
    Preparing,
    Listening,
    Waiting,
    Improving,
    Writing,
    Completed,
    Failed,
    Copied,
    AgentReadingWindow,
    AgentListening,
    AgentTranscribing,
    AgentProcessing,
    AgentOperating,
    AgentWaitingForUser,
    AgentCompleted,
    AgentFailed,
    AgentCopied,
}

/// <summary>Deliberately small, user-facing Agent state vocabulary. Sidecar
/// protocol events and their payloads must never become HUD UI directly.</summary>
public enum HudAgentStage
{
    ReadingWindow,
    Recording,
    Transcribing,
    Processing,
    Operating,
    WaitingForUser,
    Completed,
    Failed,
    Copied,
}

public enum HudPresentationTone
{
    Neutral,
    Active,
    Success,
    Failure,
}

public enum HudActionKind
{
    Copied,
    Completed,
}

public sealed record HudTransientAction
{
    public HudTransientAction(
        HudActionKind kind,
        string? text,
        TimeSpan dismissAfter)
    {
        if (dismissAfter <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(dismissAfter));
        }

        Kind = kind;
        Text = string.IsNullOrWhiteSpace(text) ? null : text;
        DismissAfter = dismissAfter;
    }

    public HudActionKind Kind { get; }

    public string? Text { get; }

    public TimeSpan DismissAfter { get; }
}

public sealed record HudLiveContext(
    string? PartialText = null,
    string? LlmStreamingText = null,
    HudTransientAction? TransientAction = null)
{
    public static HudLiveContext Empty { get; } = new();
}

public sealed record HudPresentationSnapshot(
    HudPresentationKind Kind,
    bool IsVisible,
    string? Text,
    HudStatusChip StatusChip,
    HudPresentationTone Tone,
    bool ShowsWaveform,
    bool ShowsSpinner,
    int MaximumTextLines,
    TimeSpan? AutoDismissAfter,
    VoxFlowErrorCode? ErrorCode,
    HudAgentStage? AgentStage = null);

public static class HudPresentationMapper
{
    private static readonly TimeSpan CompletedDismissDelay = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan FailedDismissDelay = TimeSpan.FromSeconds(4);

    public static HudPresentationSnapshot Map(
        DictationSnapshot source,
        HudLiveContext context)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(context);

        if (context.TransientAction is { } action)
        {
            return Visible(
                HudPresentationKind.TransientAction,
                action.Text,
                action.Kind == HudActionKind.Copied
                    ? HudStatusChip.Copied
                    : HudStatusChip.Completed,
                HudPresentationTone.Success,
                autoDismissAfter: action.DismissAfter);
        }

        return source.Phase switch
        {
            DictationPhase.Idle => new HudPresentationSnapshot(
                HudPresentationKind.Hidden,
                IsVisible: false,
                Text: null,
                HudStatusChip.None,
                HudPresentationTone.Neutral,
                ShowsWaveform: false,
                ShowsSpinner: false,
                MaximumTextLines: 2,
                AutoDismissAfter: null,
                ErrorCode: null),
            DictationPhase.Preparing => Visible(
                HudPresentationKind.Preparing,
                text: null,
                HudStatusChip.Preparing,
                HudPresentationTone.Neutral,
                showsSpinner: true),
            DictationPhase.Recording => Visible(
                HudPresentationKind.Recording,
                Normalize(context.PartialText),
                HudStatusChip.Listening,
                HudPresentationTone.Active,
                showsWaveform: true),
            DictationPhase.WaitingForFinal => Visible(
                HudPresentationKind.WaitingForFinal,
                Normalize(context.PartialText),
                HudStatusChip.Waiting,
                HudPresentationTone.Neutral,
                showsSpinner: true),
            DictationPhase.Processing => Visible(
                HudPresentationKind.Processing,
                Normalize(context.LlmStreamingText) ?? source.AuthoritativeText,
                HudStatusChip.Improving,
                HudPresentationTone.Active,
                showsSpinner: true),
            DictationPhase.Injecting => Visible(
                HudPresentationKind.Writing,
                source.OutputText,
                HudStatusChip.Writing,
                HudPresentationTone.Active,
                showsSpinner: true),
            DictationPhase.Completed => Visible(
                HudPresentationKind.Completed,
                source.OutputText,
                HudStatusChip.Completed,
                HudPresentationTone.Success,
                autoDismissAfter: CompletedDismissDelay),
            DictationPhase.Failed => Visible(
                HudPresentationKind.Failed,
                text: null,
                HudStatusChip.Failed,
                HudPresentationTone.Failure,
                autoDismissAfter: FailedDismissDelay,
                errorCode: source.Error!.Code),
            _ => throw new ArgumentOutOfRangeException(nameof(source), source.Phase, null),
        };
    }

    private static HudPresentationSnapshot Visible(
        HudPresentationKind kind,
        string? text,
        HudStatusChip statusChip,
        HudPresentationTone tone,
        bool showsWaveform = false,
        bool showsSpinner = false,
        TimeSpan? autoDismissAfter = null,
        VoxFlowErrorCode? errorCode = null) => new(
            kind,
            IsVisible: true,
            text,
            statusChip,
            tone,
            showsWaveform,
            showsSpinner,
            MaximumTextLines: 2,
            autoDismissAfter,
            errorCode);

    private static string? Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
