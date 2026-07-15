using System.Text;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentFileWriteResult(bool Ok, string? ErrorCode, bool Created);

public sealed class AgentFileWriteService
{
    public const int MaxBytes = 500_000;
    private readonly AgentPathPolicy paths;
    private readonly AgentFileReadState reads;
    public AgentFileWriteService(AgentPathPolicy paths, AgentFileReadState reads) { this.paths = paths; this.reads = reads; }

    public async Task<AgentFileWriteResult> WriteAsync(string workspaceRoot, string requestedPath, string content, CancellationToken cancellationToken)
    {
        if (Encoding.UTF8.GetByteCount(content) > MaxBytes) return new(false, "content_too_large", false);
        var decision = paths.ResolveWorkspacePath(workspaceRoot, requestedPath);
        if (!decision.Allowed) return new(false, decision.ErrorCode, false);
        var path = decision.FullPath!;
        var exists = File.Exists(path);
        if (exists && !reads.WasReadUnchanged(path)) return new(false, "file_not_read_or_modified", false);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".voxflow.tmp." + Guid.NewGuid().ToString("N");
        await File.WriteAllTextAsync(temporary, content, new UTF8Encoding(false), cancellationToken).ConfigureAwait(false);
        File.Move(temporary, path, overwrite: true);
        reads.RecordFullRead(path, content);
        return new(true, null, !exists);
    }
}
