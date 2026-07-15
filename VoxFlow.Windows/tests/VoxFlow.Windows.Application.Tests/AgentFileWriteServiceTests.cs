using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentFileWriteServiceTests
{
    [Fact]
    public async Task Creates_new_file_but_requires_read_before_overwrite()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")); Directory.CreateDirectory(root);
        try
        {
            var reads = new AgentFileReadState(); var paths = new AgentPathPolicy();
            var writer = new AgentFileWriteService(paths, reads);
            Assert.True((await writer.WriteAsync(root, "new.txt", "new", CancellationToken.None)).Created);
            await File.WriteAllTextAsync(Path.Combine(root, "old.txt"), "old");
            Assert.Equal("file_not_read_or_modified", (await writer.WriteAsync(root, "old.txt", "changed", CancellationToken.None)).ErrorCode);
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Write_enforces_size_unchanged_read_workspace_and_atomic_replace_contracts()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var reads = new AgentFileReadState();
            var paths = new AgentPathPolicy();
            var reader = new AgentFileReadService(paths, reads);
            var writer = new AgentFileWriteService(paths, reads);
            var target = Path.Combine(root, "existing.txt");
            await File.WriteAllTextAsync(target, "before");

            var oversized = await writer.WriteAsync(root, "large.txt", new string('x', AgentFileWriteService.MaxBytes + 1), CancellationToken.None);
            var outside = await writer.WriteAsync(root, "..\\outside.txt", "blocked", CancellationToken.None);
            var initialRead = await reader.ReadAsync(root, "existing.txt", CancellationToken.None, limit: AgentFileReadService.MaximumLimit);
            await File.WriteAllTextAsync(target, "changed elsewhere");
            var changed = await writer.WriteAsync(root, "existing.txt", "new", CancellationToken.None);
            _ = await reader.ReadAsync(root, "existing.txt", CancellationToken.None, limit: AgentFileReadService.MaximumLimit);
            var replaced = await writer.WriteAsync(root, "existing.txt", "replacement", CancellationToken.None);

            Assert.False(oversized.Ok);
            Assert.Equal("content_too_large", oversized.ErrorCode);
            Assert.Equal("outside_workspace", outside.ErrorCode);
            Assert.True(initialRead.IsFullRead);
            Assert.Equal("file_not_read_or_modified", changed.ErrorCode);
            Assert.True(replaced.Ok);
            Assert.False(replaced.Created);
            Assert.Equal("replacement", await File.ReadAllTextAsync(target));
            Assert.Empty(Directory.EnumerateFiles(root, "*.voxflow.tmp.*", SearchOption.AllDirectories));
        }
        finally { Directory.Delete(root, true); }
    }
}
