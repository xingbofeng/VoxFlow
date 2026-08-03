namespace VoxFlow.Windows.Application.Agent;

public sealed class AgentFileEditService
{
    private readonly AgentPathPolicy paths;
    private readonly AgentFileReadState reads;
    private readonly AgentFileWriteService writer;
    public AgentFileEditService(AgentPathPolicy paths, AgentFileReadState reads)
    { this.paths = paths; this.reads = reads; writer = new AgentFileWriteService(paths, reads); }

    public async Task<AgentFileWriteResult> ReplaceAsync(string workspaceRoot, string requestedPath, string oldText, string newText, bool replaceAll, CancellationToken cancellationToken)
    {
        if (string.IsNullOrEmpty(oldText)) return new(false, "old_text_required", false);
        var decision = paths.ResolveWorkspacePath(workspaceRoot, requestedPath);
        if (!decision.Allowed) return new(false, decision.ErrorCode, false);
        if (!reads.WasReadUnchanged(decision.FullPath!)) return new(false, "file_not_read_or_modified", false);
        var content = await File.ReadAllTextAsync(decision.FullPath!, cancellationToken).ConfigureAwait(false);
        var count = content.Split(oldText, StringSplitOptions.None).Length - 1;
        if (count == 0) return new(false, "old_text_not_found", false);
        if (count > 1 && !replaceAll) return new(false, "ambiguous_edit", false);
        var replacement = content.Replace(oldText, newText, StringComparison.Ordinal);
        return await writer.WriteAsync(workspaceRoot, requestedPath, replacement, cancellationToken).ConfigureAwait(false);
    }
}
