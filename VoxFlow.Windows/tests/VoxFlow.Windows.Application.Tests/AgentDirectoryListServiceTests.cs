using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentDirectoryListServiceTests
{
    [Fact]
    public void Lists_only_direct_children()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")); Directory.CreateDirectory(Path.Combine(root, "nested")); File.WriteAllText(Path.Combine(root, "a.txt"), "x"); File.WriteAllText(Path.Combine(root, "nested", "hidden.txt"), "x");
        try { var result = new AgentDirectoryListService(new AgentPathPolicy()).List(root, "."); Assert.True(result.Ok); Assert.Equal(["a.txt", "nested"], result.Entries); }
        finally { Directory.Delete(root, true); }
    }
}
