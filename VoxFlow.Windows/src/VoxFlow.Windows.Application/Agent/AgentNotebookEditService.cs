using System.Text.Json;
using System.Text.Json.Nodes;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentNotebookEditResult(
    bool Ok,
    string? ErrorCode,
    string? CellId = null,
    string? CellType = null,
    string? Language = null,
    string? OriginalFile = null,
    string? UpdatedFile = null);

/// <summary>Windows port of the macOS notebook_edit contract. It changes only
/// the requested cell fields and preserves all unknown notebook metadata.</summary>
public sealed class AgentNotebookEditService
{
    private readonly AgentPathPolicy paths;
    private readonly AgentFileReadState reads;
    private readonly AgentFileWriteService writer;

    public AgentNotebookEditService(AgentPathPolicy paths, AgentFileReadState reads)
    {
        this.paths = paths ?? throw new ArgumentNullException(nameof(paths));
        this.reads = reads ?? throw new ArgumentNullException(nameof(reads));
        writer = new AgentFileWriteService(paths, reads);
    }

    public async Task<AgentNotebookEditResult> EditAsync(
        string workspaceRoot,
        string notebookPath,
        string newSource,
        string editMode,
        string? cellId,
        string? cellType,
        CancellationToken cancellationToken)
    {
        if (editMode is not ("replace" or "insert" or "delete")) return Fail("invalid_edit_mode");
        var decision = paths.ResolveWorkspacePath(workspaceRoot, notebookPath);
        if (!decision.Allowed) return Fail(decision.ErrorCode!);
        if (!string.Equals(Path.GetExtension(decision.FullPath), ".ipynb", StringComparison.OrdinalIgnoreCase)) return Fail("not_notebook");
        if (!File.Exists(decision.FullPath)) return Fail("file_not_found");
        if (!reads.WasReadUnchanged(decision.FullPath!)) return Fail("file_not_read_or_modified");

        string original;
        try
        {
            original = await File.ReadAllTextAsync(decision.FullPath!, cancellationToken).ConfigureAwait(false);
        }
        catch (IOException) { return Fail("file_unavailable"); }

        JsonObject notebook;
        JsonArray cells;
        try
        {
            notebook = JsonNode.Parse(original) as JsonObject ?? throw new JsonException();
            cells = notebook["cells"] as JsonArray ?? throw new InvalidDataException();
        }
        catch (JsonException) { return Fail("invalid_notebook_json"); }
        catch (InvalidDataException) { return Fail("missing_cells"); }

        var index = ResolveIndex(cells, cellId, editMode);
        if (index.Error is not null) return Fail(index.Error);
        var resolved = index.Value;
        string outputCellId = cellId ?? string.Empty;
        string outputCellType;

        if (editMode == "delete")
        {
            var target = cells[resolved] as JsonObject;
            if (target is null) return Fail("invalid_notebook_cell");
            outputCellType = target["cell_type"]?.GetValue<string>() ?? "code";
            cells.RemoveAt(resolved);
        }
        else if (editMode == "insert")
        {
            if (cellType is not ("code" or "markdown")) return Fail("missing_cell_type");
            var newCell = new JsonObject
            {
                ["cell_type"] = cellType,
                ["metadata"] = new JsonObject(),
                ["source"] = newSource,
            };
            if (ShouldWriteCellIds(notebook))
            {
                outputCellId = Guid.NewGuid().ToString("N")[..12];
                newCell["id"] = outputCellId;
            }
            if (cellType == "code")
            {
                newCell["execution_count"] = null;
                newCell["outputs"] = new JsonArray();
            }
            cells.Insert(resolved, newCell);
            outputCellType = cellType;
        }
        else
        {
            var target = cells[resolved] as JsonObject;
            if (target is null) return Fail("invalid_notebook_cell");
            if (cellType is not null && cellType is not ("code" or "markdown")) return Fail("invalid_cell_type");
            target["source"] = newSource;
            if ((target["cell_type"]?.GetValue<string>() ?? "code") == "code")
            {
                target["execution_count"] = null;
                target["outputs"] = new JsonArray();
            }
            if (cellType is not null) target["cell_type"] = cellType;
            outputCellType = target["cell_type"]?.GetValue<string>() ?? "code";
        }

        var updated = notebook.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        var write = await writer.WriteAsync(workspaceRoot, notebookPath, updated, cancellationToken).ConfigureAwait(false);
        if (!write.Ok) return Fail(write.ErrorCode!);
        return new(true, null, string.IsNullOrWhiteSpace(outputCellId) ? null : outputCellId,
            outputCellType, Language(notebook), original, updated);
    }

    private static (int Value, string? Error) ResolveIndex(JsonArray cells, string? cellId, string mode)
    {
        if (string.IsNullOrWhiteSpace(cellId))
        {
            return mode == "insert" ? (0, null) : (0, "missing_cell_id");
        }
        var index = -1;
        for (var position = 0; position < cells.Count; position++)
        {
            if (string.Equals((cells[position] as JsonObject)?["id"]?.GetValue<string>(), cellId, StringComparison.Ordinal))
            {
                index = position;
                break;
            }
        }
        if (index < 0) index = ParseIndexAlias(cellId) ?? -1;
        if (index < 0 || index >= cells.Count) return (0, "cell_not_found");
        return mode == "insert" ? (index + 1, null) : (index, null);
    }

    private static int? ParseIndexAlias(string cellId) =>
        cellId.StartsWith("cell-", StringComparison.Ordinal)
        && int.TryParse(cellId.AsSpan("cell-".Length), out var index)
            ? index
            : null;

    private static bool ShouldWriteCellIds(JsonObject notebook) =>
        (notebook["nbformat"]?.GetValue<int>() ?? 4) > 4
        || ((notebook["nbformat"]?.GetValue<int>() ?? 4) == 4
            && (notebook["nbformat_minor"]?.GetValue<int>() ?? 0) >= 5);

    private static string Language(JsonObject notebook) =>
        ((notebook["metadata"] as JsonObject)?["language_info"] as JsonObject)?["name"]?.GetValue<string>()
        ?? "python";

    private static AgentNotebookEditResult Fail(string error) => new(false, error);
}
