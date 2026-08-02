using System.Text.RegularExpressions;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Application.Dictation;
using VoxFlow.Windows.App.Localization;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.App.Hud;

/// <summary>
/// Projects Agent lifecycle events into a compact HUD model. This boundary is
/// intentionally lossy: JSONL text, tool arguments, result payloads and error
/// reasons can contain secrets or local paths, so they are never presented.
/// </summary>
public static partial class AgentHudPresentationMapper
{
    private static readonly TimeSpan CompletedDismissDelay = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan FailedDismissDelay = TimeSpan.FromSeconds(4);

    public static HudPresentationSnapshot ReadingWindow() => Visible(
        HudAgentStage.ReadingWindow,
        HudStatusChip.AgentReadingWindow,
        HudPresentationTone.Neutral,
        showsSpinner: true);

    public static HudPresentationSnapshot FromDictation(
        DictationSnapshot source,
        HudLiveContext context)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(context);

        return source.Phase switch
        {
            DictationPhase.Idle => Hidden(),
            DictationPhase.Preparing => ReadingWindow(),
            DictationPhase.Recording => Visible(
                HudAgentStage.Recording,
                HudStatusChip.AgentListening,
                HudPresentationTone.Active,
                showsWaveform: true),
            DictationPhase.WaitingForFinal => Visible(
                HudAgentStage.Transcribing,
                HudStatusChip.AgentTranscribing,
                HudPresentationTone.Neutral,
                showsSpinner: true),
            DictationPhase.Processing or DictationPhase.Injecting => Visible(
                HudAgentStage.Processing,
                HudStatusChip.AgentProcessing,
                HudPresentationTone.Active,
                showsSpinner: true),
            DictationPhase.Completed => Visible(
                HudAgentStage.Completed,
                HudStatusChip.AgentCompleted,
                HudPresentationTone.Success,
                autoDismissAfter: CompletedDismissDelay),
            DictationPhase.Failed => Visible(
                HudAgentStage.Failed,
                HudStatusChip.AgentFailed,
                HudPresentationTone.Failure,
                autoDismissAfter: FailedDismissDelay,
                errorCode: source.Error?.Code ?? VoxFlowErrorCode.Unknown),
            _ => throw new ArgumentOutOfRangeException(nameof(source), source.Phase, null),
        };
    }

    public static HudPresentationSnapshot FromSidecarEvent(
        BuiltinAgentSidecarEvent runtimeEvent)
    {
        ArgumentNullException.ThrowIfNull(runtimeEvent);

        return runtimeEvent.Event switch
        {
            "toolRequested" when string.Equals(
                runtimeEvent.ToolCall?.Name,
                "ask_user_question",
                StringComparison.Ordinal) => Visible(
                    HudAgentStage.WaitingForUser,
                    HudStatusChip.AgentWaitingForUser,
                    HudPresentationTone.Neutral,
                    showsSpinner: false),
            "toolRequested" or "toolProgress" or "toolResolved" => Visible(
                HudAgentStage.Operating,
                HudStatusChip.AgentOperating,
                HudPresentationTone.Active,
                text: SafeToolDisplayName(runtimeEvent.ToolCall?.Name
                    ?? runtimeEvent.ToolName
                    ?? runtimeEvent.Result?.ToolName),
                showsSpinner: true),
            "error" => Visible(
                HudAgentStage.Failed,
                HudStatusChip.AgentFailed,
                HudPresentationTone.Failure,
                autoDismissAfter: FailedDismissDelay),
            _ => Visible(
                HudAgentStage.Processing,
                HudStatusChip.AgentProcessing,
                HudPresentationTone.Active,
                showsSpinner: true),
        };
    }

    public static HudPresentationSnapshot Copied() => Visible(
        HudAgentStage.Copied,
        HudStatusChip.AgentCopied,
        HudPresentationTone.Success,
        autoDismissAfter: CompletedDismissDelay);

    public static HudPresentationSnapshot CompletedSummary(string? summary) => Visible(
        HudAgentStage.Completed,
        HudStatusChip.AgentCompleted,
        HudPresentationTone.Success,
        text: SafeSummary(summary),
        autoDismissAfter: CompletedDismissDelay);

    private static HudPresentationSnapshot Hidden() => new(
        HudPresentationKind.Hidden,
        IsVisible: false,
        Text: null,
        HudStatusChip.None,
        HudPresentationTone.Neutral,
        ShowsWaveform: false,
        ShowsSpinner: false,
        MaximumTextLines: 2,
        AutoDismissAfter: null,
        ErrorCode: null,
        AgentStage: null);

    private static HudPresentationSnapshot Visible(
        HudAgentStage stage,
        HudStatusChip statusChip,
        HudPresentationTone tone,
        string? text = null,
        bool showsWaveform = false,
        bool showsSpinner = false,
        TimeSpan? autoDismissAfter = null,
        VoxFlowErrorCode? errorCode = null) => new(
            HudPresentationKind.Agent,
            IsVisible: true,
            text,
            statusChip,
            tone,
            showsWaveform,
            showsSpinner,
            MaximumTextLines: 2,
            autoDismissAfter,
            errorCode,
            stage);

    private static string? SafeToolDisplayName(string? toolName) => toolName switch
    {
        "read_file" => L10n.Localize("HudAgentToolReadFile"),
        "search_transcriptions" => L10n.Localize("HudAgentToolSearchTranscriptions"),
        "respond" => L10n.Localize("HudAgentToolRespond"),
        "ask_user_question" => L10n.Localize("HudAgentToolAskUserQuestion"),
        "write_file" => L10n.Localize("HudAgentToolWriteFile"),
        "edit_file" => L10n.Localize("HudAgentToolEditFile"),
        "notebook_edit" => L10n.Localize("HudAgentToolNotebookEdit"),
        "list_files" => L10n.Localize("HudAgentToolListFiles"),
        "glob_files" => L10n.Localize("HudAgentToolGlobFiles"),
        "grep_files" => L10n.Localize("HudAgentToolGrepFiles"),
        "clipboard" => L10n.Localize("HudAgentToolClipboard"),
        "keyboard" => L10n.Localize("HudAgentToolKeyboard"),
        "text_field" => L10n.Localize("HudAgentToolTextField"),
        "http_request" => L10n.Localize("HudAgentToolHttpRequest"),
        "open_url" => L10n.Localize("HudAgentToolOpenUrl"),
        "web_fetch" => L10n.Localize("HudAgentToolWebFetch"),
        "web_search" => L10n.Localize("HudAgentToolWebSearch"),
        _ => null,
    };

    private static string? SafeSummary(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalized = WhitespaceRegex().Replace(value.Trim(), " ");
        if (normalized.StartsWith('{') || normalized.StartsWith('['))
        {
            return null;
        }

        normalized = SecretRegex().Replace(normalized, L10n.Localize("HudAgentRedacted"));
        normalized = PathRegex().Replace(normalized, L10n.Localize("HudAgentPathRemoved"));
        return normalized.Length <= 180 ? normalized : normalized[..177] + "...";
    }

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();

    [GeneratedRegex(@"(?ix)(?:\bsk-[a-z0-9_-]{8,}|\b(?:api[ _-]?key|secret|token|authorization)\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+")]
    private static partial Regex SecretRegex();

    [GeneratedRegex(@"(?ix)(?:[a-z]:\\|/)(?:[^\s,;]+)")]
    private static partial Regex PathRegex();
}
