namespace VoxFlow.Windows.Infrastructure.Screenshots;

/// <summary>
/// Removes only VoxFlow-owned screenshot scratch PNGs that are old enough not
/// to belong to an active capture. User exports and managed screenshot assets
/// are intentionally outside these narrowly matched filename contracts.
/// </summary>
public sealed class ScreenshotScratchFileCleaner
{
    public int CleanupInlineTranslationFiles(
        string directory,
        DateTimeOffset deleteBeforeUtcExclusive) =>
        Cleanup(directory, deleteBeforeUtcExclusive, IsInlineTranslationFile);

    public int CleanupOrientationFiles(
        string directory,
        DateTimeOffset deleteBeforeUtcExclusive) =>
        Cleanup(directory, deleteBeforeUtcExclusive, IsOrientationFile);

    private static int Cleanup(
        string directory,
        DateTimeOffset deleteBeforeUtcExclusive,
        Func<string, bool> ownsFile)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        ArgumentNullException.ThrowIfNull(ownsFile);
        if (deleteBeforeUtcExclusive.Offset != TimeSpan.Zero)
        {
            throw new ArgumentException(
                "A UTC cleanup cutoff is required.",
                nameof(deleteBeforeUtcExclusive));
        }

        var root = Path.GetFullPath(directory);
        if (!Directory.Exists(root))
        {
            return 0;
        }

        var deleted = 0;
        IReadOnlyList<string> files;
        try
        {
            files = Directory.GetFiles(
                root,
                "*.png",
                new EnumerationOptions
                {
                    RecurseSubdirectories = false,
                    IgnoreInaccessible = true,
                    AttributesToSkip = FileAttributes.ReparsePoint,
                    ReturnSpecialDirectories = false,
                });
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return 0;
        }

        foreach (var path in files)
        {
            if (!ownsFile(Path.GetFileName(path)))
            {
                continue;
            }

            DateTime lastWriteUtc;
            try
            {
                lastWriteUtc = File.GetLastWriteTimeUtc(path);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                continue;
            }
            if (lastWriteUtc >= deleteBeforeUtcExclusive.UtcDateTime)
            {
                continue;
            }

            try
            {
                File.Delete(path);
                deleted++;
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                // A live OCR process can still own the file. A later startup retries it.
            }
        }

        return deleted;
    }

    private static bool IsInlineTranslationFile(string fileName)
    {
        const string prefix = "inline-";
        const string extension = ".png";
        if (!fileName.StartsWith(prefix, StringComparison.Ordinal)
            || !fileName.EndsWith(extension, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var stem = fileName[prefix.Length..^extension.Length];
        var separator = stem.IndexOf('-');
        return separator == 32
            && stem.LastIndexOf('-') == separator
            && IsGuidToken(stem[..separator])
            && IsGuidToken(stem[(separator + 1)..]);
    }

    private static bool IsOrientationFile(string fileName)
    {
        const string extension = ".png";
        return fileName.EndsWith(extension, StringComparison.OrdinalIgnoreCase)
            && IsGuidToken(fileName[..^extension.Length]);
    }

    private static bool IsGuidToken(string value) =>
        value.Length == 32
        && Guid.TryParseExact(value, "N", out _);
}
