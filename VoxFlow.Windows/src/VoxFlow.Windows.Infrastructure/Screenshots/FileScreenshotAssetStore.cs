using System.Security.Cryptography;
using System.Text;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.Infrastructure.Screenshots;

public sealed class FileScreenshotAssetStore : IScreenshotAssetStore
{
    private static readonly byte[] PngSignature =
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

    private readonly string applicationDataRoot;
    private readonly string screenshotsRoot;

    public FileScreenshotAssetStore(string applicationDataRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(applicationDataRoot);
        this.applicationDataRoot = Path.GetFullPath(applicationDataRoot);
        screenshotsRoot = Path.Combine(this.applicationDataRoot, "Screenshots");
    }

    public async Task<ScreenshotAssetSet> SaveAsync(
        ScreenshotAssetWriteRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();
        ValidatePng(request.OriginalPng, nameof(request.OriginalPng));
        ValidatePng(request.RenderedPng, nameof(request.RenderedPng));
        ValidatePng(request.ThumbnailPng, nameof(request.ThumbnailPng));
        if (!request.TranslatedPng.IsEmpty)
        {
            ValidatePng(request.TranslatedPng, nameof(request.TranslatedPng));
        }

        var key = Convert.ToHexString(
            SHA256.HashData(Encoding.UTF8.GetBytes(request.ScreenshotId)))
            .ToLowerInvariant();
        var directory = Path.Combine(screenshotsRoot, key[..2], key[2..4]);
        Directory.CreateDirectory(directory);
        var original = Path.Combine(directory, key + "-original.png");
        var rendered = Path.Combine(directory, key + ".png");
        var thumbnail = Path.Combine(directory, key + "-thumbnail.png");
        var translatedPath = request.TranslatedPng.IsEmpty
            ? null
            : Path.Combine(directory, key + "-translated.png");
        List<string> created = [];
        List<string> temporary = [];

        try
        {
            await WriteNewAsync(original, request.OriginalPng, created, temporary, cancellationToken)
                .ConfigureAwait(false);
            await WriteNewAsync(rendered, request.RenderedPng, created, temporary, cancellationToken)
                .ConfigureAwait(false);
            await WriteNewAsync(thumbnail, request.ThumbnailPng, created, temporary, cancellationToken)
                .ConfigureAwait(false);
            if (!request.TranslatedPng.IsEmpty && translatedPath is not null)
            {
                await WriteNewAsync(
                    translatedPath,
                    request.TranslatedPng,
                    created,
                    temporary,
                    cancellationToken).ConfigureAwait(false);
            }

            return new ScreenshotAssetSet(
                ToRelative(original),
                ToRelative(rendered),
                ToRelative(thumbnail),
                translatedPath is null ? null : ToRelative(translatedPath),
                request.RenderedPng.Length);
        }
        catch
        {
            DeleteFiles(temporary);
            DeleteFiles(created);
            throw;
        }
    }

    public Task<ScreenshotAssetDeleteResult> DeleteAsync(
        ScreenshotAssetSet assets,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(assets);
        cancellationToken.ThrowIfCancellationRequested();
        var deleted = 0;
        List<string> remaining = [];
        foreach (var relativePath in assets.AllRelativePaths)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var path = ResolveAbsolutePath(relativePath);
            try
            {
                var existed = File.Exists(path);
                File.Delete(path);
                if (existed)
                {
                    deleted++;
                }
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                remaining.Add(relativePath);
            }
        }
        return Task.FromResult(new ScreenshotAssetDeleteResult(deleted, remaining));
    }

    public string ResolveAbsolutePath(string relativePath)
    {
        var normalized = RequireManagedRelativePath(relativePath);
        var absolute = Path.GetFullPath(Path.Combine(
            applicationDataRoot,
            normalized.Replace('/', Path.DirectorySeparatorChar)));
        var requiredPrefix = screenshotsRoot.TrimEnd(
            Path.DirectorySeparatorChar,
            Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!absolute.StartsWith(requiredPrefix, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException(
                "The path escapes the managed screenshot store.",
                nameof(relativePath));
        }
        return absolute;
    }

    public Task<int> CleanupOrphansAsync(
        IReadOnlySet<string> referencedRelativePaths,
        DateTimeOffset deleteBeforeUtcExclusive,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(referencedRelativePaths);
        if (deleteBeforeUtcExclusive.Offset != TimeSpan.Zero)
        {
            throw new ArgumentException(
                "A UTC cleanup cutoff is required.",
                nameof(deleteBeforeUtcExclusive));
        }
        cancellationToken.ThrowIfCancellationRequested();
        if (!Directory.Exists(screenshotsRoot))
        {
            return Task.FromResult(0);
        }

        var referenced = referencedRelativePaths
            .Select(RequireManagedRelativePath)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var deleted = 0;
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint,
            ReturnSpecialDirectories = false,
        };
        foreach (var path in Directory.EnumerateFiles(screenshotsRoot, "*", options))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var fileName = Path.GetFileName(path);
            var isTemporary = fileName.Contains(".tmp-", StringComparison.Ordinal);
            var isManagedPng = fileName.EndsWith(".png", StringComparison.OrdinalIgnoreCase);
            if (!isTemporary && !isManagedPng)
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
            var relative = ToRelative(path);
            if (!isTemporary && referenced.Contains(relative))
            {
                continue;
            }
            if (TryDelete(path))
            {
                deleted++;
            }
        }

        return Task.FromResult(deleted);
    }

    private static async Task WriteNewAsync(
        string destination,
        ReadOnlyMemory<byte> content,
        ICollection<string> created,
        ICollection<string> temporary,
        CancellationToken cancellationToken)
    {
        var temp = destination + ".tmp-" + Guid.NewGuid().ToString("N");
        temporary.Add(temp);
        await using (var stream = new FileStream(
            temp,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 64 * 1024,
            FileOptions.Asynchronous | FileOptions.WriteThrough))
        {
            await stream.WriteAsync(content, cancellationToken).ConfigureAwait(false);
            await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
            stream.Flush(flushToDisk: true);
        }
        cancellationToken.ThrowIfCancellationRequested();
        File.Move(temp, destination, overwrite: false);
        _ = temporary.Remove(temp);
        created.Add(destination);
    }

    private static void ValidatePng(ReadOnlyMemory<byte> value, string parameterName)
    {
        if (value.Length < PngSignature.Length
            || !value.Span[..PngSignature.Length].SequenceEqual(PngSignature))
        {
            throw new ArgumentException("A PNG byte stream is required.", parameterName);
        }
    }

    private string ToRelative(string absolutePath) =>
        Path.GetRelativePath(applicationDataRoot, absolutePath)
            .Replace(Path.DirectorySeparatorChar, '/')
            .Replace(Path.AltDirectorySeparatorChar, '/');

    private static string RequireManagedRelativePath(string relativePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(relativePath);
        var normalized = relativePath.Replace('\\', '/').Trim();
        if (Path.IsPathRooted(normalized)
            || normalized.Contains(':', StringComparison.Ordinal)
            || !normalized.StartsWith("Screenshots/", StringComparison.Ordinal)
            || normalized.Split('/').Any(segment => segment is "" or "." or ".."))
        {
            throw new ArgumentException(
                "A managed Screenshots relative path is required.",
                nameof(relativePath));
        }
        return normalized;
    }

    private static void DeleteFiles(IEnumerable<string> paths)
    {
        foreach (var path in paths)
        {
            _ = TryDelete(path);
        }
    }

    private static bool TryDelete(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return false;
            }
            File.Delete(path);
            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
