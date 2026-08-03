using System.Text.Json;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Agent;

/// <summary>Maps the four currently implemented file tools to the same strict
/// workspace/read-before-write services used by the host policy.</summary>
public sealed class BuiltinAgentFileToolHost
{
    private readonly string workspaceRoot;
    private readonly AgentFileReadService reader;
    private readonly AgentFileWriteService writer;
    private readonly AgentFileEditService editor;
    private readonly AgentDirectoryListService directory;
    private readonly AgentFileSearchService search;
    private readonly AgentNotebookEditService notebooks;
    private readonly AgentTranscriptionSearchService? transcriptions;
    private readonly AgentToolAuthorizationPolicy? authorization;

    public BuiltinAgentFileToolHost(
        string workspaceRoot,
        AgentPathPolicy? paths = null,
        IHistoryStore? history = null,
        AgentToolAuthorizationPolicy? authorization = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(workspaceRoot);
        this.workspaceRoot = Path.GetFullPath(workspaceRoot);
        var policy = paths ?? new AgentPathPolicy();
        var reads = new AgentFileReadState();
        reader = new AgentFileReadService(policy, reads);
        writer = new AgentFileWriteService(policy, reads);
        editor = new AgentFileEditService(policy, reads);
        directory = new AgentDirectoryListService(policy);
        search = new AgentFileSearchService(policy);
        notebooks = new AgentNotebookEditService(policy, reads);
        transcriptions = history is null ? null : new AgentTranscriptionSearchService(history);
        this.authorization = authorization;
    }

    public async Task<AgentToolResult> ExecuteAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(call);
        return call.Name switch
        {
            "read_file" => await ReadAsync(call, cancellationToken).ConfigureAwait(false),
            "write_file" => await WriteAsync(call, cancellationToken).ConfigureAwait(false),
            "edit_file" => await EditAsync(call, cancellationToken).ConfigureAwait(false),
            "notebook_edit" => await NotebookEditAsync(call, cancellationToken).ConfigureAwait(false),
            "list_files" => List(call),
            "glob_files" => Glob(call),
            "grep_files" => Grep(call),
            "search_transcriptions" => SearchTranscriptions(call),
            _ => AgentToolResult.Failure(call.Name, "unknown_tool"),
        };
    }

    private async Task<AgentToolResult> ReadAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        // Keep this contract byte-for-byte aligned with builtin_agent_tool_schemas()
        // in agent-cli. The sidecar is the sole schema authority for tool calls.
        if (!TryString(call.Arguments, "file_path", out var path)) return Missing(call, "file_path");
        var lineOffset = ReadOptionalInt(call.Arguments, "offset");
        var charOffset = ReadOptionalInt(call.Arguments, "char_offset");
        var limit = ReadOptionalInt(call.Arguments, "limit");
        var result = await reader.ReadAsync(
            workspaceRoot, path, cancellationToken, lineOffset, charOffset, limit).ConfigureAwait(false);
        return result.Ok
            ? AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new
            {
                content = result.Content,
                fullRead = result.IsFullRead,
                truncated = result.IsTruncated,
                nextLineOffset = result.NextLineOffset,
                nextCharOffset = result.NextCharOffset,
            }))
            : AgentToolResult.Failure(call.Name, result.ErrorCode!);
    }

    private async Task<AgentToolResult> WriteAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        if (!TryString(call.Arguments, "file_path", out var path)) return Missing(call, "file_path");
        if (!TryString(call.Arguments, "content", out var content)) return Missing(call, "content");
        var result = await writer.WriteAsync(workspaceRoot, path, content, cancellationToken).ConfigureAwait(false);
        return result.Ok
            ? AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new { created = result.Created }))
            : AgentToolResult.Failure(call.Name, result.ErrorCode!);
    }

    private async Task<AgentToolResult> EditAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        if (!TryString(call.Arguments, "file_path", out var path)) return Missing(call, "file_path");
        if (!TryString(call.Arguments, "old_string", out var oldText)) return Missing(call, "old_string");
        if (!TryString(call.Arguments, "new_string", out var newText)) return Missing(call, "new_string");
        var replaceAll = call.Arguments.TryGetProperty("replace_all", out var value) && value.ValueKind == JsonValueKind.True;
        var result = await editor.ReplaceAsync(workspaceRoot, path, oldText, newText, replaceAll, cancellationToken).ConfigureAwait(false);
        return result.Ok
            ? AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new { edited = true }))
            : AgentToolResult.Failure(call.Name, result.ErrorCode!);
    }

    private async Task<AgentToolResult> NotebookEditAsync(AgentToolCall call, CancellationToken cancellationToken)
    {
        if (!TryString(call.Arguments, "notebook_path", out var path)) return Missing(call, "notebook_path");
        if (!TryStringValue(call.Arguments, "new_source", out var source)) return Missing(call, "new_source");
        var mode = TryString(call.Arguments, "edit_mode", out var suppliedMode) ? suppliedMode : "replace";
        _ = TryString(call.Arguments, "cell_id", out var cellId);
        _ = TryString(call.Arguments, "cell_type", out var cellType);
        var result = await notebooks.EditAsync(workspaceRoot, path, source, mode,
            string.IsNullOrWhiteSpace(cellId) ? null : cellId,
            string.IsNullOrWhiteSpace(cellType) ? null : cellType,
            cancellationToken).ConfigureAwait(false);
        return result.Ok
            ? AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new
            {
                cell_id = result.CellId,
                cell_type = result.CellType,
                language = result.Language,
                edit_mode = mode,
                notebook_path = path,
                original_file = result.OriginalFile,
                updated_file = result.UpdatedFile,
            }))
            : AgentToolResult.Failure(call.Name, result.ErrorCode!);
    }

    private AgentToolResult List(AgentToolCall call)
    {
        var path = TryString(call.Arguments, "path", out var supplied) ? supplied : ".";
        var result = directory.List(workspaceRoot, path);
        return result.Ok
            ? AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new { entries = result.Entries }))
            : AgentToolResult.Failure(call.Name, result.ErrorCode!);
    }

    private AgentToolResult Glob(AgentToolCall call)
    {
        if (!TryString(call.Arguments, "pattern", out var pattern)) return Missing(call, "pattern");
        var path = TryString(call.Arguments, "path", out var supplied) ? supplied : ".";
        var limit = ReadLimit(call.Arguments);
        var result = search.Glob(workspaceRoot, path, pattern, limit);
        return result.Ok
            ? AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new { files = result.Files, truncated = result.Truncated }))
            : AgentToolResult.Failure(call.Name, result.ErrorCode!);
    }

    private AgentToolResult Grep(AgentToolCall call)
    {
        if (!TryString(call.Arguments, "pattern", out var pattern)) return Missing(call, "pattern");
        var path = TryString(call.Arguments, "path", out var supplied) ? supplied : ".";
        var limit = ReadLimit(call.Arguments, "head_limit");
        var result = search.Grep(workspaceRoot, path, pattern, limit);
        return result.Ok
            ? AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new { matches = result.Matches, truncated = result.Truncated }))
            : AgentToolResult.Failure(call.Name, result.ErrorCode!);
    }

    private AgentToolResult SearchTranscriptions(AgentToolCall call)
    {
        if (!TryString(call.Arguments, "query", out var query)) return Missing(call, "query");
        if (transcriptions is null) return AgentToolResult.Failure(call.Name, "transcription_search_unavailable");
        if (authorization is null || !authorization.AllowsTranscriptionSearch())
        {
            return AgentToolResult.Failure(call.Name, "user_intent_required");
        }
        var dateFrom = TryStringValue(call.Arguments, "date_from", out var from) ? from : null;
        var dateTo = TryStringValue(call.Arguments, "date_to", out var to) ? to : null;
        var limit = ReadHistoryLimit(call.Arguments);
        var result = transcriptions.Search(query, dateFrom, dateTo, limit);
        return result.Ok
            ? AgentToolResult.Success(call.Name, JsonSerializer.SerializeToElement(new { entries = result.Entries }))
            : AgentToolResult.Failure(call.Name, result.ErrorCode!);
    }

    private static AgentToolResult Missing(AgentToolCall call, string field) =>
        AgentToolResult.Failure(call.Name, $"missing_{field}");

    private static bool TryString(JsonElement arguments, string name, out string value)
    {
        value = string.Empty;
        if (arguments.ValueKind != JsonValueKind.Object
            || !arguments.TryGetProperty(name, out var property)
            || property.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        var parsed = property.GetString();
        if (string.IsNullOrWhiteSpace(parsed))
        {
            return false;
        }

        value = parsed;
        return true;
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

    private static int ReadLimit(JsonElement arguments, string name = "limit") =>
        arguments.ValueKind == JsonValueKind.Object
        && arguments.TryGetProperty(name, out var value)
        && value.TryGetInt32(out var limit)
        && limit is >= 1 and <= AgentFileSearchService.MaximumResults
            ? limit
            : AgentFileSearchService.MaximumResults;

    private static int ReadHistoryLimit(JsonElement arguments) =>
        arguments.ValueKind == JsonValueKind.Object
        && arguments.TryGetProperty("limit", out var value)
        && value.TryGetInt32(out var limit)
            ? limit
            : 5;

    private static int? ReadOptionalInt(JsonElement arguments, string name) =>
        arguments.ValueKind == JsonValueKind.Object
        && arguments.TryGetProperty(name, out var value)
        && value.TryGetInt32(out var number)
            ? number
            : null;
}
