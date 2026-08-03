using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Screenshot;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteScreenshotRecordRepository : IScreenshotRecordRepository
{
    private const string SelectSql =
        "SELECT id, original_image_path, rendered_image_path, thumbnail_path, " +
        "translated_image_path, width_px, height_px, file_size_bytes, source_display_id, " +
        "source_window_title, ocr_text, refined_text, translated_text, summary_text, " +
        "is_favorite, created_at_unix_ms, updated_at_unix_ms, deleted_at_unix_ms " +
        "FROM screenshot_records";

    private readonly SqliteTransactionRunner transactionRunner;

    public SqliteScreenshotRecordRepository(SqliteTransactionRunner transactionRunner)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
    }

    public void Add(ScreenshotRecord record)
    {
        ArgumentNullException.ThrowIfNull(record);
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO screenshot_records(" +
                "id, media_type, original_image_path, rendered_image_path, thumbnail_path, " +
                "translated_image_path, width_px, height_px, file_size_bytes, source_display_id, " +
                "source_window_title, ocr_text, refined_text, translated_text, summary_text, " +
                "searchable_text, character_count, is_favorite, created_at_unix_ms, " +
                "updated_at_unix_ms, deleted_at_unix_ms" +
                ") VALUES (" +
                "$id, 'screenshot', $originalPath, $renderedPath, $thumbnailPath, " +
                "$translatedImagePath, $width, $height, $fileSize, $sourceDisplayId, " +
                "$sourceWindowTitle, $ocrText, $refinedText, $translatedText, $summaryText, " +
                "$searchableText, $characterCount, $favorite, $createdAt, $updatedAt, $deletedAt);";
            AddRecordParameters(command, record);
            command.ExecuteNonQuery();
            return 0;
        });
    }

    public ScreenshotRecord? Get(string id, bool includeDeleted = false)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        return transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = SelectSql +
                " WHERE id = $id" +
                (includeDeleted ? ";" : " AND deleted_at_unix_ms IS NULL;");
            command.Parameters.AddWithValue("$id", id.Trim());
            using var reader = command.ExecuteReader();
            return reader.Read() ? ReadRecord(reader) : null;
        });
    }

    public ScreenshotRecordPage Search(ScreenshotRecordQuery query)
    {
        ArgumentNullException.ThrowIfNull(query);
        return transactionRunner.Read(connection =>
        {
            var normalizedQuery = ScreenshotSearchNormalizer.Normalize(query.SearchText);
            var where =
                " WHERE deleted_at_unix_ms IS NULL" +
                " AND ($favoritesOnly = 0 OR is_favorite = 1)" +
                " AND ($query = '' OR searchable_text LIKE $like ESCAPE '\\')";
            using var countCommand = connection.CreateCommand();
            countCommand.CommandText = "SELECT COUNT(*) FROM screenshot_records" + where + ";";
            AddQueryParameters(countCommand, query, normalizedQuery);
            var total = Convert.ToInt32(
                countCommand.ExecuteScalar(),
                System.Globalization.CultureInfo.InvariantCulture);

            using var pageCommand = connection.CreateCommand();
            pageCommand.CommandText = SelectSql + where +
                " ORDER BY created_at_unix_ms DESC, id ASC LIMIT $limit OFFSET $offset;";
            AddQueryParameters(pageCommand, query, normalizedQuery);
            pageCommand.Parameters.AddWithValue("$limit", query.Limit);
            pageCommand.Parameters.AddWithValue("$offset", query.Offset);
            using var reader = pageCommand.ExecuteReader();
            List<ScreenshotRecord> records = [];
            while (reader.Read())
            {
                records.Add(ReadRecord(reader));
            }

            return new ScreenshotRecordPage(records, total, query.Offset, query.Limit);
        });
    }

    public ScreenshotRecordAggregate GetAggregate(ScreenshotRecordAggregateQuery query)
    {
        ArgumentNullException.ThrowIfNull(query);
        return transactionRunner.Read(connection =>
        {
            var normalizedQuery = ScreenshotSearchNormalizer.Normalize(query.SearchText);
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT COUNT(*), " +
                "COALESCE(SUM(CASE WHEN created_at_unix_ms >= $localDayStart " +
                "AND created_at_unix_ms < $localDayEnd THEN 1 ELSE 0 END), 0), " +
                "COALESCE(SUM(CASE WHEN is_favorite = 1 THEN 1 ELSE 0 END), 0) " +
                "FROM screenshot_records WHERE deleted_at_unix_ms IS NULL " +
                "AND ($favoritesOnly = 0 OR is_favorite = 1) " +
                "AND ($query = '' OR searchable_text LIKE $like ESCAPE '\\');";
            AddFilterParameters(
                command,
                query.FavoritesOnly,
                normalizedQuery);
            command.Parameters.AddWithValue(
                "$localDayStart",
                query.LocalDayStartUtc.ToUnixTimeMilliseconds());
            command.Parameters.AddWithValue(
                "$localDayEnd",
                query.LocalDayEndUtcExclusive.ToUnixTimeMilliseconds());
            using var reader = command.ExecuteReader();
            _ = reader.Read();
            return new ScreenshotRecordAggregate(
                reader.GetInt32(0),
                reader.GetInt32(1),
                reader.GetInt32(2));
        });
    }

    public ScreenshotRecordStats GetStats() =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT COUNT(*), COALESCE(SUM(is_favorite), 0), " +
                "COALESCE(SUM(file_size_bytes), 0), COALESCE(SUM(character_count), 0) " +
                "FROM screenshot_records WHERE deleted_at_unix_ms IS NULL;";
            using var reader = command.ExecuteReader();
            _ = reader.Read();
            return new ScreenshotRecordStats(
                reader.GetInt32(0),
                reader.GetInt32(1),
                reader.GetInt64(2),
                reader.GetInt64(3));
        });

    public IReadOnlyList<ScreenshotRecord> ListDeletedBefore(
        DateTimeOffset deletedBeforeUtcExclusive)
    {
        ScreenshotValueTimeValidation.RequireUtc(
            deletedBeforeUtcExclusive,
            nameof(deletedBeforeUtcExclusive));
        return transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = SelectSql +
                " WHERE deleted_at_unix_ms IS NOT NULL " +
                "AND deleted_at_unix_ms < $deletedBefore " +
                "ORDER BY deleted_at_unix_ms ASC, id ASC;";
            command.Parameters.AddWithValue(
                "$deletedBefore",
                deletedBeforeUtcExclusive.ToUnixTimeMilliseconds());
            using var reader = command.ExecuteReader();
            List<ScreenshotRecord> result = [];
            while (reader.Read())
            {
                result.Add(ReadRecord(reader));
            }
            return (IReadOnlyList<ScreenshotRecord>)result;
        });
    }

    public IReadOnlySet<string> ListReferencedAssetPaths() =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT original_image_path, rendered_image_path, thumbnail_path, " +
                "translated_image_path FROM screenshot_records;";
            using var reader = command.ExecuteReader();
            HashSet<string> result = new(StringComparer.OrdinalIgnoreCase);
            while (reader.Read())
            {
                result.Add(reader.GetString(0));
                result.Add(reader.GetString(1));
                result.Add(reader.GetString(2));
                if (!reader.IsDBNull(3))
                {
                    result.Add(reader.GetString(3));
                }
            }
            return (IReadOnlySet<string>)result;
        });

    public bool SetFavorite(
        string id,
        bool isFavorite,
        DateTimeOffset updatedAtUtc)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ScreenshotValueTimeValidation.RequireUtc(updatedAtUtc, nameof(updatedAtUtc));
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE screenshot_records SET is_favorite = $favorite, " +
                "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                "WHERE id = $id AND deleted_at_unix_ms IS NULL;";
            command.Parameters.AddWithValue("$favorite", isFavorite ? 1 : 0);
            command.Parameters.AddWithValue("$updatedAt", updatedAtUtc.ToUnixTimeMilliseconds());
            command.Parameters.AddWithValue("$id", id.Trim());
            return command.ExecuteNonQuery() == 1;
        });
    }

    public bool SoftDelete(string id, DateTimeOffset deletedAtUtc)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ScreenshotValueTimeValidation.RequireUtc(deletedAtUtc, nameof(deletedAtUtc));
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE screenshot_records SET deleted_at_unix_ms = $deletedAt, " +
                "updated_at_unix_ms = MAX(updated_at_unix_ms, $deletedAt) " +
                "WHERE id = $id AND deleted_at_unix_ms IS NULL " +
                "AND created_at_unix_ms <= $deletedAt;";
            command.Parameters.AddWithValue("$deletedAt", deletedAtUtc.ToUnixTimeMilliseconds());
            command.Parameters.AddWithValue("$id", id.Trim());
            return command.ExecuteNonQuery() == 1;
        });
    }

    public bool PurgeDeleted(
        string id,
        DateTimeOffset deletedBeforeUtcExclusive)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ScreenshotValueTimeValidation.RequireUtc(
            deletedBeforeUtcExclusive,
            nameof(deletedBeforeUtcExclusive));
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "DELETE FROM screenshot_records WHERE id = $id " +
                "AND deleted_at_unix_ms IS NOT NULL " +
                "AND deleted_at_unix_ms < $deletedBefore;";
            command.Parameters.AddWithValue("$id", id.Trim());
            command.Parameters.AddWithValue(
                "$deletedBefore",
                deletedBeforeUtcExclusive.ToUnixTimeMilliseconds());
            return command.ExecuteNonQuery() == 1;
        });
    }

    public bool ReplaceOcrAndInvalidateTransforms(
        string id,
        string text,
        DateTimeOffset updatedAtUtc)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentNullException.ThrowIfNull(text);
        ScreenshotValueTimeValidation.RequireUtc(updatedAtUtc, nameof(updatedAtUtc));
        var normalizedText = text.Trim();
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE screenshot_records SET ocr_text = $ocrText, " +
                "refined_text = NULL, translated_text = NULL, summary_text = NULL, " +
                "translated_image_path = NULL, character_count = $characterCount, " +
                "searchable_text = $searchableText, " +
                "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                "WHERE id = $id AND deleted_at_unix_ms IS NULL;";
            command.Parameters.AddWithValue("$ocrText", normalizedText);
            command.Parameters.AddWithValue("$characterCount", normalizedText.Length);
            command.Parameters.AddWithValue(
                "$searchableText",
                ScreenshotSearchNormalizer.ForRecord(
                    normalizedText,
                    refinedText: null,
                    translatedText: null,
                    summaryText: null));
            command.Parameters.AddWithValue("$updatedAt", updatedAtUtc.ToUnixTimeMilliseconds());
            command.Parameters.AddWithValue("$id", id.Trim());
            return command.ExecuteNonQuery() == 1;
        });
    }

    public bool UpdateTransform(
        string id,
        ScreenshotTransformOperation operation,
        string text,
        DateTimeOffset updatedAtUtc,
        string? translatedImagePath = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        if (!Enum.IsDefined(operation))
        {
            throw new ArgumentOutOfRangeException(nameof(operation));
        }
        ScreenshotValueTimeValidation.RequireUtc(updatedAtUtc, nameof(updatedAtUtc));
        var translatedPath = string.IsNullOrWhiteSpace(translatedImagePath)
            ? null
            : ValidateManagedPath(translatedImagePath);

        return transactionRunner.Write((connection, transaction) =>
        {
            var current = ReadTransformFields(connection, transaction, id.Trim());
            if (current is null)
            {
                return false;
            }

            var refinedText = operation == ScreenshotTransformOperation.Refinement
                ? text
                : current.RefinedText;
            var translatedText = operation == ScreenshotTransformOperation.Translation
                ? text
                : current.TranslatedText;
            var summaryText = operation == ScreenshotTransformOperation.Summary
                ? text
                : current.SummaryText;
            var resolvedTranslatedPath = operation == ScreenshotTransformOperation.Translation
                ? translatedPath ?? current.TranslatedImagePath
                : current.TranslatedImagePath;

            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE screenshot_records SET refined_text = $refinedText, " +
                "translated_text = $translatedText, summary_text = $summaryText, " +
                "translated_image_path = $translatedImagePath, searchable_text = $searchableText, " +
                "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                "WHERE id = $id AND deleted_at_unix_ms IS NULL;";
            command.Parameters.AddWithValue("$refinedText", DatabaseValue(refinedText));
            command.Parameters.AddWithValue("$translatedText", DatabaseValue(translatedText));
            command.Parameters.AddWithValue("$summaryText", DatabaseValue(summaryText));
            command.Parameters.AddWithValue("$translatedImagePath", DatabaseValue(resolvedTranslatedPath));
            command.Parameters.AddWithValue(
                "$searchableText",
                ScreenshotSearchNormalizer.ForRecord(
                    current.OcrText,
                    refinedText,
                    translatedText,
                    summaryText));
            command.Parameters.AddWithValue("$updatedAt", updatedAtUtc.ToUnixTimeMilliseconds());
            command.Parameters.AddWithValue("$id", id.Trim());
            return command.ExecuteNonQuery() == 1;
        });
    }

    private static void AddRecordParameters(SqliteCommand command, ScreenshotRecord record)
    {
        command.Parameters.AddWithValue("$id", record.Id);
        command.Parameters.AddWithValue("$originalPath", record.OriginalImagePath);
        command.Parameters.AddWithValue("$renderedPath", record.RenderedImagePath);
        command.Parameters.AddWithValue("$thumbnailPath", record.ThumbnailPath);
        command.Parameters.AddWithValue("$translatedImagePath", DatabaseValue(record.TranslatedImagePath));
        command.Parameters.AddWithValue("$width", record.WidthPixels);
        command.Parameters.AddWithValue("$height", record.HeightPixels);
        command.Parameters.AddWithValue("$fileSize", record.FileSizeBytes);
        command.Parameters.AddWithValue("$sourceDisplayId", DatabaseValue(record.SourceDisplayId));
        command.Parameters.AddWithValue("$sourceWindowTitle", DatabaseValue(record.SourceWindowTitle));
        command.Parameters.AddWithValue("$ocrText", record.OcrText);
        command.Parameters.AddWithValue("$refinedText", DatabaseValue(record.RefinedText));
        command.Parameters.AddWithValue("$translatedText", DatabaseValue(record.TranslatedText));
        command.Parameters.AddWithValue("$summaryText", DatabaseValue(record.SummaryText));
        command.Parameters.AddWithValue(
            "$searchableText",
            ScreenshotSearchNormalizer.ForRecord(
                record.OcrText,
                record.RefinedText,
                record.TranslatedText,
                record.SummaryText));
        command.Parameters.AddWithValue("$characterCount", record.CharacterCount);
        command.Parameters.AddWithValue("$favorite", record.IsFavorite ? 1 : 0);
        command.Parameters.AddWithValue("$createdAt", record.CreatedAtUtc.ToUnixTimeMilliseconds());
        command.Parameters.AddWithValue("$updatedAt", record.UpdatedAtUtc.ToUnixTimeMilliseconds());
        command.Parameters.AddWithValue(
            "$deletedAt",
            record.DeletedAtUtc is { } deleted
                ? deleted.ToUnixTimeMilliseconds()
                : DBNull.Value);
    }

    private static void AddQueryParameters(
        SqliteCommand command,
        ScreenshotRecordQuery query,
        string normalizedQuery) => AddFilterParameters(
            command,
            query.FavoritesOnly,
            normalizedQuery);

    private static void AddFilterParameters(
        SqliteCommand command,
        bool favoritesOnly,
        string normalizedQuery)
    {
        command.Parameters.AddWithValue("$favoritesOnly", favoritesOnly ? 1 : 0);
        command.Parameters.AddWithValue("$query", normalizedQuery);
        command.Parameters.AddWithValue("$like", "%" + EscapeLike(normalizedQuery) + "%");
    }

    private static ScreenshotRecord ReadRecord(SqliteDataReader reader) => new(
        reader.GetString(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetString(3),
        reader.GetInt32(5),
        reader.GetInt32(6),
        reader.GetInt64(7),
        reader.GetString(10),
        DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(15)),
        translatedImagePath: NullableString(reader, 4),
        sourceDisplayId: NullableString(reader, 8),
        sourceWindowTitle: NullableString(reader, 9),
        refinedText: NullableString(reader, 11),
        translatedText: NullableString(reader, 12),
        summaryText: NullableString(reader, 13),
        isFavorite: reader.GetInt64(14) == 1,
        updatedAtUtc: DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(16)),
        deletedAtUtc: reader.IsDBNull(17)
            ? null
            : DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(17)));

    private static TransformFields? ReadTransformFields(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string id)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "SELECT ocr_text, refined_text, translated_text, summary_text, translated_image_path " +
            "FROM screenshot_records WHERE id = $id AND deleted_at_unix_ms IS NULL;";
        command.Parameters.AddWithValue("$id", id);
        using var reader = command.ExecuteReader();
        return reader.Read()
            ? new TransformFields(
                reader.GetString(0),
                NullableString(reader, 1),
                NullableString(reader, 2),
                NullableString(reader, 3),
                NullableString(reader, 4))
            : null;
    }

    private static string ValidateManagedPath(string value)
    {
        var normalized = value.Replace('\\', '/').Trim();
        if (Path.IsPathRooted(normalized)
            || normalized.Contains(':', StringComparison.Ordinal)
            || !normalized.StartsWith("Screenshots/", StringComparison.Ordinal)
            || normalized.Split('/').Any(segment => segment is "" or "." or ".."))
        {
            throw new ArgumentException("A managed Screenshots relative path is required.", nameof(value));
        }
        return normalized;
    }

    private static string? NullableString(SqliteDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);

    private static object DatabaseValue(string? value) =>
        value is null ? DBNull.Value : value;

    private static string EscapeLike(string value) => value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("%", "\\%", StringComparison.Ordinal)
        .Replace("_", "\\_", StringComparison.Ordinal);

    private sealed record TransformFields(
        string OcrText,
        string? RefinedText,
        string? TranslatedText,
        string? SummaryText,
        string? TranslatedImagePath);
}

internal static class ScreenshotValueTimeValidation
{
    public static void RequireUtc(DateTimeOffset value, string parameterName)
    {
        if (value.Offset != TimeSpan.Zero)
        {
            throw new ArgumentException("A UTC timestamp is required.", parameterName);
        }
    }
}
