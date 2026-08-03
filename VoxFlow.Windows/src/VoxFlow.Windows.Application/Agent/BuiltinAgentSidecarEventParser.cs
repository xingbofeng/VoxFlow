using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public enum BuiltinAgentSidecarParseStatus
{
    Empty,
    Event,
    UnknownEvent,
    UnsupportedSchema,
    Incomplete,
    Invalid,
}

public sealed record BuiltinAgentSidecarParseResult(
    BuiltinAgentSidecarParseStatus Status,
    BuiltinAgentSidecarEvent? Event,
    string? SafeMessage = null);

/// <summary>
/// Parses one complete JSONL event without retaining raw stdout. Unknown and
/// malformed input is classified for process lifecycle handling, never echoed
/// into diagnostics because it may contain model, tool, or provider content.
/// </summary>
public static class BuiltinAgentSidecarEventParser
{
    private static readonly HashSet<string> KnownEvents = new(StringComparer.Ordinal)
    {
        "runStarted",
        "turnStarted",
        "modelDelta",
        "toolRequested",
        "toolResolved",
        "turnCompleted",
        "error",
    };

    public static BuiltinAgentSidecarParseResult ParseLine(string line)
    {
        ArgumentNullException.ThrowIfNull(line);
        if (string.IsNullOrWhiteSpace(line))
        {
            return new(BuiltinAgentSidecarParseStatus.Empty, null);
        }

        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(line);
        }
        catch (JsonException exception) when (IsIncomplete(exception, line))
        {
            return new(BuiltinAgentSidecarParseStatus.Incomplete, null);
        }
        catch (JsonException)
        {
            return new(BuiltinAgentSidecarParseStatus.Invalid, null, "invalid_jsonl_event");
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("event", out var eventKind)
                || eventKind.ValueKind != JsonValueKind.String)
            {
                return new(BuiltinAgentSidecarParseStatus.Invalid, null, "event_required");
            }

            var name = eventKind.GetString();
            if (string.IsNullOrWhiteSpace(name) || !KnownEvents.Contains(name))
            {
                return new(BuiltinAgentSidecarParseStatus.UnknownEvent, null, "unknown_event");
            }

            try
            {
                var parsed = JsonSerializer.Deserialize<BuiltinAgentSidecarEvent>(
                    root.GetRawText(),
                    DomainJson.Options);
                if (parsed is null || !IsValid(parsed))
                {
                    return new(BuiltinAgentSidecarParseStatus.Invalid, null, "invalid_event_contract");
                }
                if (parsed.SchemaCompatibility != SchemaCompatibility.Current)
                {
                    return new(BuiltinAgentSidecarParseStatus.UnsupportedSchema, null, "unsupported_schema_version");
                }
                return new(BuiltinAgentSidecarParseStatus.Event, parsed);
            }
            catch (JsonException)
            {
                return new(BuiltinAgentSidecarParseStatus.Invalid, null, "invalid_event_contract");
            }
        }
    }

    private static bool IsValid(BuiltinAgentSidecarEvent sidecarEvent) => sidecarEvent.Event switch
    {
        "runStarted" => true,
        "turnStarted" => sidecarEvent.Step is > 0,
        "modelDelta" => sidecarEvent.Text is not null,
        "toolRequested" => sidecarEvent.ToolCall is not null,
        "toolResolved" => !string.IsNullOrWhiteSpace(sidecarEvent.ToolName)
                          && sidecarEvent.Result is not null,
        "turnCompleted" => sidecarEvent.Summary is not null,
        "error" => !string.IsNullOrWhiteSpace(sidecarEvent.Reason),
        _ => false,
    };

    private static bool IsIncomplete(JsonException exception, string line) =>
        exception.BytePositionInLine >= line.Length - 1
        || line.TrimEnd().EndsWith('{')
        || line.TrimEnd().EndsWith('"');
}
