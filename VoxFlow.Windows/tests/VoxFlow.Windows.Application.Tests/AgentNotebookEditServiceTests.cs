using System.Text.Json;
using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentNotebookEditServiceTests
{
    [Fact]
    public async Task Replace_insert_and_delete_preserve_unknown_notebook_fields_after_a_full_read()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-notebook-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var path = Path.Combine(root, "demo.ipynb");
            await File.WriteAllTextAsync(path, """
            {"nbformat":4,"nbformat_minor":5,"metadata":{"language_info":{"name":"python"},"custom":{"keep":true}},"cells":[{"id":"first","cell_type":"code","metadata":{"tag":"keep"},"source":"print(1)","execution_count":7,"outputs":[{"output_type":"stream"}]}],"custom_top":"keep"}
            """);
            var paths = new AgentPathPolicy();
            var reads = new AgentFileReadState();
            var reader = new AgentFileReadService(paths, reads);
            Assert.True((await reader.ReadAsync(root, "demo.ipynb", CancellationToken.None)).Ok);
            var service = new AgentNotebookEditService(paths, reads);

            var replace = await service.EditAsync(root, "demo.ipynb", "print(2)", "replace", "first", null, CancellationToken.None);
            var insert = await service.EditAsync(root, "demo.ipynb", "# added", "insert", "cell-0", "markdown", CancellationToken.None);
            var delete = await service.EditAsync(root, "demo.ipynb", "ignored", "delete", "cell-0", null, CancellationToken.None);

            Assert.True(replace.Ok);
            Assert.True(insert.Ok);
            Assert.NotNull(insert.CellId);
            Assert.True(delete.Ok);
            using var document = JsonDocument.Parse(await File.ReadAllTextAsync(path));
            Assert.Equal("keep", document.RootElement.GetProperty("custom_top").GetString());
            Assert.True(document.RootElement.GetProperty("metadata").GetProperty("custom").GetProperty("keep").GetBoolean());
            var cell = Assert.Single(document.RootElement.GetProperty("cells").EnumerateArray());
            Assert.Equal("markdown", cell.GetProperty("cell_type").GetString());
            Assert.Equal("# added", cell.GetProperty("source").GetString());
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task Notebook_edits_require_full_read_and_reject_invalid_inputs()
    {
        var root = Path.Combine(Path.GetTempPath(), "voxflow-notebook-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            await File.WriteAllTextAsync(Path.Combine(root, "demo.ipynb"), "{\"cells\":[]}");
            var service = new AgentNotebookEditService(new AgentPathPolicy(), new AgentFileReadState());

            var unread = await service.EditAsync(root, "demo.ipynb", "x", "replace", "cell-0", null, CancellationToken.None);
            var nonNotebook = await service.EditAsync(root, "demo.txt", "x", "replace", "cell-0", null, CancellationToken.None);
            var invalidMode = await service.EditAsync(root, "demo.ipynb", "x", "move", "cell-0", null, CancellationToken.None);

            Assert.Equal("file_not_read_or_modified", unread.ErrorCode);
            Assert.Equal("not_notebook", nonNotebook.ErrorCode);
            Assert.Equal("invalid_edit_mode", invalidMode.ErrorCode);
        }
        finally { Directory.Delete(root, recursive: true); }
    }
}
