using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

/// <summary>Small platform boundary for the text-only Agent clipboard tool.
/// Clipboard contents are returned only to the current model turn and never
/// placed in a trace by this host.</summary>
public interface IAgentClipboardTextGateway
{
    string? ReadText();

    void WriteText(string text);
}

public sealed class BuiltinAgentClipboardToolHost
{
    private readonly IAgentClipboardTextGateway clipboard;

    public BuiltinAgentClipboardToolHost(IAgentClipboardTextGateway clipboard) =>
        this.clipboard = clipboard ?? throw new ArgumentNullException(nameof(clipboard));

    public Task<AgentToolResult> ExecuteAsync(
        AgentToolCall call,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        cancellationToken.ThrowIfCancellationRequested();
        if (call.Arguments.ValueKind != JsonValueKind.Object)
        {
            return Task.FromResult(AgentToolResult.Failure(call.Name, "invalid_arguments"));
        }
        if (call.Arguments.TryGetProperty("image", out _)
            || call.Arguments.TryGetProperty("path", out _))
        {
            return Task.FromResult(AgentToolResult.Failure(
                call.Name, "unsupported_clipboard_payload"));
        }
        if (!call.Arguments.TryGetProperty("action", out var actionProperty)
            || actionProperty.ValueKind != JsonValueKind.String)
        {
            return Task.FromResult(AgentToolResult.Failure(call.Name, "missing_action"));
        }

        var action = actionProperty.GetString();
        try
        {
            return Task.FromResult(action switch
            {
                "read_text" => Read(call),
                "write_text" => Write(call),
                _ => AgentToolResult.Failure(call.Name, "unsupported_clipboard_action"),
            });
        }
        catch
        {
            return Task.FromResult(AgentToolResult.Failure(call.Name, "clipboard_failure"));
        }
    }

    private AgentToolResult Read(AgentToolCall call) => AgentToolResult.Success(
        call.Name,
        JsonSerializer.SerializeToElement(new
        {
            action = "read_text",
            text = clipboard.ReadText(),
            untrusted = true,
        }));

    private AgentToolResult Write(AgentToolCall call)
    {
        if (!call.Arguments.TryGetProperty("text", out var textProperty)
            || textProperty.ValueKind != JsonValueKind.String)
        {
            return AgentToolResult.Failure(call.Name, "missing_text");
        }

        clipboard.WriteText(textProperty.GetString() ?? string.Empty);
        return AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new
        {
            action = "write_text",
        }));
    }
}
