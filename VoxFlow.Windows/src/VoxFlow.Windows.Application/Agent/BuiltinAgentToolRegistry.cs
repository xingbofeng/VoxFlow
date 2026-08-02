using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

public enum BuiltinAgentToolArgumentKind
{
    String,
    Integer,
    Boolean,
    Object,
    Array,
}

/// <summary>
/// A host-side mirror of a Rust sidecar function schema. The individual tool
/// hosts retain their semantic and authorization validation; this contract
/// rejects malformed JSONL calls before they reach those hosts.
/// </summary>
public sealed class BuiltinAgentToolSchema
{
    internal BuiltinAgentToolSchema(
        string name,
        IReadOnlySet<string> requiredParameters,
        IReadOnlyDictionary<string, BuiltinAgentToolArgumentKind> parameters)
    {
        Name = name;
        RequiredParameters = requiredParameters;
        Parameters = parameters;
    }

    public string Name { get; }

    public IReadOnlySet<string> RequiredParameters { get; }

    public IReadOnlyDictionary<string, BuiltinAgentToolArgumentKind> Parameters { get; }

    public bool TryValidate(AgentToolCall call, out string errorCode)
    {
        ArgumentNullException.ThrowIfNull(call);
        foreach (var required in RequiredParameters)
        {
            if (!call.Arguments.TryGetProperty(required, out _))
            {
                errorCode = "missing_required_argument";
                return false;
            }
        }

        foreach (var property in call.Arguments.EnumerateObject())
        {
            if (!Parameters.TryGetValue(property.Name, out var expectedKind))
            {
                errorCode = "unexpected_argument";
                return false;
            }
            if (!Matches(expectedKind, property.Value.ValueKind))
            {
                errorCode = "invalid_argument_type";
                return false;
            }
        }

        errorCode = string.Empty;
        return true;
    }

    private static bool Matches(BuiltinAgentToolArgumentKind expected, JsonValueKind actual) =>
        expected switch
        {
            BuiltinAgentToolArgumentKind.String => actual == JsonValueKind.String,
            BuiltinAgentToolArgumentKind.Integer => actual == JsonValueKind.Number,
            BuiltinAgentToolArgumentKind.Boolean => actual is JsonValueKind.True or JsonValueKind.False,
            BuiltinAgentToolArgumentKind.Object => actual == JsonValueKind.Object,
            BuiltinAgentToolArgumentKind.Array => actual == JsonValueKind.Array,
            _ => throw new ArgumentOutOfRangeException(nameof(expected), expected, null),
        };
}

public static class BuiltinAgentToolRegistry
{
    private static readonly IReadOnlyDictionary<string, BuiltinAgentToolSchema> Schemas =
        new Dictionary<string, BuiltinAgentToolSchema>(StringComparer.Ordinal)
        {
            ["read_file"] = Define("read_file", ["file_path"],
                ("file_path", BuiltinAgentToolArgumentKind.String),
                ("offset", BuiltinAgentToolArgumentKind.Integer),
                ("char_offset", BuiltinAgentToolArgumentKind.Integer),
                ("limit", BuiltinAgentToolArgumentKind.Integer)),
            ["search_transcriptions"] = Define("search_transcriptions", ["query"],
                ("query", BuiltinAgentToolArgumentKind.String),
                ("date_from", BuiltinAgentToolArgumentKind.String),
                ("date_to", BuiltinAgentToolArgumentKind.String),
                ("limit", BuiltinAgentToolArgumentKind.Integer)),
            ["respond"] = Define("respond", ["mode", "text"],
                ("mode", BuiltinAgentToolArgumentKind.String),
                ("text", BuiltinAgentToolArgumentKind.String),
                ("severity", BuiltinAgentToolArgumentKind.String)),
            ["ask_user_question"] = Define("ask_user_question", ["questions"],
                ("questions", BuiltinAgentToolArgumentKind.Array),
                ("answers", BuiltinAgentToolArgumentKind.Object),
                ("annotations", BuiltinAgentToolArgumentKind.Object),
                ("metadata", BuiltinAgentToolArgumentKind.Object)),
            ["write_file"] = Define("write_file", ["file_path", "content"],
                ("file_path", BuiltinAgentToolArgumentKind.String),
                ("content", BuiltinAgentToolArgumentKind.String)),
            ["edit_file"] = Define("edit_file", ["file_path", "old_string", "new_string"],
                ("file_path", BuiltinAgentToolArgumentKind.String),
                ("old_string", BuiltinAgentToolArgumentKind.String),
                ("new_string", BuiltinAgentToolArgumentKind.String),
                ("replace_all", BuiltinAgentToolArgumentKind.Boolean)),
            ["notebook_edit"] = Define("notebook_edit", ["notebook_path", "new_source"],
                ("notebook_path", BuiltinAgentToolArgumentKind.String),
                ("cell_id", BuiltinAgentToolArgumentKind.String),
                ("new_source", BuiltinAgentToolArgumentKind.String),
                ("cell_type", BuiltinAgentToolArgumentKind.String),
                ("edit_mode", BuiltinAgentToolArgumentKind.String)),
            ["list_files"] = Define("list_files", [],
                ("path", BuiltinAgentToolArgumentKind.String)),
            ["glob_files"] = Define("glob_files", ["pattern"],
                ("pattern", BuiltinAgentToolArgumentKind.String),
                ("path", BuiltinAgentToolArgumentKind.String),
                ("limit", BuiltinAgentToolArgumentKind.Integer)),
            ["grep_files"] = Define("grep_files", ["pattern"],
                ("pattern", BuiltinAgentToolArgumentKind.String),
                ("path", BuiltinAgentToolArgumentKind.String),
                ("glob", BuiltinAgentToolArgumentKind.String),
                ("output_mode", BuiltinAgentToolArgumentKind.String),
                ("-B", BuiltinAgentToolArgumentKind.Integer),
                ("-A", BuiltinAgentToolArgumentKind.Integer),
                ("-C", BuiltinAgentToolArgumentKind.Integer),
                ("context", BuiltinAgentToolArgumentKind.Integer),
                ("-n", BuiltinAgentToolArgumentKind.Boolean),
                ("-i", BuiltinAgentToolArgumentKind.Boolean),
                ("type", BuiltinAgentToolArgumentKind.String),
                ("head_limit", BuiltinAgentToolArgumentKind.Integer),
                ("offset", BuiltinAgentToolArgumentKind.Integer),
                ("multiline", BuiltinAgentToolArgumentKind.Boolean)),
            ["clipboard"] = Define("clipboard", ["action"],
                ("action", BuiltinAgentToolArgumentKind.String),
                ("text", BuiltinAgentToolArgumentKind.String),
                ("image", BuiltinAgentToolArgumentKind.String),
                ("path", BuiltinAgentToolArgumentKind.String)),
            ["keyboard"] = Define("keyboard", ["action"],
                ("action", BuiltinAgentToolArgumentKind.String),
                ("text", BuiltinAgentToolArgumentKind.String),
                ("key", BuiltinAgentToolArgumentKind.String),
                ("keys", BuiltinAgentToolArgumentKind.Array)),
            ["text_field"] = Define("text_field", ["action"],
                ("action", BuiltinAgentToolArgumentKind.String),
                ("text", BuiltinAgentToolArgumentKind.String)),
            ["http_request"] = Define("http_request", ["url"],
                ("url", BuiltinAgentToolArgumentKind.String),
                ("method", BuiltinAgentToolArgumentKind.String),
                ("headers", BuiltinAgentToolArgumentKind.Object),
                ("body", BuiltinAgentToolArgumentKind.String)),
            ["open_url"] = Define("open_url", ["url"],
                ("url", BuiltinAgentToolArgumentKind.String)),
            ["web_fetch"] = Define("web_fetch", ["url", "prompt"],
                ("url", BuiltinAgentToolArgumentKind.String),
                ("prompt", BuiltinAgentToolArgumentKind.String)),
            ["web_search"] = Define("web_search", ["query"],
                ("query", BuiltinAgentToolArgumentKind.String),
                ("allowed_domains", BuiltinAgentToolArgumentKind.Array),
                ("blocked_domains", BuiltinAgentToolArgumentKind.Array),
                ("num_results", BuiltinAgentToolArgumentKind.Integer),
                ("livecrawl", BuiltinAgentToolArgumentKind.String),
                ("search_type", BuiltinAgentToolArgumentKind.String),
                ("context_max_characters", BuiltinAgentToolArgumentKind.Integer)),
        };

    public static IReadOnlySet<string> ApprovedNames => Schemas.Keys.ToHashSet(StringComparer.Ordinal);

    public static IReadOnlyCollection<BuiltinAgentToolSchema> ApprovedSchemas => Schemas.Values.ToArray();

    public static bool IsApproved(string? toolName) =>
        toolName is not null && Schemas.ContainsKey(toolName);

    public static bool TryGetSchema(string? toolName, out BuiltinAgentToolSchema? schema)
    {
        if (toolName is not null && Schemas.TryGetValue(toolName, out var found))
        {
            schema = found;
            return true;
        }

        schema = null;
        return false;
    }

    private static BuiltinAgentToolSchema Define(
        string name,
        IEnumerable<string> required,
        params (string Name, BuiltinAgentToolArgumentKind Kind)[] parameters)
    {
        var parameterMap = parameters.ToDictionary(
            parameter => parameter.Name,
            parameter => parameter.Kind,
            StringComparer.Ordinal);
        var requiredSet = required.ToHashSet(StringComparer.Ordinal);
        if (!requiredSet.IsSubsetOf(parameterMap.Keys))
        {
            throw new InvalidOperationException($"{name} requires a parameter not in its schema.");
        }
        return new BuiltinAgentToolSchema(name, requiredSet, parameterMap);
    }
}
