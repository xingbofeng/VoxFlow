namespace VoxFlow.Windows.Application.Screenshot;

public sealed class ScreenshotAssetWriteRequest
{
    public ScreenshotAssetWriteRequest(
        string screenshotId,
        ReadOnlyMemory<byte> originalPng,
        ReadOnlyMemory<byte> renderedPng,
        ReadOnlyMemory<byte> thumbnailPng,
        ReadOnlyMemory<byte> translatedPng = default)
    {
        ScreenshotId = ScreenshotValueValidation.RequireId(screenshotId);
        OriginalPng = RequireBytes(originalPng, nameof(originalPng));
        RenderedPng = RequireBytes(renderedPng, nameof(renderedPng));
        ThumbnailPng = RequireBytes(thumbnailPng, nameof(thumbnailPng));
        TranslatedPng = translatedPng.IsEmpty
            ? default
            : RequireBytes(translatedPng, nameof(translatedPng));
    }

    public string ScreenshotId { get; }

    public ReadOnlyMemory<byte> OriginalPng { get; }

    public ReadOnlyMemory<byte> RenderedPng { get; }

    public ReadOnlyMemory<byte> ThumbnailPng { get; }

    public ReadOnlyMemory<byte> TranslatedPng { get; }

    public override string ToString() =>
        $"ScreenshotAssetWriteRequest {{ ScreenshotId = {ScreenshotId}, " +
        $"HasTranslatedImage = {!TranslatedPng.IsEmpty} }}";

    private static ReadOnlyMemory<byte> RequireBytes(
        ReadOnlyMemory<byte> value,
        string parameterName)
    {
        if (value.IsEmpty)
        {
            throw new ArgumentException("PNG content is required.", parameterName);
        }
        return value.ToArray();
    }
}

public sealed class ScreenshotAssetSet
{
    public ScreenshotAssetSet(
        string originalImagePath,
        string renderedImagePath,
        string thumbnailPath,
        string? translatedImagePath,
        long renderedFileSizeBytes)
    {
        OriginalImagePath = ScreenshotValueValidation.RequireManagedPath(
            originalImagePath,
            nameof(originalImagePath));
        RenderedImagePath = ScreenshotValueValidation.RequireManagedPath(
            renderedImagePath,
            nameof(renderedImagePath));
        ThumbnailPath = ScreenshotValueValidation.RequireManagedPath(
            thumbnailPath,
            nameof(thumbnailPath));
        TranslatedImagePath = ScreenshotValueValidation.OptionalManagedPath(
            translatedImagePath,
            nameof(translatedImagePath));
        ArgumentOutOfRangeException.ThrowIfNegative(renderedFileSizeBytes);
        RenderedFileSizeBytes = renderedFileSizeBytes;
    }

    public string OriginalImagePath { get; }

    public string RenderedImagePath { get; }

    public string ThumbnailPath { get; }

    public string? TranslatedImagePath { get; }

    public long RenderedFileSizeBytes { get; }

    public IReadOnlyList<string> AllRelativePaths =>
        TranslatedImagePath is null
            ? [OriginalImagePath, RenderedImagePath, ThumbnailPath]
            : [OriginalImagePath, RenderedImagePath, ThumbnailPath, TranslatedImagePath];

    public override string ToString() =>
        $"ScreenshotAssetSet {{ AssetCount = {AllRelativePaths.Count}, " +
        $"RenderedFileSizeBytes = {RenderedFileSizeBytes} }}";
}

public sealed class ScreenshotAssetDeleteResult
{
    public ScreenshotAssetDeleteResult(
        int deletedCount,
        IReadOnlyList<string>? remainingRelativePaths = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(deletedCount);
        DeletedCount = deletedCount;
        RemainingRelativePaths = Array.AsReadOnly(
            (remainingRelativePaths ?? [])
                .Select(path => ScreenshotValueValidation.RequireManagedPath(
                    path,
                    nameof(remainingRelativePaths)))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray());
    }

    public int DeletedCount { get; }

    public IReadOnlyList<string> RemainingRelativePaths { get; }

    public bool IsComplete => RemainingRelativePaths.Count == 0;
}

public interface IScreenshotAssetStore
{
    Task<ScreenshotAssetSet> SaveAsync(
        ScreenshotAssetWriteRequest request,
        CancellationToken cancellationToken);

    Task<ScreenshotAssetDeleteResult> DeleteAsync(
        ScreenshotAssetSet assets,
        CancellationToken cancellationToken);

    string ResolveAbsolutePath(string relativePath);

    Task<int> CleanupOrphansAsync(
        IReadOnlySet<string> referencedRelativePaths,
        DateTimeOffset deleteBeforeUtcExclusive,
        CancellationToken cancellationToken);
}
