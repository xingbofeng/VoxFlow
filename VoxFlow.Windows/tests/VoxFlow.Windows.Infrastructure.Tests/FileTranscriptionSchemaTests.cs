using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests;

public sealed class FileTranscriptionSchemaTests
{
    [Fact]
    public void Migration_creates_job_and_segment_tables_with_cascade_and_query_indexes()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.sqlite");

        var migrator = new VoxFlowDatabaseMigrator();
        migrator.Migrate(databasePath);
        migrator.Migrate(databasePath);

        var factory = new SqliteConnectionFactory(databasePath, pooling: false);
        using var connection = factory.Open();

        Assert.True(TableExists(connection, "file_transcription_jobs"));
        Assert.True(TableExists(connection, "file_transcription_segments"));
        Assert.True(IndexExists(connection, "idx_file_transcription_jobs_created_at"));
        Assert.True(IndexExists(connection, "idx_file_transcription_jobs_status"));
        Assert.True(IndexExists(connection, "idx_file_transcription_segments_job_index"));
        Assert.True(IndexExists(connection, "idx_file_transcription_segments_status"));
        Assert.Subset(
            ColumnNames(connection, "file_transcription_jobs"),
            new HashSet<string>(StringComparer.Ordinal)
            {
                "raw_text",
                "final_text",
                "provider_mode",
                "segment_count",
                "segment_completed",
                "partial_failure_summary",
                "translation_error_code",
                "translation_updated_at_unix_ms",
                "completed_at_unix_ms",
            });
        Assert.Contains(
            "provider_id",
            ColumnNames(connection, "file_transcription_segments"));

        using (var insertJob = connection.CreateCommand())
        {
            insertJob.CommandText =
                "INSERT INTO file_transcription_jobs(" +
                "id, source_path, display_name, provider_id, language, status, progress, " +
                "translation_status, created_at_unix_ms, updated_at_unix_ms" +
                ") VALUES ('job-1', 'C:/meeting.wav', 'meeting.wav', 'qwen3_asr', 'auto', " +
                "'queued', 0, 'notRequested', 1, 1);";
            insertJob.ExecuteNonQuery();
        }

        using (var insertSegment = connection.CreateCommand())
        {
            insertSegment.CommandText =
                "INSERT INTO file_transcription_segments(" +
                "job_id, segment_index, start_ms, end_ms, status, provider_id, retry_count, provider_mode, fallback_reason" +
                ") VALUES ('job-1', 0, 0, 30000, 'pending', 'qwen3_asr', 0, 'segmentedPcm', 'none');";
            insertSegment.ExecuteNonQuery();
        }

        using (var deleteJob = connection.CreateCommand())
        {
            deleteJob.CommandText = "DELETE FROM file_transcription_jobs WHERE id = 'job-1';";
            deleteJob.ExecuteNonQuery();
        }

        using var countSegments = connection.CreateCommand();
        countSegments.CommandText = "SELECT COUNT(*) FROM file_transcription_segments;";
        Assert.Equal(0L, Convert.ToInt64(countSegments.ExecuteScalar()));
    }

    [Fact]
    public void Migration_upgrades_an_existing_v1_database_without_reapplying_v1()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow-v1.sqlite");
        var factory = new SqliteConnectionFactory(databasePath, pooling: false);
        using (var connection = factory.Open())
        {
            var assembly = typeof(VoxFlowDatabaseMigrator).Assembly;
            using var stream = assembly.GetManifestResourceStream(
                "VoxFlow.Windows.Infrastructure.Persistence.Migrations.V001__initial.sql");
            Assert.NotNull(stream);
            using var reader = new StreamReader(stream);
            using var command = connection.CreateCommand();
            command.CommandText = reader.ReadToEnd();
            command.ExecuteNonQuery();

            using var ledger = connection.CreateCommand();
            ledger.CommandText =
                "INSERT INTO schema_migrations(version, name, applied_at_unix_ms) " +
                "VALUES (1, 'initial', 1);";
            ledger.ExecuteNonQuery();
        }

        new VoxFlowDatabaseMigrator().Migrate(databasePath);

        using var upgraded = factory.Open();
        Assert.True(TableExists(upgraded, "settings"));
        Assert.True(TableExists(upgraded, "file_transcription_jobs"));
        using var versions = upgraded.CreateCommand();
        versions.CommandText = "SELECT group_concat(version, ',') FROM schema_migrations ORDER BY version;";
        Assert.Equal("1,2", versions.ExecuteScalar());
    }

    private static bool TableExists(SqliteConnection connection, string name)
    {
        using var command = connection.CreateCommand();
        command.CommandText =
            "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = $name);";
        command.Parameters.AddWithValue("$name", name);
        return Convert.ToInt64(command.ExecuteScalar()) == 1;
    }

    private static bool IndexExists(SqliteConnection connection, string name)
    {
        using var command = connection.CreateCommand();
        command.CommandText =
            "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type = 'index' AND name = $name);";
        command.Parameters.AddWithValue("$name", name);
        return Convert.ToInt64(command.ExecuteScalar()) == 1;
    }

    private static HashSet<string> ColumnNames(SqliteConnection connection, string table)
    {
        using var command = connection.CreateCommand();
        command.CommandText = $"PRAGMA table_info({table});";
        using var reader = command.ExecuteReader();
        HashSet<string> names = new(StringComparer.Ordinal);
        while (reader.Read())
        {
            names.Add(reader.GetString(1));
        }

        return names;
    }
}
