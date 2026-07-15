using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public interface IAgentOutputClipboard
{
    bool TryCopy(string text);
}

public interface IAgentOutputSummaryPresenter
{
    void ShowSummary(string? text);
}

/// <summary>Optional UI capability for the successful copy branch. Keeping it
/// separate preserves the existing output-summary contract used by headless
/// callers and tests.</summary>
public interface IAgentOutputStatusPresenter
{
    void ShowCopied();
}

public enum AgentComposeOutputStatus
{
    Copied,
    Summarized,
    CopyFailed,
    Failed,
}

public sealed record AgentComposeOutputResult(
    AgentComposeOutputStatus Status,
    string? SafeErrorCode = null);

/// <summary>Applies the Agent final-output policy at the final host boundary.
/// It never injects text or submits forms: no-side-effect answers are copied,
/// while successful side effects receive only a summary presentation.</summary>
public sealed class AgentComposeOutputCoordinator
{
    private readonly IAgentOutputClipboard clipboard;
    private readonly IAgentOutputSummaryPresenter summary;

    public AgentComposeOutputCoordinator(
        IAgentOutputClipboard clipboard,
        IAgentOutputSummaryPresenter summary)
    {
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));
        this.summary = summary ?? throw new ArgumentNullException(nameof(summary));
    }

    public AgentComposeOutputResult Complete(
        string? finalText,
        IReadOnlyList<AgentToolResult> toolResults)
    {
        var decision = AgentFinalOutputPolicy.Decide(finalText, toolResults);
        return decision.Kind switch
        {
            AgentFinalOutputKind.CopyText when clipboard.TryCopy(decision.Text!) =>
                Copied(),
            AgentFinalOutputKind.CopyText =>
                new(AgentComposeOutputStatus.CopyFailed, "clipboard_copy_failed"),
            AgentFinalOutputKind.ShowSummary => Show(decision.Text),
            AgentFinalOutputKind.Failed => new(AgentComposeOutputStatus.Failed, decision.ErrorCode),
            _ => throw new ArgumentOutOfRangeException(nameof(decision)),
        };
    }

    private AgentComposeOutputResult Show(string? text)
    {
        summary.ShowSummary(text);
        return new(AgentComposeOutputStatus.Summarized);
    }

    private AgentComposeOutputResult Copied()
    {
        if (summary is IAgentOutputStatusPresenter status)
        {
            status.ShowCopied();
        }

        return new(AgentComposeOutputStatus.Copied);
    }
}
