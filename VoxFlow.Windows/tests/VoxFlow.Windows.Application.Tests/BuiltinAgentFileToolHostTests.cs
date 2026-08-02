using System.Text.Json;
using VoxFlow.Windows.Application.Agent;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Application.Tests;

public sealed class BuiltinAgentFileToolHostTests
{
    [Fact]
    public async Task Read_then_edit_then_write_uses_the_same_read_before_write_state()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-file-host-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            await File.WriteAllTextAsync(Path.Combine(root, "note.txt"), "draft");
            var host = new BuiltinAgentFileToolHost(root);

            var read = await host.ExecuteAsync(Call("read_file", new { file_path = "note.txt" }), CancellationToken.None);
            var edit = await host.ExecuteAsync(Call("edit_file", new { file_path = "note.txt", old_string = "draft", new_string = "final", replace_all = false }), CancellationToken.None);
            var write = await host.ExecuteAsync(Call("write_file", new { file_path = "note.txt", content = "published" }), CancellationToken.None);

            Assert.True(read.Ok);
            Assert.True(edit.Ok);
            Assert.True(write.Ok);
            Assert.Equal("published", await File.ReadAllTextAsync(Path.Combine(root, "note.txt")));
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task Tools_reject_an_outside_workspace_path()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-file-host-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var result = await new BuiltinAgentFileToolHost(root).ExecuteAsync(
                Call("write_file", new { file_path = "..\\outside.txt", content = "blocked" }), CancellationToken.None);

            Assert.False(result.Ok);
            Assert.Equal("outside_workspace", result.Error?.Code);
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task Glob_and_grep_follow_the_sidecar_schema()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-file-host-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            await File.WriteAllTextAsync(Path.Combine(root, "note.txt"), "needle");
            var host = new BuiltinAgentFileToolHost(root);

            var glob = await host.ExecuteAsync(Call("glob_files", new { pattern = "*.txt", limit = 10 }), CancellationToken.None);
            var grep = await host.ExecuteAsync(Call("grep_files", new { pattern = "needle", head_limit = 10 }), CancellationToken.None);

            Assert.True(glob.Ok);
            Assert.True(grep.Ok);
            Assert.Equal("glob_files", glob.ToolName);
            Assert.Equal("grep_files", grep.ToolName);
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task Notebook_edit_follows_the_sidecar_schema()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-file-host-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            await File.WriteAllTextAsync(Path.Combine(root, "note.ipynb"), "{\"nbformat\":4,\"nbformat_minor\":5,\"cells\":[{\"id\":\"first\",\"cell_type\":\"markdown\",\"metadata\":{},\"source\":\"old\"}]}");
            var host = new BuiltinAgentFileToolHost(root);
            Assert.True((await host.ExecuteAsync(Call("read_file", new { file_path = "note.ipynb" }), CancellationToken.None)).Ok);

            var edit = await host.ExecuteAsync(Call("notebook_edit", new
            {
                notebook_path = "note.ipynb", new_source = "new", edit_mode = "replace", cell_id = "first",
            }), CancellationToken.None);

            Assert.True(edit.Ok);
            Assert.Equal("notebook_edit", edit.ToolName);
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private static AgentToolCall Call(string name, object arguments) => new(
        Guid.NewGuid().ToString("N"), name, JsonSerializer.SerializeToElement(arguments));
}
