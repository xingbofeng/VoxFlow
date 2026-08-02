using VoxFlow.Windows.Application.Screenshot;
using VoxFlow.Windows.Infrastructure.Screenshots;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Screenshots;

public sealed class FileScreenshotAssetStoreTests
{
    [Fact]
    public async Task Save_writes_original_rendered_and_thumbnail_atomically_under_screenshots()
    {
        using var directory = new TemporaryDirectory();
        var store = new FileScreenshotAssetStore(directory.Path);

        var request = new ScreenshotAssetWriteRequest("record-1", Png(1), Png(2), Png(3));
        Assert.True(request.TranslatedPng.IsEmpty);
        var assets = await store.SaveAsync(
            request,
            CancellationToken.None);

        Assert.All(
            new[] { assets.OriginalImagePath, assets.RenderedImagePath, assets.ThumbnailPath },
            path => Assert.StartsWith("Screenshots/", path, StringComparison.Ordinal));
        Assert.DoesNotContain("AgentRuntime", assets.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.Equal(Png(1), await File.ReadAllBytesAsync(store.ResolveAbsolutePath(assets.OriginalImagePath)));
        Assert.Equal(Png(2), await File.ReadAllBytesAsync(store.ResolveAbsolutePath(assets.RenderedImagePath)));
        Assert.Equal(Png(3), await File.ReadAllBytesAsync(store.ResolveAbsolutePath(assets.ThumbnailPath)));
        Assert.Empty(Directory.EnumerateFiles(
            Path.Combine(directory.Path, "Screenshots"),
            "*.tmp-*",
            SearchOption.AllDirectories));
    }

    [Fact]
    public async Task Partial_save_failure_removes_only_files_created_by_that_attempt()
    {
        using var directory = new TemporaryDirectory();
        var store = new FileScreenshotAssetStore(directory.Path);
        var first = await store.SaveAsync(
            new ScreenshotAssetWriteRequest("same-id", Png(1), Png(2), Png(3)),
            CancellationToken.None);
        File.Delete(store.ResolveAbsolutePath(first.OriginalImagePath));
        File.Delete(store.ResolveAbsolutePath(first.ThumbnailPath));

        await Assert.ThrowsAsync<IOException>(() => store.SaveAsync(
            new ScreenshotAssetWriteRequest("same-id", Png(4), Png(5), Png(6)),
            CancellationToken.None));

        Assert.False(File.Exists(store.ResolveAbsolutePath(first.OriginalImagePath)));
        Assert.Equal(Png(2), await File.ReadAllBytesAsync(store.ResolveAbsolutePath(first.RenderedImagePath)));
        Assert.False(File.Exists(store.ResolveAbsolutePath(first.ThumbnailPath)));
        Assert.Empty(Directory.EnumerateFiles(
            Path.Combine(directory.Path, "Screenshots"),
            "*.tmp-*",
            SearchOption.AllDirectories));
    }

    [Fact]
    public async Task Cleanup_deletes_only_old_unreferenced_managed_files_and_temps()
    {
        using var directory = new TemporaryDirectory();
        var store = new FileScreenshotAssetStore(directory.Path);
        var keep = await store.SaveAsync(
            new ScreenshotAssetWriteRequest("keep", Png(1), Png(2), Png(3)),
            CancellationToken.None);
        var orphan = await store.SaveAsync(
            new ScreenshotAssetWriteRequest("orphan", Png(4), Png(5), Png(6)),
            CancellationToken.None);
        var cutoff = new DateTimeOffset(2026, 7, 13, 8, 0, 0, TimeSpan.Zero);
        foreach (var path in Paths(orphan))
        {
            File.SetLastWriteTimeUtc(store.ResolveAbsolutePath(path), cutoff.AddHours(-1).UtcDateTime);
        }
        var recentTemp = Path.Combine(directory.Path, "Screenshots", "recent.tmp-token");
        var oldTemp = Path.Combine(directory.Path, "Screenshots", "old.tmp-token");
        await File.WriteAllBytesAsync(recentTemp, [1]);
        await File.WriteAllBytesAsync(oldTemp, [1]);
        File.SetLastWriteTimeUtc(recentTemp, cutoff.AddMinutes(1).UtcDateTime);
        File.SetLastWriteTimeUtc(oldTemp, cutoff.AddHours(-1).UtcDateTime);
        var userExport = Path.Combine(directory.Path, "user-save-as.png");
        await File.WriteAllBytesAsync(userExport, Png(9));

        var deleted = await store.CleanupOrphansAsync(
            Paths(keep).ToHashSet(StringComparer.Ordinal),
            cutoff,
            CancellationToken.None);

        Assert.Equal(4, deleted);
        Assert.All(Paths(keep), path => Assert.True(File.Exists(store.ResolveAbsolutePath(path))));
        Assert.All(Paths(orphan), path => Assert.False(File.Exists(store.ResolveAbsolutePath(path))));
        Assert.True(File.Exists(recentTemp));
        Assert.False(File.Exists(oldTemp));
        Assert.True(File.Exists(userExport));
    }

    [Fact]
    public async Task Delete_is_idempotent_and_path_resolution_rejects_escape_or_agent_paths()
    {
        using var directory = new TemporaryDirectory();
        var store = new FileScreenshotAssetStore(directory.Path);
        var assets = await store.SaveAsync(
            new ScreenshotAssetWriteRequest("delete", Png(1), Png(2), Png(3)),
            CancellationToken.None);

        var first = await store.DeleteAsync(assets, CancellationToken.None);
        var second = await store.DeleteAsync(assets, CancellationToken.None);

        Assert.True(first.IsComplete);
        Assert.Equal(3, first.DeletedCount);
        Assert.True(second.IsComplete);
        Assert.Equal(0, second.DeletedCount);
        Assert.All(Paths(assets), path => Assert.False(File.Exists(store.ResolveAbsolutePath(path))));
        Assert.Throws<ArgumentException>(() => store.ResolveAbsolutePath("Screenshots/../outside.png"));
        Assert.Throws<ArgumentException>(() => store.ResolveAbsolutePath("AgentRuntime/capture.png"));
        Assert.Throws<ArgumentException>(() => store.ResolveAbsolutePath(@"C:\outside.png"));
    }

    [Fact]
    public async Task Delete_reports_a_locked_managed_asset_and_succeeds_on_retry()
    {
        using var directory = new TemporaryDirectory();
        var store = new FileScreenshotAssetStore(directory.Path);
        var assets = await store.SaveAsync(
            new ScreenshotAssetWriteRequest("retry-delete", Png(1), Png(2), Png(3)),
            CancellationToken.None);
        var lockedPath = store.ResolveAbsolutePath(assets.RenderedImagePath);
        ScreenshotAssetDeleteResult blocked;
        await using (var locked = new FileStream(
            lockedPath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.None))
        {
            blocked = await store.DeleteAsync(assets, CancellationToken.None);
        }

        Assert.False(blocked.IsComplete);
        Assert.Equal([assets.RenderedImagePath], blocked.RemainingRelativePaths);
        Assert.True(File.Exists(lockedPath));

        var retried = await store.DeleteAsync(assets, CancellationToken.None);

        Assert.True(retried.IsComplete);
        Assert.Equal(1, retried.DeletedCount);
        Assert.False(File.Exists(lockedPath));
    }

    private static string[] Paths(ScreenshotAssetSet assets) =>
        [assets.OriginalImagePath, assets.RenderedImagePath, assets.ThumbnailPath];

    private static byte[] Png(byte marker) =>
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, marker];
}
