namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentDirectoryListResult(bool Ok, IReadOnlyList<string> Entries, string? ErrorCode);

public sealed class AgentDirectoryListService
{
    private readonly AgentPathPolicy paths;
    public AgentDirectoryListService(AgentPathPolicy paths) => this.paths = paths ?? throw new ArgumentNullException(nameof(paths));

    public AgentDirectoryListResult List(string workspaceRoot, string requestedPath)
    {
        var decision = paths.ResolveWorkspacePath(workspaceRoot, requestedPath);
        if (!decision.Allowed) return new(false, [], decision.ErrorCode);
        if (!Directory.Exists(decision.FullPath)) return new(false, [], "directory_not_found");
        var entries = Directory.EnumerateFileSystemEntries(decision.FullPath!, "*", SearchOption.TopDirectoryOnly)
            .Select(Path.GetFileName).Where(name => !string.IsNullOrWhiteSpace(name))
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase).ToArray();
        return new(true, entries!, null);
    }
}
