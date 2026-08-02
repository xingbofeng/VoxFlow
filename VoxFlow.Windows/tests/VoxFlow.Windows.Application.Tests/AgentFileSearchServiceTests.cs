using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentFileSearchServiceTests
{
    [Fact]
    public async Task Glob_and_grep_stay_inside_workspace_skip_git_and_honor_result_limits()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-search-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(root, "src"));
        Directory.CreateDirectory(Path.Combine(root, ".git"));
        try
        {
            await File.WriteAllTextAsync(Path.Combine(root, "src", "one.cs"), "class One { }\nneedle");
            await File.WriteAllTextAsync(Path.Combine(root, "src", "two.cs"), "needle\nneedle");
            await File.WriteAllTextAsync(Path.Combine(root, ".git", "config"), "needle");
            var search = new AgentFileSearchService(new AgentPathPolicy());

            var glob = search.Glob(root, ".", "**/*.cs", limit: 1);
            var grep = search.Grep(root, ".", "needle", limit: 2);

            Assert.True(glob.Ok);
            Assert.Single(glob.Files);
            Assert.True(glob.Truncated);
            Assert.True(grep.Ok);
            Assert.Equal(2, grep.Matches.Count);
            Assert.True(grep.Truncated);
            Assert.DoesNotContain(grep.Matches, match => match.Path.StartsWith(".git/", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void Search_rejects_workspace_escape_invalid_regex_and_reparse_root()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-search-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var search = new AgentFileSearchService(new AgentPathPolicy());
            Assert.Equal("outside_workspace", search.Glob(root, "..", "*", 10).ErrorCode);
            Assert.Equal("invalid_pattern", search.Grep(root, ".", "[", 10).ErrorCode);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task Grep_stops_pathological_regex_with_a_safe_timeout()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-search-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            await File.WriteAllTextAsync(Path.Combine(root, "slow.txt"), new string('a', 20_000) + "!");
            var result = new AgentFileSearchService(new AgentPathPolicy())
                .Grep(root, ".", "^(a+)+$", 10);

            Assert.False(result.Ok);
            Assert.Equal("regex_timeout", result.ErrorCode);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
