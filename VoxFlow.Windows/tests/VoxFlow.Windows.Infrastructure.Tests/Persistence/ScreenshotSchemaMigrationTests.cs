using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class ScreenshotSchemaMigrationTests
{
    private static readonly WindowsInteractiveFeatureFlags InteractiveFeatures = new(
        selectionTransformEnabled: true,
        builtinAgentEnabled: true);

    [Fact]
    public void Fresh_database_applies_v004_once_with_screenshot_columns_and_indexes()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        var migrator = ScreenshotMigrator();

        migrator.Migrate(databasePath);
        migrator.Migrate(databasePath);

        using var connection = Open(databasePath);
        Assert.Equal([1L, 2L, 3L, 4L], ReadVersions(connection));
        Assert.Equal(
            [
                "id",
                "media_type",
                "original_image_path",
                "rendered_image_path",
                "thumbnail_path",
                "translated_image_path",
                "width_px",
                "height_px",
                "file_size_bytes",
                "source_display_id",
                "source_window_title",
                "ocr_text",
                "refined_text",
                "translated_text",
                "summary_text",
                "searchable_text",
                "character_count",
                "is_favorite",
                "created_at_unix_ms",
                "updated_at_unix_ms",
                "deleted_at_unix_ms",
            ],
            ReadColumns(connection, "screenshot_records"));
        Assert.True(IndexExists(connection, "idx_screenshot_records_created"));
        Assert.True(IndexExists(connection, "idx_screenshot_records_favorite"));
        Assert.True(IndexExists(connection, "idx_screenshot_records_updated"));
        Assert.True(IndexExists(connection, "idx_screenshot_records_searchable"));
        Assert.Equal(1L, Scalar<long>(connection,
            "SELECT COUNT(*) FROM schema_migrations WHERE version = 4;"));
    }

    [Fact]
    public void V003_upgrade_preserves_existing_settings_history_workflow_and_provider_rows()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow-v003.db");
        var v003 = new VoxFlowDatabaseMigrator(
            InteractiveFeatureMigrationCatalog.For(InteractiveFeatures));
        v003.Migrate(databasePath);
        using (var connection = Open(databasePath))
        {
            Execute(connection,
                "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
                "VALUES ('theme', '\"dark\"', 10);");
            Execute(connection,
                "INSERT INTO dictation_history(" +
                "id, source, raw_text, final_text, metadata_json, created_at_unix_ms" +
                ") VALUES ('history-1', 'dictation', 'raw', 'final', '{}', 11);");
            Execute(connection,
                "INSERT INTO llm_providers(" +
                "provider_id, display_name, provider_type, base_url, model, temperature, " +
                "timeout_seconds, enabled, is_default, health_status, agent_capability_status, " +
                "created_at_unix_ms, updated_at_unix_ms" +
                ") VALUES ('provider-1', 'Provider', 'openaiCompatible', " +
                "'https://example.test/v1', 'model', 0.2, 30, 1, 1, 'unknown', 'unknown', 12, 12);");
            Execute(connection,
                "INSERT INTO workflow_tasks(" +
                "id, kind, stage, status, generation, created_at_unix_ms, updated_at_unix_ms" +
                ") VALUES ('workflow-1', 'agentCompose', 'processing', 'running', 'generation-1', 13, 13);");
        }

        var migrator = ScreenshotMigrator();
        migrator.Migrate(databasePath);
        migrator.Migrate(databasePath);

        using var upgraded = Open(databasePath);
        Assert.Equal("\"dark\"", Scalar<string>(upgraded,
            "SELECT json_value FROM settings WHERE key = 'theme';"));
        Assert.Equal("final", Scalar<string>(upgraded,
            "SELECT final_text FROM dictation_history WHERE id = 'history-1';"));
        Assert.Equal("model", Scalar<string>(upgraded,
            "SELECT model FROM llm_providers WHERE provider_id = 'provider-1';"));
        Assert.Equal("running", Scalar<string>(upgraded,
            "SELECT status FROM workflow_tasks WHERE id = 'workflow-1';"));
        Assert.Equal(0L, Scalar<long>(upgraded,
            "SELECT COUNT(*) FROM screenshot_records;"));
    }

    [Fact]
    public void V004_rejects_blob_paths_invalid_dimensions_and_non_screenshot_media()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        ScreenshotMigrator().Migrate(databasePath);
        using var connection = Open(databasePath);

        Assert.DoesNotContain(ReadColumns(connection, "screenshot_records"), column =>
            column.Contains("blob", StringComparison.OrdinalIgnoreCase)
            || column.Contains("bytes", StringComparison.OrdinalIgnoreCase)
                && !column.Equals("file_size_bytes", StringComparison.Ordinal));
        Assert.Throws<SqliteException>(() => Execute(connection,
            MinimalInsertSql("bad-media", "recording", 100, 100)));
        Assert.Throws<SqliteException>(() => Execute(connection,
            MinimalInsertSql("bad-size", "screenshot", 0, 100)));
        Assert.Throws<SqliteException>(() => Execute(connection,
            MinimalInsertSql("bad-path", "screenshot", 100, 100)
                .Replace("Screenshots/a.png", "AgentRuntime/sessions/a.png", StringComparison.Ordinal)));
    }

    private static VoxFlowDatabaseMigrator ScreenshotMigrator() => new(
    [
        .. InteractiveFeatureMigrationCatalog.For(InteractiveFeatures),
        .. ScreenshotMigrationCatalog.All(),
    ]);

    private static string MinimalInsertSql(string id, string mediaType, int width, int height) =>
        "INSERT INTO screenshot_records(" +
        "id, media_type, original_image_path, rendered_image_path, thumbnail_path, " +
        "width_px, height_px, file_size_bytes, ocr_text, searchable_text, character_count, " +
        "is_favorite, created_at_unix_ms, updated_at_unix_ms" +
        ") VALUES (" +
        $"'{id}', '{mediaType}', 'Screenshots/a.png', 'Screenshots/b.png', 'Screenshots/c.png', " +
        $"{width}, {height}, 1, '', '', 0, 0, 1, 1);";

    private static SqliteConnection Open(string databasePath)
    {
        var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = SqliteOpenMode.ReadWrite,
            Pooling = false,
            ForeignKeys = true,
        }.ToString());
        connection.Open();
        return connection;
    }

    private static void Execute(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static string[] ReadColumns(SqliteConnection connection, string table)
    {
        using var command = connection.CreateCommand();
        command.CommandText = $"PRAGMA table_info([{table}]);";
        using var reader = command.ExecuteReader();
        List<string> result = [];
        while (reader.Read()) result.Add(reader.GetString(1));
        return [.. result];
    }

    private static long[] ReadVersions(SqliteConnection connection)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT version FROM schema_migrations ORDER BY version;";
        using var reader = command.ExecuteReader();
        List<long> result = [];
        while (reader.Read()) result.Add(reader.GetInt64(0));
        return [.. result];
    }

    private static bool IndexExists(SqliteConnection connection, string index)
    {
        using var command = connection.CreateCommand();
        command.CommandText =
            "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type = 'index' AND name = $name);";
        command.Parameters.AddWithValue("$name", index);
        return Convert.ToInt64(command.ExecuteScalar()) == 1;
    }

    private static T Scalar<T>(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        return (T)command.ExecuteScalar()!;
    }
}
