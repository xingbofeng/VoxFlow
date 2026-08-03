namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentPathDecision(bool Allowed, string? FullPath, string? ErrorCode);

public sealed class AgentPathPolicy
{
    private static readonly string[] DeviceNames = ["CON", "PRN", "AUX", "NUL", "CLOCK$"];
    private readonly Func<string, FileAttributes?> attributes;

    public AgentPathPolicy(Func<string, FileAttributes?>? attributes = null) =>
        this.attributes = attributes ?? ReadAttributes;

    public AgentPathDecision ResolveWorkspacePath(string workspaceRoot, string requestedPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(workspaceRoot);
        ArgumentException.ThrowIfNullOrWhiteSpace(requestedPath);
        if (requestedPath.StartsWith("\\\\.\\", StringComparison.Ordinal) ||
            requestedPath.StartsWith("\\\\?\\", StringComparison.OrdinalIgnoreCase))
            return new(false, null, "blocked_device_path");

        var leaf = Path.GetFileNameWithoutExtension(requestedPath);
        if (DeviceNames.Contains(leaf, StringComparer.OrdinalIgnoreCase) ||
            System.Text.RegularExpressions.Regex.IsMatch(leaf, "^(COM|LPT)[1-9]$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            return new(false, null, "blocked_device_path");

        var rootDirectory = TrimDirectoryEnding(Path.GetFullPath(workspaceRoot));
        if (IsSystemDirectory(rootDirectory))
        {
            return new(false, null, "blocked_system_directory");
        }
        var root = rootDirectory + Path.DirectorySeparatorChar;
        var full = Path.GetFullPath(Path.IsPathRooted(requestedPath) ? requestedPath : Path.Combine(root, requestedPath));
        if (!string.Equals(full, rootDirectory, StringComparison.OrdinalIgnoreCase) &&
            !full.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            return new(false, null, "outside_workspace");
        if (HasReparsePoint(rootDirectory, full))
        {
            return new(false, null, "blocked_reparse_point");
        }
        return new(true, full, null);
    }

    private bool HasReparsePoint(string workspaceRoot, string fullPath)
    {
        var relative = Path.GetRelativePath(workspaceRoot, fullPath);
        if (relative is "." or "")
        {
            return false;
        }

        var current = workspaceRoot;
        foreach (var part in relative.Split(
            [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar],
            StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, part);
            if (attributes(current) is { } value
                && value.HasFlag(FileAttributes.ReparsePoint))
            {
                return true;
            }
        }

        return false;
    }

    private static FileAttributes? ReadAttributes(string path)
    {
        try
        {
            return File.Exists(path) || Directory.Exists(path)
                ? File.GetAttributes(path)
                : null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static string TrimDirectoryEnding(string path)
    {
        var root = Path.GetPathRoot(path);
        return string.Equals(path, root, StringComparison.OrdinalIgnoreCase)
            ? path
            : path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
    }

    private static bool IsSystemDirectory(string path) => SystemDirectories()
        .Any(directory => IsSameOrDescendant(path, directory));

    private static IEnumerable<string> SystemDirectories()
    {
        var values = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
        };
        foreach (var value in values.Where(value => !string.IsNullOrWhiteSpace(value)))
        {
            yield return TrimDirectoryEnding(Path.GetFullPath(value));
        }
    }

    private static bool IsSameOrDescendant(string candidate, string parent)
    {
        var boundary = parent + Path.DirectorySeparatorChar;
        return string.Equals(candidate, parent, StringComparison.OrdinalIgnoreCase)
            || candidate.StartsWith(boundary, StringComparison.OrdinalIgnoreCase);
    }
}
