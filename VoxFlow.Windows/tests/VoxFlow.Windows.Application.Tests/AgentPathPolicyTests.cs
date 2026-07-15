using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentPathPolicyTests
{
    [Fact]
    public void Rejects_escape_and_windows_device_paths()
    {
        var policy = new AgentPathPolicy();
        var root = Path.Combine(Path.GetTempPath(), "voxflow-workspace");
        Assert.True(policy.ResolveWorkspacePath(root, "report.md").Allowed);
        Assert.Equal("outside_workspace", policy.ResolveWorkspacePath(root, "..\\outside.txt").ErrorCode);
        Assert.Equal("blocked_device_path", policy.ResolveWorkspacePath(root, "NUL").ErrorCode);
    }

    [Fact]
    public void Canonical_workspace_comparison_rejects_prefix_case_escape_and_system_workspace()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-workspace", "project");
        var policy = new AgentPathPolicy();

        var allowed = policy.ResolveWorkspacePath(root, Path.Combine(root, "src", "note.txt"));
        var prefixEscape = policy.ResolveWorkspacePath(root, root + "-other" + Path.DirectorySeparatorChar + "note.txt");
        var device = policy.ResolveWorkspacePath(root, "\\\\?\\GLOBALROOT\\Device\\HarddiskVolume1");

        Assert.True(allowed.Allowed);
        Assert.Equal("outside_workspace", prefixEscape.ErrorCode);
        Assert.Equal("blocked_device_path", device.ErrorCode);

        var windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        if (!string.IsNullOrWhiteSpace(windowsDirectory))
        {
            Assert.Equal("blocked_system_directory", policy.ResolveWorkspacePath(windowsDirectory, "System32\\cmd.exe").ErrorCode);
        }
    }

    [Fact]
    public void Existing_junction_or_reparse_component_is_rejected_before_file_tools_can_follow_it()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-workspace", "project");
        var junction = Path.Combine(root, "linked");
        var policy = new AgentPathPolicy(path =>
            string.Equals(path, junction, StringComparison.OrdinalIgnoreCase)
                ? FileAttributes.Directory | FileAttributes.ReparsePoint
                : null);

        var decision = policy.ResolveWorkspacePath(root, Path.Combine("linked", "outside.txt"));

        Assert.False(decision.Allowed);
        Assert.Equal("blocked_reparse_point", decision.ErrorCode);
        Assert.Null(decision.FullPath);
    }

    [Theory]
    [InlineData("CON.txt")]
    [InlineData("com1.log")]
    [InlineData("LPT9")]
    [InlineData("AUX.md")]
    public void Device_names_are_blocked_regardless_of_extension_or_case(string requested)
    {
        var decision = new AgentPathPolicy().ResolveWorkspacePath(
            Path.Combine(Path.GetTempPath(), "voxflow-workspace"), requested);

        Assert.Equal("blocked_device_path", decision.ErrorCode);
    }
}
