using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public enum AgentTextFieldWriteStatus
{
    Succeeded,
    MissingSelection,
    ReadOnly,
    TargetChanged,
    Secure,
    UipiBlocked,
    InputFailed,
}

public interface IAgentTextFieldGateway
{
    Task<AgentTextFieldWriteStatus> InsertAsync(string text, CancellationToken cancellationToken);

    Task<AgentTextFieldWriteStatus> ReplaceSelectionAsync(string text, CancellationToken cancellationToken);
}

public interface IAgentTextFieldGatewayFactory
{
    IAgentTextFieldGateway Create(SelectionSnapshot? selection);
}

public sealed class BuiltinAgentTextFieldToolHost
{
    private readonly AgentContextSnapshot context;
    private readonly IAgentTextFieldGateway gateway;

    public BuiltinAgentTextFieldToolHost(
        AgentContextSnapshot context,
        IAgentTextFieldGateway gateway)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.gateway = gateway ?? throw new ArgumentNullException(nameof(gateway));
    }

    public async Task<AgentToolResult> ExecuteAsync(
        AgentToolCall call,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        if (!TryString(call.Arguments, "action", out var action))
        {
            return AgentToolResult.Failure(call.Name, "missing_action");
        }
        return action switch
        {
            "read_selection" => ReadSelection(call),
            "read_all" => ReadAll(call),
            "insert" => await WriteAsync(call, insert: true, cancellationToken).ConfigureAwait(false),
            "replace_selection" => await WriteAsync(call, insert: false, cancellationToken).ConfigureAwait(false),
            _ => AgentToolResult.Failure(call.Name, "unsupported_text_field_action"),
        };
    }

    private AgentToolResult ReadSelection(AgentToolCall call) =>
        string.IsNullOrWhiteSpace(context.SelectedText)
            ? AgentToolResult.Failure(call.Name, "missing_selection")
            : AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new
            {
                action = "read_selection",
                text = context.SelectedText,
                untrusted = true,
            }));

    private AgentToolResult ReadAll(AgentToolCall call) =>
        string.IsNullOrWhiteSpace(context.FocusedInputText)
            ? AgentToolResult.Failure(call.Name, "missing_input_context")
            : AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new
            {
                action = "read_all",
                text = context.FocusedInputText,
                untrusted = true,
            }));

    private async Task<AgentToolResult> WriteAsync(
        AgentToolCall call,
        bool insert,
        CancellationToken cancellationToken)
    {
        if (!TryStringValue(call.Arguments, "text", out var text) || string.IsNullOrWhiteSpace(text))
        {
            return AgentToolResult.Failure(call.Name, "missing_text");
        }
        if (context.Selection is null)
        {
            return AgentToolResult.Failure(call.Name, "missing_selection");
        }
        var status = insert
            ? await gateway.InsertAsync(text, cancellationToken).ConfigureAwait(false)
            : await gateway.ReplaceSelectionAsync(text, cancellationToken).ConfigureAwait(false);
        return Result(call.Name, insert ? "insert" : "replace_selection", status);
    }

    private static AgentToolResult Result(
        string toolName,
        string action,
        AgentTextFieldWriteStatus status) => status switch
        {
            AgentTextFieldWriteStatus.Succeeded => AgentToolResult.Success(toolName,
                JsonSerializer.SerializeToElement(new { action })),
            AgentTextFieldWriteStatus.MissingSelection => AgentToolResult.Failure(toolName, "missing_selection"),
            AgentTextFieldWriteStatus.ReadOnly => AgentToolResult.Failure(toolName, "readonly_text_field"),
            AgentTextFieldWriteStatus.TargetChanged => AgentToolResult.Failure(toolName, "target_changed"),
            AgentTextFieldWriteStatus.Secure => AgentToolResult.Failure(toolName, "secure_text_field"),
            AgentTextFieldWriteStatus.UipiBlocked => AgentToolResult.Failure(toolName, "uipi_blocked"),
            AgentTextFieldWriteStatus.InputFailed => AgentToolResult.Failure(toolName, "text_field_failed"),
            _ => throw new ArgumentOutOfRangeException(nameof(status), status, null),
        };

    private static bool TryString(JsonElement arguments, string name, out string value) =>
        TryStringValue(arguments, name, out value) && !string.IsNullOrWhiteSpace(value);

    private static bool TryStringValue(JsonElement arguments, string name, out string value)
    {
        value = string.Empty;
        if (arguments.ValueKind != JsonValueKind.Object
            || !arguments.TryGetProperty(name, out var property)
            || property.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        value = property.GetString() ?? string.Empty;
        return true;
    }
}
