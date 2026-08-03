using VoxFlow.Windows.Application.Agent;

namespace VoxFlow.Windows.Application.Tests;

public sealed class AgentFileReadServiceTests
{
    [Fact]
    public async Task Reads_small_utf8_file_and_rejects_escape()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            await File.WriteAllTextAsync(Path.Combine(root, "a.txt"), "hello");
            var service = new AgentFileReadService(new AgentPathPolicy());
            Assert.Equal("hello", (await service.ReadAsync(root, "a.txt", CancellationToken.None)).Content);
            Assert.Equal("outside_workspace", (await service.ReadAsync(root, "..\\x", CancellationToken.None)).ErrorCode);
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Read_ranges_are_bounded_and_only_a_complete_read_unblocks_write_state()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            await File.WriteAllTextAsync(Path.Combine(root, "lines.txt"), "one\ntwo\nthree\nfour");
            var reads = new AgentFileReadState();
            var service = new AgentFileReadService(new AgentPathPolicy(), reads);

            var firstPage = await service.ReadAsync(root, "lines.txt", CancellationToken.None, limit: 2);
            var secondPage = await service.ReadAsync(root, "lines.txt", CancellationToken.None, lineOffset: 3, limit: 2);
            var chars = await service.ReadAsync(root, "lines.txt", CancellationToken.None, charOffset: 4, limit: 3);

            Assert.True(firstPage.Ok);
            Assert.Equal("one" + Environment.NewLine + "two", firstPage.Content);
            Assert.True(firstPage.IsTruncated);
            Assert.Equal(3, firstPage.NextLineOffset);
            Assert.False(firstPage.IsFullRead);
            Assert.True(secondPage.IsFullRead is false);
            Assert.Equal("two", chars.Content);
            Assert.Equal(7, chars.NextCharOffset);
            Assert.False(reads.WasReadUnchanged(Path.Combine(root, "lines.txt")));

            var full = await service.ReadAsync(root, "lines.txt", CancellationToken.None, limit: AgentFileReadService.MaximumLimit);
            Assert.True(full.IsFullRead);
            Assert.True(reads.WasReadUnchanged(Path.Combine(root, "lines.txt")));
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Directories_binary_oversized_and_invalid_offsets_are_safe_failures()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            await File.WriteAllBytesAsync(Path.Combine(root, "binary.bin"), [0x41, 0x00, 0x42]);
            await File.WriteAllBytesAsync(Path.Combine(root, "large.txt"), new byte[AgentFileReadService.MaxBytes + 1]);
            await File.WriteAllTextAsync(Path.Combine(root, "small.txt"), "a");
            var service = new AgentFileReadService(new AgentPathPolicy());

            Assert.Equal("path_is_directory", (await service.ReadAsync(root, ".", CancellationToken.None)).ErrorCode);
            Assert.Equal("file_binary", (await service.ReadAsync(root, "binary.bin", CancellationToken.None)).ErrorCode);
            Assert.Equal("file_too_large", (await service.ReadAsync(root, "large.txt", CancellationToken.None)).ErrorCode);
            Assert.Equal("invalid_read_range", (await service.ReadAsync(root, "small.txt", CancellationToken.None, lineOffset: 0)).ErrorCode);
            Assert.Equal("ambiguous_read_range", (await service.ReadAsync(root, "small.txt", CancellationToken.None, lineOffset: 1, charOffset: 0)).ErrorCode);
            Assert.Equal("line_offset_out_of_range", (await service.ReadAsync(root, "small.txt", CancellationToken.None, lineOffset: 3)).ErrorCode);
        }
        finally { Directory.Delete(root, true); }
    }
}
