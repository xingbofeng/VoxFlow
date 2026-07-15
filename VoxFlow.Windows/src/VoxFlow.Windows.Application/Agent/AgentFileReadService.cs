using System.Text;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentFileReadResult(
    bool Ok,
    string? Content,
    string? ErrorCode,
    bool IsFullRead,
    bool IsTruncated = false,
    int? NextLineOffset = null,
    int? NextCharOffset = null);

public sealed class AgentFileReadService
{
    public const long MaxBytes = 1_000_000;
    public const int DefaultLimit = 2_000;
    public const int MaximumLimit = 10_000;
    private readonly AgentPathPolicy paths;
    private readonly AgentFileReadState readState;
    public AgentFileReadService(AgentPathPolicy paths, AgentFileReadState? readState = null)
    {
        this.paths = paths ?? throw new ArgumentNullException(nameof(paths));
        this.readState = readState ?? new AgentFileReadState();
    }

    public async Task<AgentFileReadResult> ReadAsync(
        string workspaceRoot,
        string requestedPath,
        CancellationToken cancellationToken,
        int? lineOffset = null,
        int? charOffset = null,
        int? limit = null)
    {
        var decision = paths.ResolveWorkspacePath(workspaceRoot, requestedPath);
        if (!decision.Allowed) return new(false, null, decision.ErrorCode, false);
        if (Directory.Exists(decision.FullPath!)) return new(false, null, "path_is_directory", false);
        if (lineOffset is < 1 || charOffset is < 0 || limit is < 1 or > MaximumLimit)
        {
            return new(false, null, "invalid_read_range", false);
        }
        if (lineOffset is not null && charOffset is not null)
        {
            return new(false, null, "ambiguous_read_range", false);
        }
        var info = new FileInfo(decision.FullPath!);
        if (!info.Exists) return new(false, null, "file_not_found", false);
        if (info.Length > MaxBytes) return new(false, null, "file_too_large", false);
        try
        {
            var bytes = await File.ReadAllBytesAsync(info.FullName, cancellationToken).ConfigureAwait(false);
            if (bytes.Contains((byte)0)) return new(false, null, "file_binary", false);
            var encoding = new UTF8Encoding(false, true);
            var content = encoding.GetString(bytes);
            return Slice(info.FullName, content, lineOffset, charOffset, limit ?? DefaultLimit);
        }
        catch (DecoderFallbackException) { return new(false, null, "file_not_utf8", false); }
        catch (IOException) { return new(false, null, "file_unavailable", false); }
    }

    private AgentFileReadResult Slice(
        string fullPath,
        string content,
        int? lineOffset,
        int? charOffset,
        int limit)
    {
        if (charOffset is { } characterStart)
        {
            if (characterStart > content.Length)
            {
                return new(false, null, "char_offset_out_of_range", false);
            }

            var length = Math.Min(limit, content.Length - characterStart);
            var sliced = content.Substring(characterStart, length);
            var next = characterStart + length;
            var full = characterStart == 0 && next == content.Length;
            if (full) readState.RecordFullRead(fullPath, content);
            return new(true, sliced, null, full, !full,
                NextCharOffset: next < content.Length ? next : null);
        }

        var lines = content.Split(["\r\n", "\n", "\r"], StringSplitOptions.None);
        var start = (lineOffset ?? 1) - 1;
        if (start > lines.Length)
        {
            return new(false, null, "line_offset_out_of_range", false);
        }
        var count = Math.Min(limit, lines.Length - start);
        var slicedLines = lines.Skip(start).Take(count).ToArray();
        var nextLine = start + count;
        var fullRead = start == 0 && nextLine == lines.Length;
        if (fullRead) readState.RecordFullRead(fullPath, content);
        return new(
            true,
            string.Join(Environment.NewLine, slicedLines),
            null,
            fullRead,
            !fullRead,
            NextLineOffset: nextLine < lines.Length ? nextLine + 1 : null);
    }
}
