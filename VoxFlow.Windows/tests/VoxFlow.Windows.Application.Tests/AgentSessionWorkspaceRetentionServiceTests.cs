using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentSessionWorkspaceRetentionServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 7, 11, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Cleanup_removes_expired_and_overflow_sessions_but_skips_reparse_points()
    {
        var sessions = Enumerable.Range(0, 101)
            .Select(index => new AgentSessionWorkspaceDescriptor(
                $"recent-{index:D3}",
                Now.AddMinutes(-index),
                isReparsePoint: false))
            .Append(new AgentSessionWorkspaceDescriptor(
                "expired",
                Now.AddDays(-7).AddMilliseconds(-1),
                isReparsePoint: false))
            .Append(new AgentSessionWorkspaceDescriptor(
                "unsafe-link",
                Now.AddDays(-30),
                isReparsePoint: true))
            .ToArray();
        var store = new CapturingWorkspaceStore(sessions);
        var service = new AgentSessionWorkspaceRetentionService(
            store,
            new ControlledTimeProvider(Now));

        var result = service.CleanupExpired();

        Assert.Equal(2, result.DeletedCount);
        Assert.Equal(1, result.SkippedUnsafeCount);
        Assert.Contains("expired", store.DeletedIds);
        Assert.Contains("recent-100", store.DeletedIds);
        Assert.DoesNotContain("recent-099", store.DeletedIds);
        Assert.DoesNotContain("unsafe-link", store.DeletedIds);
    }

    [Fact]
    public void History_deletion_accepts_only_a_session_id_and_never_an_artifact_path()
    {
        var store = new CapturingWorkspaceStore(
        [
            new AgentSessionWorkspaceDescriptor("agent-task", Now, false),
        ]);
        var service = new AgentSessionWorkspaceRetentionService(
            store,
            new ControlledTimeProvider(Now));

        Assert.True(service.DeleteSessionForHistory("agent-task"));
        Assert.Equal(["agent-task"], store.DeletedIds);
        Assert.Throws<ArgumentException>(() =>
            service.DeleteSessionForHistory(@"C:\Users\Alice\report.md"));
        Assert.Throws<ArgumentException>(() =>
            service.DeleteSessionForHistory("../outside"));
        Assert.Equal(["agent-task"], store.DeletedIds);
    }

    [Fact]
    public void File_system_store_deletes_only_a_direct_managed_session_directory()
    {
        using var directory = new TemporaryDirectory();
        var sessionsRoot = Path.Combine(directory.Path, "sessions");
        var managed = Path.Combine(sessionsRoot, "agent-task");
        var external = Path.Combine(directory.Path, "external-artifact");
        Directory.CreateDirectory(managed);
        Directory.CreateDirectory(external);
        File.WriteAllText(Path.Combine(managed, "trace.json"), "managed");
        File.WriteAllText(Path.Combine(external, "report.md"), "user file");
        var store = new FileSystemAgentSessionWorkspaceStore(sessionsRoot);

        Assert.True(store.DeleteSession("agent-task"));

        Assert.False(Directory.Exists(managed));
        Assert.True(File.Exists(Path.Combine(external, "report.md")));
        Assert.Throws<ArgumentException>(() =>
            store.DeleteSession(@"..\external-artifact"));
        Assert.True(File.Exists(Path.Combine(external, "report.md")));
    }

    [Fact]
    public void Ephemeral_cleanup_removes_only_screenshots_and_tmp_from_all_safe_sessions()
    {
        using var directory = new TemporaryDirectory();
        var sessionsRoot = Path.Combine(directory.Path, "sessions");
        var session = Path.Combine(sessionsRoot, "agent-task");
        Directory.CreateDirectory(Path.Combine(session, "screenshots"));
        Directory.CreateDirectory(Path.Combine(session, "tmp"));
        File.WriteAllText(Path.Combine(session, "screenshots", "capture.png"), "pixels");
        File.WriteAllText(Path.Combine(session, "tmp", "request.json"), "transient");
        File.WriteAllText(Path.Combine(session, "result.md"), "user artifact");
        var service = new AgentSessionWorkspaceRetentionService(
            new FileSystemAgentSessionWorkspaceStore(sessionsRoot),
            new ControlledTimeProvider(Now));

        var result = service.CleanupEphemeralArtifacts();

        Assert.Equal(2, result.DeletedDirectoryCount);
        Assert.Equal(0, result.SkippedUnsafeCount);
        Assert.False(Directory.Exists(Path.Combine(session, "screenshots")));
        Assert.False(Directory.Exists(Path.Combine(session, "tmp")));
        Assert.Equal("user artifact", File.ReadAllText(Path.Combine(session, "result.md")));
    }

    private sealed class CapturingWorkspaceStore(
        IReadOnlyList<AgentSessionWorkspaceDescriptor> initial)
        : IAgentSessionWorkspaceStore
    {
        private readonly List<AgentSessionWorkspaceDescriptor> sessions = [.. initial];

        public List<string> DeletedIds { get; } = [];

        public IReadOnlyList<AgentSessionWorkspaceDescriptor> ListSessions() =>
            sessions.ToArray();

        public bool DeleteSession(string sessionId)
        {
            DeletedIds.Add(sessionId);
            return sessions.RemoveAll(session => session.SessionId == sessionId) == 1;
        }

        public AgentSessionWorkspaceEphemeralCleanupResult CleanupEphemeralArtifacts(
            string sessionId) => new(0, 0);
    }
}
