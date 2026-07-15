using System.Text;
using System.Text.RegularExpressions;

namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentFileSearchResult(
    bool Ok,
    IReadOnlyList<string> Files,
    IReadOnlyList<AgentGrepMatch> Matches,
    bool Truncated,
    string? ErrorCode);

public sealed record AgentGrepMatch(string Path, int Line, string Text);

/// <summary>
/// Shell-free workspace glob and grep implementation.  Traversal never
/// follows reparse points and intentionally omits VCS metadata, so a model
/// cannot use a junction or .git checkout to escape its managed workspace.
/// </summary>
public sealed class AgentFileSearchService
{
    public const int MaximumResults = 200;
    private const int MaximumFileBytes = 1_000_000;
    private static readonly TimeSpan RegexTimeout = TimeSpan.FromMilliseconds(250);
    private readonly AgentPathPolicy paths;

    public AgentFileSearchService(AgentPathPolicy paths) =>
        this.paths = paths ?? throw new ArgumentNullException(nameof(paths));

    public AgentFileSearchResult Glob(
        string workspaceRoot,
        string requestedPath,
        string pattern,
        int limit = MaximumResults)
    {
        if (!TryResolveDirectory(workspaceRoot, requestedPath, out var root, out var error))
        {
            return Failure(error!);
        }
        if (string.IsNullOrWhiteSpace(pattern) || limit is < 1 or > MaximumResults)
        {
            return Failure("invalid_pattern");
        }

        Regex matcher;
        try
        {
            matcher = new Regex(GlobToRegex(pattern), RegexOptions.CultureInvariant | RegexOptions.IgnoreCase, RegexTimeout);
        }
        catch (ArgumentException)
        {
            return Failure("invalid_pattern");
        }

        var files = new List<string>();
        try
        {
            foreach (var file in EnumerateWorkspaceFiles(root))
            {
                var relative = RelativePath(root, file);
                if (!matcher.IsMatch(relative))
                {
                    continue;
                }
                files.Add(relative);
                if (files.Count == limit)
                {
                    return new(true, files, [], true, null);
                }
            }
        }
        catch (RegexMatchTimeoutException)
        {
            return Failure("regex_timeout");
        }

        return new(true, files, [], false, null);
    }

    public AgentFileSearchResult Grep(
        string workspaceRoot,
        string requestedPath,
        string pattern,
        int limit = MaximumResults)
    {
        if (!TryResolveDirectory(workspaceRoot, requestedPath, out var root, out var error))
        {
            return Failure(error!);
        }
        if (string.IsNullOrWhiteSpace(pattern) || limit is < 1 or > MaximumResults)
        {
            return Failure("invalid_pattern");
        }

        Regex matcher;
        try
        {
            matcher = new Regex(pattern, RegexOptions.CultureInvariant, RegexTimeout);
        }
        catch (ArgumentException)
        {
            return Failure("invalid_pattern");
        }

        var matches = new List<AgentGrepMatch>();
        try
        {
            foreach (var file in EnumerateWorkspaceFiles(root))
            {
                var content = TryReadUtf8Text(file);
                if (content is null)
                {
                    continue;
                }
                var relative = RelativePath(root, file);
                var line = 0;
                using var reader = new StringReader(content);
                while (reader.ReadLine() is { } text)
                {
                    line++;
                    if (!matcher.IsMatch(text))
                    {
                        continue;
                    }
                    matches.Add(new AgentGrepMatch(relative, line, text));
                    if (matches.Count == limit)
                    {
                        return new(true, [], matches, true, null);
                    }
                }
            }
        }
        catch (RegexMatchTimeoutException)
        {
            return Failure("regex_timeout");
        }

        return new(true, [], matches, false, null);
    }

    private bool TryResolveDirectory(
        string workspaceRoot,
        string requestedPath,
        out string root,
        out string? error)
    {
        root = string.Empty;
        error = null;
        var decision = paths.ResolveWorkspacePath(workspaceRoot, requestedPath);
        if (!decision.Allowed)
        {
            error = decision.ErrorCode;
            return false;
        }
        if (!Directory.Exists(decision.FullPath))
        {
            error = "directory_not_found";
            return false;
        }
        var attributes = File.GetAttributes(decision.FullPath!);
        if (attributes.HasFlag(FileAttributes.ReparsePoint))
        {
            error = "reparse_point_blocked";
            return false;
        }
        root = decision.FullPath!;
        return true;
    }

    private static IEnumerable<string> EnumerateWorkspaceFiles(string root)
    {
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0)
        {
            var directory = pending.Pop();
            IEnumerable<string> entries;
            try
            {
                entries = Directory.EnumerateFileSystemEntries(directory).ToArray();
            }
            catch (IOException)
            {
                continue;
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }

            foreach (var entry in entries.OrderBy(path => path, StringComparer.OrdinalIgnoreCase))
            {
                FileAttributes attributes;
                try
                {
                    attributes = File.GetAttributes(entry);
                }
                catch (IOException)
                {
                    continue;
                }
                catch (UnauthorizedAccessException)
                {
                    continue;
                }
                if (attributes.HasFlag(FileAttributes.ReparsePoint))
                {
                    continue;
                }
                if (Directory.Exists(entry))
                {
                    if (!string.Equals(Path.GetFileName(entry), ".git", StringComparison.OrdinalIgnoreCase))
                    {
                        pending.Push(entry);
                    }
                    continue;
                }
                if (File.Exists(entry))
                {
                    yield return entry;
                }
            }
        }
    }

    private static string? TryReadUtf8Text(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || info.Length > MaximumFileBytes)
            {
                return null;
            }
            return new UTF8Encoding(false, true).GetString(File.ReadAllBytes(path));
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (DecoderFallbackException)
        {
            return null;
        }
    }

    private static string RelativePath(string root, string path) =>
        Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/');

    private static AgentFileSearchResult Failure(string error) => new(false, [], [], false, error);

    private static string GlobToRegex(string pattern)
    {
        var expression = new StringBuilder("^");
        for (var index = 0; index < pattern.Length; index++)
        {
            var character = pattern[index];
            if (character == '*' && index + 1 < pattern.Length && pattern[index + 1] == '*')
            {
                index++;
                if (index + 1 < pattern.Length && IsPathSeparator(pattern[index + 1]))
                {
                    index++;
                    expression.Append("(?:.*/)?");
                }
                else
                {
                    expression.Append(".*");
                }
            }
            else if (character == '*')
            {
                expression.Append("[^/]*");
            }
            else if (character == '?')
            {
                expression.Append("[^/]");
            }
            else if (IsPathSeparator(character))
            {
                expression.Append('/');
            }
            else
            {
                expression.Append(Regex.Escape(character.ToString()));
            }
        }
        return expression.Append('$').ToString();
    }

    private static bool IsPathSeparator(char character) => character is '/' or '\\';
}
