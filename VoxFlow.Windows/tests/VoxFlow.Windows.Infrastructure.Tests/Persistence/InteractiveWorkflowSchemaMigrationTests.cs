using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class InteractiveWorkflowSchemaMigrationTests
{
    private static readonly WindowsInteractiveFeatureFlags EnabledFeatures = new(
        selectionTransformEnabled: true,
        builtinAgentEnabled: true);

    [Fact]
    public void Fresh_database_applies_v1_v2_v3_in_order_with_generic_llm_and_workflow_schema()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");

        InteractiveMigrator().Migrate(databasePath);

        using var connection = Open(databasePath);
        Assert.Equal(
            ["1:initial", "2:file_transcription", "3:interactive_workflows"],
            ReadMigrationLedger(connection));
        Assert.Equal(
            [
                "provider_id",
                "display_name",
                "provider_type",
                "base_url",
                "model",
                "api_key_ref",
                "temperature",
                "timeout_seconds",
                "enabled",
                "is_default",
                "health_status",
                "health_message",
                "health_latency_ms",
                "health_checked_at_unix_ms",
                "agent_capability_status",
                "agent_capability_message",
                "agent_capability_checked_at_unix_ms",
                "created_at_unix_ms",
                "updated_at_unix_ms",
            ],
            ReadColumns(connection, "llm_providers"));
        Assert.Equal(
            [
                "id",
                "kind",
                "stage",
                "status",
                "generation",
                "raw_text",
                "partial_text",
                "final_text",
                "provider_id",
                "model",
                "target_json",
                "context_json",
                "trace_json",
                "output_json",
                "failure_json",
                "warnings_json",
                "created_at_unix_ms",
                "updated_at_unix_ms",
                "completed_at_unix_ms",
            ],
            ReadColumns(connection, "workflow_tasks"));
        Assert.True(IndexExists(connection, "ux_llm_providers_single_default"));
        Assert.True(IndexExists(connection, "idx_llm_providers_enabled_default"));
        Assert.True(IndexExists(connection, "idx_workflow_tasks_created_at"));
        Assert.True(IndexExists(connection, "idx_workflow_tasks_kind_created_at"));
        Assert.True(IndexExists(connection, "idx_workflow_tasks_status_updated_at"));

        Assert.Throws<SqliteException>(() => Execute(
            connection,
            "INSERT INTO workflow_tasks(" +
            "id, kind, stage, status, generation, target_json, created_at_unix_ms, updated_at_unix_ms" +
            ") VALUES ('bad', 'screenshot', 'processing', 'running', 'g', 'not-json', 1, 1);"));
    }

    [Fact]
    public void V1_upgrade_preserves_legacy_openai_and_history_while_applying_v2_v3()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow-v1.db");
        ApplyEmbeddedV1(databasePath);
        using (var connection = Open(databasePath))
        {
            Execute(
                connection,
                "INSERT INTO llm_providers(provider_id, base_url, model, enabled, updated_at_unix_ms) " +
                "VALUES ('openai', 'https://api.openai.com/v1', 'legacy-model', 1, 100);");
            Execute(
                connection,
                "INSERT INTO dictation_history(id, source, raw_text, final_text, metadata_json, created_at_unix_ms) " +
                "VALUES ('history-1', 'dictation', 'raw', 'final', '{}', 100);");
        }

        InteractiveMigrator().Migrate(databasePath);

        using var upgraded = Open(databasePath);
        Assert.Equal([1L, 2L, 3L], ReadMigrationVersions(upgraded));
        Assert.Equal("legacy-model", Scalar<string>(
            upgraded,
            "SELECT model FROM llm_providers WHERE provider_id = 'openai';"));
        Assert.Equal("OpenAI", Scalar<string>(
            upgraded,
            "SELECT display_name FROM llm_providers WHERE provider_id = 'openai';"));
        Assert.Equal(1L, Scalar<long>(
            upgraded,
            "SELECT enabled FROM llm_providers WHERE provider_id = 'openai';"));
        Assert.Equal(1L, Scalar<long>(
            upgraded,
            "SELECT is_default FROM llm_providers WHERE provider_id = 'openai';"));
        Assert.Equal(0.2D, Scalar<double>(
            upgraded,
            "SELECT temperature FROM llm_providers WHERE provider_id = 'openai';"),
            precision: 6);
        Assert.Equal(300L, Scalar<long>(
            upgraded,
            "SELECT timeout_seconds FROM llm_providers WHERE provider_id = 'openai';"));
        Assert.Equal("final", Scalar<string>(
            upgraded,
            "SELECT final_text FROM dictation_history WHERE id = 'history-1';"));
        Assert.True(TableExists(upgraded, "file_transcription_jobs"));
        Assert.True(TableExists(upgraded, "workflow_tasks"));
    }

    [Fact]
    public void V2_upgrade_preserves_file_transcription_rows_and_adds_v3_once()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow-v2.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        using (var connection = Open(databasePath))
        {
            Execute(
                connection,
                "INSERT INTO file_transcription_jobs(" +
                "id, source_path, display_name, provider_id, language, status, progress, " +
                "translation_status, created_at_unix_ms, updated_at_unix_ms" +
                ") VALUES ('job-1', 'C:/meeting.wav', 'meeting.wav', 'qwen3_asr', " +
                "'auto', 'queued', 0, 'notRequested', 10, 10);");
        }

        var migrator = InteractiveMigrator();
        migrator.Migrate(databasePath);
        migrator.Migrate(databasePath);

        using var upgraded = Open(databasePath);
        Assert.Equal([1L, 2L, 3L], ReadMigrationVersions(upgraded));
        Assert.Equal(1L, Scalar<long>(
            upgraded,
            "SELECT COUNT(*) FROM file_transcription_jobs WHERE id = 'job-1';"));
        Assert.Equal(1L, Scalar<long>(
            upgraded,
            "SELECT COUNT(*) FROM schema_migrations WHERE version = 3;"));
    }

    [Fact]
    public void Failed_v3_rolls_back_all_schema_changes_and_ledger_entry()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow-rollback.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        var failing = new VoxFlowDatabaseMigrator(
        [
            new SqliteMigration(
                3,
                "interactive_workflows",
                "CREATE TABLE workflow_tasks(id TEXT PRIMARY KEY); " +
                "ALTER TABLE llm_providers ADD COLUMN display_name TEXT; " +
                "INSERT INTO missing_v3_table(id) VALUES (1);"),
        ]);

        Assert.Throws<SqliteException>(() => failing.Migrate(databasePath));

        using var connection = Open(databasePath);
        Assert.Equal([1L, 2L], ReadMigrationVersions(connection));
        Assert.False(TableExists(connection, "workflow_tasks"));
        Assert.DoesNotContain("display_name", ReadColumns(connection, "llm_providers"));
    }

    [Fact]
    public void Enabled_catalog_exposes_exactly_one_embedded_v3_migration()
    {
        var migrations = InteractiveFeatureMigrationCatalog.For(EnabledFeatures);

        var migration = Assert.Single(migrations);
        Assert.Equal(3, migration.Version);
        Assert.Equal("interactive_workflows", migration.Name);
        Assert.Contains("CREATE TABLE workflow_tasks", migration.Sql, StringComparison.Ordinal);
        Assert.Contains("agent_capability_status", migration.Sql, StringComparison.Ordinal);
    }

    private static VoxFlowDatabaseMigrator InteractiveMigrator() => new(
        InteractiveFeatureMigrationCatalog.For(EnabledFeatures));

    private static void ApplyEmbeddedV1(string databasePath)
    {
        using var connection = Open(databasePath);
        var assembly = typeof(VoxFlowDatabaseMigrator).Assembly;
        using var stream = assembly.GetManifestResourceStream(
            "VoxFlow.Windows.Infrastructure.Persistence.Migrations.V001__initial.sql");
        Assert.NotNull(stream);
        using var reader = new StreamReader(stream);
        Execute(connection, reader.ReadToEnd());
        Execute(
            connection,
            "INSERT INTO schema_migrations(version, name, applied_at_unix_ms) " +
            "VALUES (1, 'initial', 1);");
    }

    private static SqliteConnection Open(string databasePath)
    {
        var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Pooling = false,
            ForeignKeys = true,
        }.ToString());
        connection.Open();
        return connection;
    }

    private static string[] ReadColumns(SqliteConnection connection, string table)
    {
        using var command = connection.CreateCommand();
        command.CommandText = $"PRAGMA table_info([{table.Replace("]", "]]", StringComparison.Ordinal)}]);";
        using var reader = command.ExecuteReader();
        List<string> columns = [];
        while (reader.Read())
        {
            columns.Add(reader.GetString(1));
        }
        return [.. columns];
    }

    private static string[] ReadMigrationLedger(SqliteConnection connection)
    {
        using var command = connection.CreateCommand();
        command.CommandText =
            "SELECT CAST(version AS TEXT) || ':' || name " +
            "FROM schema_migrations ORDER BY version;";
        using var reader = command.ExecuteReader();
        List<string> entries = [];
        while (reader.Read())
        {
            entries.Add(reader.GetString(0));
        }
        return [.. entries];
    }

    private static long[] ReadMigrationVersions(SqliteConnection connection)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT version FROM schema_migrations ORDER BY version;";
        using var reader = command.ExecuteReader();
        List<long> versions = [];
        while (reader.Read())
        {
            versions.Add(reader.GetInt64(0));
        }
        return [.. versions];
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

    private static void Execute(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static T Scalar<T>(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        return (T)command.ExecuteScalar()!;
    }
}
