using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentFileEditServiceTests
{
    [Fact]
    public async Task Rejects_ambiguous_edit_and_writes_unique_read_file()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")); Directory.CreateDirectory(root);
        try
        {
            var path = Path.Combine(root, "a.txt"); await File.WriteAllTextAsync(path, "one one");
            var reads = new AgentFileReadState(); reads.RecordFullRead(path, "one one");
            var service = new AgentFileEditService(new AgentPathPolicy(), reads);
            Assert.Equal("ambiguous_edit", (await service.ReplaceAsync(root, "a.txt", "one", "two", false, CancellationToken.None)).ErrorCode);
            var result = await service.ReplaceAsync(root, "a.txt", "one", "two", true, CancellationToken.None);
            Assert.True(result.Ok); Assert.Equal("two two", await File.ReadAllTextAsync(path));
        }
        finally { Directory.Delete(root, true); }
    }
}
