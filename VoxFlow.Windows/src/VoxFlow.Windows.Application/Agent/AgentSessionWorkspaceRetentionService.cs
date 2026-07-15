namespace VoxFlow.Windows.Application.Agent;

public sealed record AgentSessionWorkspaceDescriptor
{
    public AgentSessionWorkspaceDescriptor(
        string sessionId,
        DateTimeOffset lastWriteTimeUtc,
        bool isReparsePoint)
    {
        SessionId = sessionId;
        LastWriteTimeUtc = lastWriteTimeUtc;
        IsReparsePoint = isReparsePoint;
    }

    public string SessionId { get; }

    public DateTimeOffset LastWriteTimeUtc { get; }

    public bool IsReparsePoint { get; }
}

public sealed record AgentSessionWorkspaceCleanupResult(
    int DeletedCount,
    int SkippedUnsafeCount);

public sealed record AgentSessionWorkspaceEphemeralCleanupResult(
    int DeletedDirectoryCount,
    int SkippedUnsafeCount);

public interface IAgentSessionWorkspaceStore
{
    IReadOnlyList<AgentSessionWorkspaceDescriptor> ListSessions();

    bool DeleteSession(string sessionId);

    AgentSessionWorkspaceEphemeralCleanupResult CleanupEphemeralArtifacts(
        string sessionId);
}

public sealed class FileSystemAgentSessionWorkspaceStore
    : IAgentSessionWorkspaceStore
{
    private readonly string sessionsRoot;

    public FileSystemAgentSessionWorkspaceStore(string sessionsRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sessionsRoot);
        this.sessionsRoot = Path.GetFullPath(sessionsRoot);
        Directory.CreateDirectory(this.sessionsRoot);
    }

    public IReadOnlyList<AgentSessionWorkspaceDescriptor> ListSessions() =>
        new DirectoryInfo(sessionsRoot)
            .EnumerateDirectories("*", SearchOption.TopDirectoryOnly)
            .Select(directory => new AgentSessionWorkspaceDescriptor(
                directory.Name,
                directory.LastWriteTimeUtc,
                directory.Attributes.HasFlag(FileAttributes.ReparsePoint)))
            .OrderBy(session => session.SessionId, StringComparer.Ordinal)
            .ToArray();

    public bool DeleteSession(string sessionId)
    {
        var path = ResolveDirectChild(sessionId);
        var directory = new DirectoryInfo(path);
        if (!directory.Exists
            || directory.Attributes.HasFlag(FileAttributes.ReparsePoint))
        {
            return false;
        }

        try
        {
            DeleteDirectoryWithoutFollowingReparsePoints(directory);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    public AgentSessionWorkspaceEphemeralCleanupResult CleanupEphemeralArtifacts(
        string sessionId)
    {
        var path = ResolveDirectChild(sessionId);
        var session = new DirectoryInfo(path);
        if (!session.Exists)
        {
            return new(0, 0);
        }
        if (session.Attributes.HasFlag(FileAttributes.ReparsePoint))
        {
            return new(0, 1);
        }

        var deleted = 0;
        var skippedUnsafe = 0;
        foreach (var directoryName in new[] { "screenshots", "tmp" })
        {
            var ephemeralDirectory = new DirectoryInfo(Path.Combine(path, directoryName));
            if (!ephemeralDirectory.Exists)
            {
                continue;
            }
            if (ephemeralDirectory.Attributes.HasFlag(FileAttributes.ReparsePoint))
            {
                skippedUnsafe++;
                continue;
            }

            try
            {
                DeleteDirectoryWithoutFollowingReparsePoints(ephemeralDirectory);
                deleted++;
            }
            catch (IOException)
            {
                skippedUnsafe++;
            }
            catch (UnauthorizedAccessException)
            {
                skippedUnsafe++;
            }
        }

        return new(deleted, skippedUnsafe);
    }

    private string ResolveDirectChild(string sessionId)
    {
        AgentSessionWorkspaceRetentionService.ValidateSessionId(sessionId);
        var path = Path.GetFullPath(Path.Combine(sessionsRoot, sessionId));
        if (!string.Equals(
                Path.GetDirectoryName(path),
                sessionsRoot,
                StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException(
                "A managed Agent session must be a direct child of the session root.",
                nameof(sessionId));
        }
        return path;
    }

    private static void DeleteDirectoryWithoutFollowingReparsePoints(
        DirectoryInfo directory)
    {
        foreach (var entry in directory.EnumerateFileSystemInfos())
        {
            if (entry.Attributes.HasFlag(FileAttributes.ReparsePoint))
            {
                if (entry is DirectoryInfo linkedDirectory)
                {
                    linkedDirectory.Delete(recursive: false);
                }
                else
                {
                    entry.Delete();
                }
                continue;
            }

            if (entry is DirectoryInfo childDirectory)
            {
                DeleteDirectoryWithoutFollowingReparsePoints(childDirectory);
            }
            else
            {
                entry.Delete();
            }
        }
        directory.Delete(recursive: false);
    }
}

/// <summary>
/// Applies retention only to app-managed session identifiers. Artifact paths
/// are deliberately not accepted by this boundary, so deleting history can
/// never delete a user-selected file outside the managed session root.
/// </summary>
public sealed class AgentSessionWorkspaceRetentionService
{
    public const int MaximumRetainedSessions = 100;
    public static readonly TimeSpan MaximumSessionAge = TimeSpan.FromDays(7);

    private readonly IAgentSessionWorkspaceStore store;
    private readonly TimeProvider timeProvider;

    public AgentSessionWorkspaceRetentionService(
        IAgentSessionWorkspaceStore store,
        TimeProvider timeProvider)
    {
        this.store = store ?? throw new ArgumentNullException(nameof(store));
        this.timeProvider = timeProvider
            ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public AgentSessionWorkspaceCleanupResult CleanupExpired()
    {
        var cutoff = timeProvider.GetUtcNow() - MaximumSessionAge;
        var sessions = store.ListSessions();
        var unsafeCount = sessions.Count(session => session.IsReparsePoint);
        var safe = sessions
            .Where(session => !session.IsReparsePoint)
            .OrderByDescending(session => session.LastWriteTimeUtc)
            .ThenBy(session => session.SessionId, StringComparer.Ordinal)
            .ToArray();
        var expiredIds = safe
            .Where(session => session.LastWriteTimeUtc < cutoff)
            .Select(session => session.SessionId)
            .ToHashSet(StringComparer.Ordinal);
        var retainedAfterAge = safe
            .Where(session => !expiredIds.Contains(session.SessionId))
            .ToArray();
        var overflowIds = retainedAfterAge
            .Skip(MaximumRetainedSessions)
            .Select(session => session.SessionId);

        var deleted = 0;
        foreach (var sessionId in expiredIds
                     .Concat(overflowIds)
                     .Distinct(StringComparer.Ordinal))
        {
            if (store.DeleteSession(sessionId))
            {
                deleted++;
            }
        }

        return new AgentSessionWorkspaceCleanupResult(deleted, unsafeCount);
    }

    public bool DeleteSessionForHistory(string sessionId)
    {
        ValidateSessionId(sessionId);
        var descriptor = store.ListSessions().FirstOrDefault(session =>
            string.Equals(session.SessionId, sessionId, StringComparison.Ordinal));
        return descriptor is { IsReparsePoint: false }
            && store.DeleteSession(sessionId);
    }

    /// <summary>Removes only the two reserved transient directories from all
    /// safe managed sessions. Ordinary task artifacts are deliberately kept.
    /// This runs on startup to recover captures left by a process crash.</summary>
    public AgentSessionWorkspaceEphemeralCleanupResult CleanupEphemeralArtifacts()
    {
        var deleted = 0;
        var skippedUnsafe = 0;
        foreach (var session in store.ListSessions())
        {
            if (session.IsReparsePoint)
            {
                skippedUnsafe++;
                continue;
            }

            var result = store.CleanupEphemeralArtifacts(session.SessionId);
            deleted += result.DeletedDirectoryCount;
            skippedUnsafe += result.SkippedUnsafeCount;
        }
        return new(deleted, skippedUnsafe);
    }

    /// <summary>Runs at Agent task termination. It accepts only the managed
    /// task identifier so a model or artifact path cannot redirect cleanup.</summary>
    public AgentSessionWorkspaceEphemeralCleanupResult CleanupEphemeralArtifactsForSession(
        string sessionId)
    {
        ValidateSessionId(sessionId);
        var session = store.ListSessions().FirstOrDefault(candidate =>
            string.Equals(candidate.SessionId, sessionId, StringComparison.Ordinal));
        return session switch
        {
            null => new(0, 0),
            { IsReparsePoint: true } => new(0, 1),
            _ => store.CleanupEphemeralArtifacts(sessionId),
        };
    }

    internal static void ValidateSessionId(string sessionId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sessionId);
        if (sessionId is "." or ".."
            || sessionId.Length > 128
            || sessionId.IndexOfAny(['/', '\\', ':']) >= 0
            || sessionId.Any(character =>
                !(char.IsAsciiLetterOrDigit(character)
                  || character is '-' or '_' or '.')))
        {
            throw new ArgumentException(
                "A managed Agent session id must not contain a path.",
                nameof(sessionId));
        }
    }
}
