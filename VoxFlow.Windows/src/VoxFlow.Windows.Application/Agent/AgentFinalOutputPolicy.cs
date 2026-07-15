using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public enum AgentFinalOutputKind { CopyText, ShowSummary, Failed }

public sealed record AgentFinalOutputDecision(AgentFinalOutputKind Kind, string? Text, string? ErrorCode);

public static class AgentFinalOutputPolicy
{
    private static readonly HashSet<string> AlwaysSideEffectingTools = new(StringComparer.Ordinal)
    {
        "write_file", "edit_file", "notebook_edit", "keyboard", "open_url"
    };

    public static AgentFinalOutputDecision Decide(string? finalText, IReadOnlyList<AgentToolResult> results)
    {
        ArgumentNullException.ThrowIfNull(results);
        var hasSideEffect = results.Any(result => result.Ok && IsSideEffecting(result));
        if (string.IsNullOrWhiteSpace(finalText))
        {
            return hasSideEffect
                ? new(AgentFinalOutputKind.ShowSummary, null, null)
                : new(AgentFinalOutputKind.Failed, null, "missing_completion");
        }
        return hasSideEffect
            ? new(AgentFinalOutputKind.ShowSummary, finalText, null)
            : new(AgentFinalOutputKind.CopyText, finalText, null);
    }

    private static bool IsSideEffecting(AgentToolResult result)
    {
        if (AlwaysSideEffectingTools.Contains(result.ToolName))
        {
            return true;
        }

        var action = Action(result);
        return result.ToolName switch
        {
            "clipboard" => string.Equals(action, "write_text", StringComparison.Ordinal),
            "text_field" => action is "insert" or "replace_selection",
            "http_request" => !string.Equals(action, "GET", StringComparison.OrdinalIgnoreCase),
            _ => false,
        };
    }

    private static string? Action(AgentToolResult result) =>
        result.Result is { ValueKind: System.Text.Json.JsonValueKind.Object } value
        && value.TryGetProperty("action", out var action)
            ? action.GetString()
            : null;
}
