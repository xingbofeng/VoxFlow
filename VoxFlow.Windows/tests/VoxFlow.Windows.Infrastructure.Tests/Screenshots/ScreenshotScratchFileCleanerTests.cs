using VoxFlow.Windows.Infrastructure.Screenshots;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Screenshots;

public sealed class ScreenshotScratchFileCleanerTests
{
    [Fact]
    public void Inline_cleanup_deletes_only_stale_exactly_owned_files()
    {
        using var directory = new TemporaryDirectory();
        var cutoff = new DateTimeOffset(2026, 7, 14, 1, 0, 0, TimeSpan.Zero);
        var stale = Create(
            directory.Path,
            $"inline-{Guid.NewGuid():N}-{Guid.NewGuid():N}.png",
            cutoff.AddMinutes(-1));
        var recent = Create(
            directory.Path,
            $"inline-{Guid.NewGuid():N}-{Guid.NewGuid():N}.png",
            cutoff.AddMinutes(1));
        var export = Create(directory.Path, "inline-user-export.png", cutoff.AddDays(-1));
        var nearMatch = Create(
            directory.Path,
            $"inline-{Guid.NewGuid():N}-{Guid.NewGuid():N}-extra.png",
            cutoff.AddDays(-1));
        var nestedDirectory = Directory.CreateDirectory(Path.Combine(directory.Path, "nested"));
        var nested = Create(
            nestedDirectory.FullName,
            $"inline-{Guid.NewGuid():N}-{Guid.NewGuid():N}.png",
            cutoff.AddDays(-1));

        var deleted = new ScreenshotScratchFileCleaner()
            .CleanupInlineTranslationFiles(directory.Path, cutoff);

        Assert.Equal(1, deleted);
        Assert.False(File.Exists(stale));
        Assert.True(File.Exists(recent));
        Assert.True(File.Exists(export));
        Assert.True(File.Exists(nearMatch));
        Assert.True(File.Exists(nested));
    }

    [Fact]
    public void Orientation_cleanup_deletes_only_stale_guid_pngs()
    {
        using var directory = new TemporaryDirectory();
        var cutoff = new DateTimeOffset(2026, 7, 14, 1, 0, 0, TimeSpan.Zero);
        var stale = Create(directory.Path, $"{Guid.NewGuid():N}.png", cutoff.AddHours(-1));
        var recent = Create(directory.Path, $"{Guid.NewGuid():N}.PNG", cutoff.AddMinutes(1));
        var userPng = Create(directory.Path, "scan.png", cutoff.AddDays(-1));
        var other = Create(directory.Path, $"{Guid.NewGuid():N}.tmp", cutoff.AddDays(-1));

        var deleted = new ScreenshotScratchFileCleaner()
            .CleanupOrientationFiles(directory.Path, cutoff);

        Assert.Equal(1, deleted);
        Assert.False(File.Exists(stale));
        Assert.True(File.Exists(recent));
        Assert.True(File.Exists(userPng));
        Assert.True(File.Exists(other));
    }

    [Fact]
    public void Cleanup_requires_utc_cutoff_and_tolerates_missing_directory()
    {
        using var directory = new TemporaryDirectory();
        var missing = Path.Combine(directory.Path, "missing");
        var cleaner = new ScreenshotScratchFileCleaner();

        Assert.Equal(
            0,
            cleaner.CleanupOrientationFiles(
                missing,
                new DateTimeOffset(2026, 7, 14, 1, 0, 0, TimeSpan.Zero)));
        Assert.Throws<ArgumentException>(() => cleaner.CleanupInlineTranslationFiles(
            directory.Path,
            new DateTimeOffset(2026, 7, 14, 1, 0, 0, TimeSpan.FromHours(8))));
    }

    private static string Create(
        string directory,
        string fileName,
        DateTimeOffset lastWriteUtc)
    {
        var path = Path.Combine(directory, fileName);
        File.WriteAllBytes(path, [1, 2, 3]);
        File.SetLastWriteTimeUtc(path, lastWriteUtc.UtcDateTime);
        return path;
    }
}
