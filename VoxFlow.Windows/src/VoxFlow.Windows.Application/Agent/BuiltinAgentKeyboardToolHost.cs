using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public enum AgentKeyboardWriteStatus
{
    Succeeded,
    TargetChanged,
    UipiBlocked,
    InputFailed,
}

public interface IAgentKeyboardGateway
{
    Task<AgentKeyboardWriteStatus> TypeAsync(string text, CancellationToken cancellationToken);

    Task<AgentKeyboardWriteStatus> PressAsync(
        IReadOnlyList<string> keys,
        CancellationToken cancellationToken);
}

public interface IAgentKeyboardGatewayFactory
{
    IAgentKeyboardGateway Create(ForegroundTargetSnapshot target);
}

/// <summary>Validates the Agent keyboard schema before the platform boundary.
/// It deliberately exposes no modifier chords and never accepts a submit key.</summary>
public sealed class BuiltinAgentKeyboardToolHost
{
    private static readonly HashSet<string> ApprovedKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "Escape", "Tab", "Backspace", "Delete", "Left", "Right", "Up", "Down", "Home", "End",
    };

    private readonly IAgentKeyboardGateway keyboard;

    public BuiltinAgentKeyboardToolHost(IAgentKeyboardGateway keyboard) =>
        this.keyboard = keyboard ?? throw new ArgumentNullException(nameof(keyboard));

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
            "type" => await TypeAsync(call, cancellationToken).ConfigureAwait(false),
            "press" => await PressAsync(call, cancellationToken).ConfigureAwait(false),
            _ => AgentToolResult.Failure(call.Name, "unsupported_keyboard_action"),
        };
    }

    private async Task<AgentToolResult> TypeAsync(
        AgentToolCall call,
        CancellationToken cancellationToken)
    {
        if (!TryStringValue(call.Arguments, "text", out var text))
        {
            return AgentToolResult.Failure(call.Name, "missing_text");
        }
        if (text.Contains('\r', StringComparison.Ordinal) || text.Contains('\n', StringComparison.Ordinal))
        {
            return AgentToolResult.Failure(call.Name, "submit_key_not_allowed");
        }

        var status = await keyboard.TypeAsync(text, cancellationToken).ConfigureAwait(false);
        return Result(call.Name, "type", status);
    }

    private async Task<AgentToolResult> PressAsync(
        AgentToolCall call,
        CancellationToken cancellationToken)
    {
        var keys = ReadKeys(call.Arguments);
        if (keys is null || keys.Count == 0)
        {
            return AgentToolResult.Failure(call.Name, "missing_key");
        }
        if (keys.Any(IsSubmitKey))
        {
            return AgentToolResult.Failure(call.Name, "submit_key_not_allowed");
        }
        if (keys.Any(key => !ApprovedKeys.Contains(key)))
        {
            return AgentToolResult.Failure(call.Name, "unsafe_keyboard_key");
        }

        var status = await keyboard.PressAsync(keys, cancellationToken).ConfigureAwait(false);
        return Result(call.Name, "press", status);
    }

    private static AgentToolResult Result(
        string toolName,
        string action,
        AgentKeyboardWriteStatus status) => status switch
        {
            AgentKeyboardWriteStatus.Succeeded => AgentToolResult.Success(toolName,
                JsonSerializer.SerializeToElement(new { action })),
            AgentKeyboardWriteStatus.TargetChanged => AgentToolResult.Failure(toolName, "target_changed"),
            AgentKeyboardWriteStatus.UipiBlocked => AgentToolResult.Failure(toolName, "uipi_blocked"),
            AgentKeyboardWriteStatus.InputFailed => AgentToolResult.Failure(toolName, "keyboard_failed"),
            _ => throw new ArgumentOutOfRangeException(nameof(status), status, null),
        };

    private static bool IsSubmitKey(string key) =>
        key.Equals("Enter", StringComparison.OrdinalIgnoreCase)
        || key.Equals("Return", StringComparison.OrdinalIgnoreCase);

    private static IReadOnlyList<string>? ReadKeys(JsonElement arguments)
    {
        if (TryString(arguments, "key", out var key))
        {
            return [key];
        }
        if (!arguments.TryGetProperty("keys", out var value)
            || value.ValueKind != JsonValueKind.Array)
        {
            return null;
        }
        var keys = new List<string>();
        foreach (var item in value.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(item.GetString()))
            {
                return null;
            }
            keys.Add(item.GetString()!);
        }
        return keys;
    }

    private static bool TryString(JsonElement arguments, string name, out string value)
    {
        value = string.Empty;
        return TryStringValue(arguments, name, out value) && !string.IsNullOrWhiteSpace(value);
    }

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
