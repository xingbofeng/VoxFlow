using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public enum AgentUserResponseSeverity { Info, Warning, Error }
public sealed record AgentUserResponse(string Text, AgentUserResponseSeverity Severity, bool CopyToClipboard);
public interface IAgentUserResponsePresenter { Task PresentAsync(AgentUserResponse response, CancellationToken cancellationToken); }

public sealed class BuiltinAgentRespondToolHost
{
    private readonly IAgentUserResponsePresenter presenter;
    private readonly IAgentClipboardTextGateway? clipboard;
    public BuiltinAgentRespondToolHost(IAgentUserResponsePresenter presenter, IAgentClipboardTextGateway? clipboard = null)
    { this.presenter = presenter ?? throw new ArgumentNullException(nameof(presenter)); this.clipboard = clipboard; }

    public async Task<AgentToolResult> ExecuteAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        if (!TryString(call.Arguments, "text", out var text)) return AgentToolResult.Failure(call.Name, "missing_text");
        var severity = ParseSeverity(call.Arguments);
        if (severity is null) return AgentToolResult.Failure(call.Name, "invalid_severity");
        var copy = call.Arguments.TryGetProperty("copy", out var copyValue) && copyValue.ValueKind == JsonValueKind.True;
        var copied = false;
        if (copy)
        {
            if (clipboard is null) return AgentToolResult.Failure(call.Name, "clipboard_unavailable");
            try { cancellationToken.ThrowIfCancellationRequested(); clipboard.WriteText(text); copied = true; }
            catch { return AgentToolResult.Failure(call.Name, "clipboard_write_failed"); }
        }
        await presenter.PresentAsync(new AgentUserResponse(text, severity.Value, copy), cancellationToken).ConfigureAwait(false);
        return AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new { kind = "responded", severity = severity.Value.ToString().ToLowerInvariant(), copied }));
    }

    private static AgentUserResponseSeverity? ParseSeverity(JsonElement arguments)
    {
        if (!arguments.TryGetProperty("mode", out var mode) && !arguments.TryGetProperty("severity", out mode)) return AgentUserResponseSeverity.Info;
        if (mode.ValueKind != JsonValueKind.String) return null;
        return mode.GetString()?.ToLowerInvariant() switch { "info" or "status" => AgentUserResponseSeverity.Info, "warning" or "warn" => AgentUserResponseSeverity.Warning, "error" or "refusal" => AgentUserResponseSeverity.Error, _ => null };
    }
    private static bool TryString(JsonElement arguments, string name, out string text)
    { text = string.Empty; return arguments.ValueKind == JsonValueKind.Object && arguments.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(text = value.GetString() ?? string.Empty); }
}
