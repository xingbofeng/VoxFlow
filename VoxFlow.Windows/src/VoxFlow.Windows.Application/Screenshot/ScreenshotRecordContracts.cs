using System.Text;

namespace VoxFlow.Windows.Application.Screenshot;

public enum ScreenshotTransformOperation
{
    Refinement,
    Translation,
    Summary,
}

public sealed class ScreenshotRecord
{
    public const string ScreenshotMediaType = "screenshot";

    public ScreenshotRecord(
        string id,
        string originalImagePath,
        string renderedImagePath,
        string thumbnailPath,
        int widthPixels,
        int heightPixels,
        long fileSizeBytes,
        string ocrText,
        DateTimeOffset createdAtUtc,
        string? translatedImagePath = null,
        string? sourceDisplayId = null,
        string? sourceWindowTitle = null,
        string? refinedText = null,
        string? translatedText = null,
        string? summaryText = null,
        bool isFavorite = false,
        DateTimeOffset? updatedAtUtc = null,
        DateTimeOffset? deletedAtUtc = null)
    {
        Id = ScreenshotValueValidation.RequireId(id);
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
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(widthPixels);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(heightPixels);
        ArgumentOutOfRangeException.ThrowIfNegative(fileSizeBytes);
        ArgumentNullException.ThrowIfNull(ocrText);
        ScreenshotValueValidation.RequireUtc(createdAtUtc, nameof(createdAtUtc));
        var resolvedUpdatedAt = updatedAtUtc ?? createdAtUtc;
        ScreenshotValueValidation.RequireUtc(resolvedUpdatedAt, nameof(updatedAtUtc));
        if (resolvedUpdatedAt < createdAtUtc)
        {
            throw new ArgumentOutOfRangeException(
                nameof(updatedAtUtc),
                "The updated time cannot precede creation.");
        }
        if (deletedAtUtc is { } deleted)
        {
            ScreenshotValueValidation.RequireUtc(deleted, nameof(deletedAtUtc));
            if (deleted < createdAtUtc)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(deletedAtUtc),
                    "The deleted time cannot precede creation.");
            }
        }

        WidthPixels = widthPixels;
        HeightPixels = heightPixels;
        FileSizeBytes = fileSizeBytes;
        SourceDisplayId = ScreenshotValueValidation.OptionalText(sourceDisplayId);
        SourceWindowTitle = ScreenshotValueValidation.OptionalText(sourceWindowTitle);
        OcrText = ocrText;
        RefinedText = ScreenshotValueValidation.OptionalText(refinedText);
        TranslatedText = ScreenshotValueValidation.OptionalText(translatedText);
        SummaryText = ScreenshotValueValidation.OptionalText(summaryText);
        IsFavorite = isFavorite;
        CreatedAtUtc = createdAtUtc;
        UpdatedAtUtc = resolvedUpdatedAt;
        DeletedAtUtc = deletedAtUtc;
    }

    public string Id { get; }

    public string MediaType => ScreenshotMediaType;

    public string OriginalImagePath { get; }

    public string RenderedImagePath { get; }

    public string ThumbnailPath { get; }

    public string? TranslatedImagePath { get; }

    public int WidthPixels { get; }

    public int HeightPixels { get; }

    public long FileSizeBytes { get; }

    public string? SourceDisplayId { get; }

    public string? SourceWindowTitle { get; }

    public string OcrText { get; }

    public string? RefinedText { get; }

    public string? TranslatedText { get; }

    public string? SummaryText { get; }

    public int CharacterCount => OcrText.Length;

    public bool IsFavorite { get; }

    public DateTimeOffset CreatedAtUtc { get; }

    public DateTimeOffset UpdatedAtUtc { get; }

    public DateTimeOffset? DeletedAtUtc { get; }

    public override string ToString() =>
        $"ScreenshotRecord {{ Id = {Id}, Size = {WidthPixels}x{HeightPixels}, " +
        $"CharacterCount = {CharacterCount}, Favorite = {IsFavorite}, Deleted = {DeletedAtUtc is not null} }}";
}

public sealed class ScreenshotRecordQuery
{
    public ScreenshotRecordQuery(
        string? searchText,
        bool favoritesOnly,
        int offset,
        int limit)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(offset);
        if (limit is < 1 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(limit));
        }

        SearchText = string.IsNullOrWhiteSpace(searchText) ? null : searchText.Trim();
        FavoritesOnly = favoritesOnly;
        Offset = offset;
        Limit = limit;
    }

    public string? SearchText { get; }

    public bool FavoritesOnly { get; }

    public int Offset { get; }

    public int Limit { get; }
}

public sealed record ScreenshotRecordPage(
    IReadOnlyList<ScreenshotRecord> Items,
    int TotalCount,
    int Offset,
    int Limit);

public sealed class ScreenshotRecordAggregateQuery
{
    public ScreenshotRecordAggregateQuery(
        string? searchText,
        bool favoritesOnly,
        DateTimeOffset localDayStartUtc,
        DateTimeOffset localDayEndUtcExclusive)
    {
        ScreenshotValueValidation.RequireUtc(
            localDayStartUtc,
            nameof(localDayStartUtc));
        ScreenshotValueValidation.RequireUtc(
            localDayEndUtcExclusive,
            nameof(localDayEndUtcExclusive));
        if (localDayEndUtcExclusive <= localDayStartUtc)
        {
            throw new ArgumentOutOfRangeException(
                nameof(localDayEndUtcExclusive),
                "The local-day end must follow its start.");
        }

        SearchText = string.IsNullOrWhiteSpace(searchText) ? null : searchText.Trim();
        FavoritesOnly = favoritesOnly;
        LocalDayStartUtc = localDayStartUtc;
        LocalDayEndUtcExclusive = localDayEndUtcExclusive;
    }

    public string? SearchText { get; }

    public bool FavoritesOnly { get; }

    public DateTimeOffset LocalDayStartUtc { get; }

    public DateTimeOffset LocalDayEndUtcExclusive { get; }
}

public sealed record ScreenshotRecordAggregate(
    int TotalCount,
    int TodayCount,
    int FavoriteCount);

public sealed record ScreenshotRecordStats(
    int TotalCount,
    int FavoriteCount,
    long TotalFileSizeBytes,
    long TotalCharacterCount);

public interface IScreenshotRecordRepository
{
    void Add(ScreenshotRecord record);

    ScreenshotRecord? Get(string id, bool includeDeleted = false);

    ScreenshotRecordPage Search(ScreenshotRecordQuery query);

    ScreenshotRecordAggregate GetAggregate(ScreenshotRecordAggregateQuery query);

    ScreenshotRecordStats GetStats();

    IReadOnlyList<ScreenshotRecord> ListDeletedBefore(
        DateTimeOffset deletedBeforeUtcExclusive);

    IReadOnlySet<string> ListReferencedAssetPaths();

    bool SetFavorite(string id, bool isFavorite, DateTimeOffset updatedAtUtc);

    bool SoftDelete(string id, DateTimeOffset deletedAtUtc);

    bool PurgeDeleted(
        string id,
        DateTimeOffset deletedBeforeUtcExclusive);

    /// <summary>
    /// Replaces the canonical OCR text and atomically invalidates every value
    /// derived from the previous OCR revision.
    /// </summary>
    bool ReplaceOcrAndInvalidateTransforms(
        string id,
        string text,
        DateTimeOffset updatedAtUtc);

    bool UpdateTransform(
        string id,
        ScreenshotTransformOperation operation,
        string text,
        DateTimeOffset updatedAtUtc,
        string? translatedImagePath = null);
}

public static class ScreenshotSearchNormalizer
{
    public static string Normalize(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var normalized = value.Normalize(NormalizationForm.FormKC).ToUpperInvariant();
        var result = new StringBuilder(normalized.Length);
        var previousWasWhitespace = true;
        foreach (var character in normalized)
        {
            if (char.IsWhiteSpace(character))
            {
                if (!previousWasWhitespace)
                {
                    result.Append(' ');
                    previousWasWhitespace = true;
                }
                continue;
            }

            result.Append(character);
            previousWasWhitespace = false;
        }

        return result.ToString().Trim();
    }

    public static string ForRecord(
        string ocrText,
        string? refinedText,
        string? translatedText,
        string? summaryText) => Normalize(string.Join(
            '\n',
            new[] { ocrText, refinedText, translatedText, summaryText }
                .Where(value => !string.IsNullOrWhiteSpace(value))));
}

internal static class ScreenshotValueValidation
{
    public static string RequireId(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        var trimmed = value.Trim();
        if (trimmed.Length > 128
            || trimmed.Any(character => char.IsControl(character)
                || character is '/' or '\\' or ':'))
        {
            throw new ArgumentException("The screenshot ID is invalid.", nameof(value));
        }
        return trimmed;
    }

    public static string RequireManagedPath(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        var normalized = value.Replace('\\', '/').Trim();
        if (Path.IsPathRooted(normalized)
            || normalized.Contains(':', StringComparison.Ordinal)
            || !normalized.StartsWith("Screenshots/", StringComparison.Ordinal)
            || normalized.Split('/').Any(segment => segment is "" or "." or ".."))
        {
            throw new ArgumentException(
                "A managed Screenshots relative path is required.",
                parameterName);
        }
        return normalized;
    }

    public static string? OptionalManagedPath(string? value, string parameterName) =>
        string.IsNullOrWhiteSpace(value) ? null : RequireManagedPath(value, parameterName);

    public static string? OptionalText(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value;

    public static void RequireUtc(DateTimeOffset value, string parameterName)
    {
        if (value.Offset != TimeSpan.Zero)
        {
            throw new ArgumentException("A UTC timestamp is required.", parameterName);
        }
    }
}
