using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class DatabaseSchemaTests
{
    private static readonly string[] ExpectedTables =
    [
        "asr_providers",
        "credentials",
        "dictation_history",
        "file_transcription_jobs",
        "file_transcription_segments",
        "llm_providers",
        "models",
        "schema_migrations",
        "settings",
        "ui_state",
    ];

    private static readonly string[] ExpectedIndexes =
    [
        "idx_credentials_owner",
        "idx_dictation_history_created_at",
        "idx_dictation_history_source_created_at",
        "idx_file_transcription_jobs_created_at",
        "idx_file_transcription_jobs_status",
        "idx_file_transcription_segments_job_index",
        "idx_file_transcription_segments_status",
        "idx_models_state",
        "ux_credentials_owner_field",
    ];

    [Fact]
    public void Fresh_database_contains_the_complete_schema_and_indexes()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");

        new VoxFlowDatabaseMigrator().Migrate(databasePath);

        using var connection = Open(databasePath);
        Assert.Equal(ExpectedTables, ReadObjectNames(connection, "table"));
        Assert.Equal(ExpectedIndexes, ReadObjectNames(connection, "index"));

        AssertColumns(
            connection,
            "settings",
            "key", "json_value", "updated_at_unix_ms");
        AssertColumns(
            connection,
            "asr_providers",
            "provider_id", "selected_model_id", "enabled", "config_json", "updated_at_unix_ms");
        AssertColumns(
            connection,
            "llm_providers",
            "provider_id", "base_url", "model", "enabled", "updated_at_unix_ms");
        AssertColumns(
            connection,
            "credentials",
            "credential_id", "owner_kind", "owner_id", "field_name", "scope",
            "protection_version", "ciphertext", "updated_at_unix_ms");
        AssertColumns(
            connection,
            "models",
            "model_id", "version", "state", "bytes", "total_bytes", "install_path", "error_code",
            "updated_at_unix_ms");
        AssertColumns(
            connection,
            "dictation_history",
            "id", "source", "raw_text", "final_text", "metadata_json", "created_at_unix_ms");
        AssertColumns(
            connection,
            "ui_state",
            "key", "json_value", "updated_at_unix_ms");
    }

    [Fact]
    public void Schema_rejects_invalid_json_booleans_and_unprotected_credential_shapes()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        using var connection = Open(databasePath);

        Assert.Throws<SqliteException>(() => Execute(
            connection,
            "INSERT INTO settings(key, json_value, updated_at_unix_ms) VALUES ('bad', 'not-json', 1);"));
        Assert.Throws<SqliteException>(() => Execute(
            connection,
            "INSERT INTO asr_providers(provider_id, enabled, config_json, updated_at_unix_ms) " +
            "VALUES ('qwen3_asr', 2, '{}', 1);"));
        Assert.Throws<SqliteException>(() => Execute(
            connection,
            "INSERT INTO credentials(" +
            "credential_id, owner_kind, owner_id, field_name, scope, protection_version, ciphertext, updated_at_unix_ms" +
            ") VALUES ('id', 'asr', 'tencent', 'secret_key', 'LocalMachine', 1, X'01', 1);"));
        Assert.Throws<SqliteException>(() => Execute(
            connection,
            "INSERT INTO credentials(" +
            "credential_id, owner_kind, owner_id, field_name, scope, protection_version, ciphertext, updated_at_unix_ms" +
            ") VALUES ('id', 'asr', 'tencent', 'secret_key', 'CurrentUser', 1, X'', 1);"));

        var credentialColumns = ReadColumns(connection, "credentials");
        Assert.DoesNotContain(credentialColumns, column =>
            column.Contains("plaintext", StringComparison.OrdinalIgnoreCase)
            || column.Equals("secret", StringComparison.OrdinalIgnoreCase)
            || column.Equals("value", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Reapplying_migrations_is_idempotent()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        var migrator = new VoxFlowDatabaseMigrator();

        migrator.Migrate(databasePath);
        migrator.Migrate(databasePath);

        using var connection = Open(databasePath);
        Assert.Equal([1L, 2L], ReadMigrationVersions(connection));
    }

    [Fact]
    public void Upgrade_preserves_existing_data_and_records_each_version_once()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        using (var connection = Open(databasePath))
        {
            Execute(
                connection,
                "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
                "VALUES ('theme', '\"dark\"', 1);");
        }

        var migrator = new VoxFlowDatabaseMigrator(
        [
            new SqliteMigration(
                3,
                "test-upgrade",
                "ALTER TABLE settings ADD COLUMN test_marker TEXT NULL;"),
        ]);

        migrator.Migrate(databasePath);
        migrator.Migrate(databasePath);

        using var upgraded = Open(databasePath);
        Assert.Equal([1L, 2L, 3L], ReadMigrationVersions(upgraded));
        Assert.Equal("\"dark\"", Scalar<string>(
            upgraded,
            "SELECT json_value FROM settings WHERE key = 'theme';"));
        Assert.Contains("test_marker", ReadColumns(upgraded, "settings"));
    }

    [Fact]
    public void Failed_upgrade_rolls_back_schema_and_migration_ledger()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        var failing = new VoxFlowDatabaseMigrator(
        [
            new SqliteMigration(
                3,
                "failing-upgrade",
                "CREATE TABLE must_roll_back(id INTEGER PRIMARY KEY); " +
                "INSERT INTO table_that_does_not_exist(id) VALUES (1);"),
        ]);

        Assert.Throws<SqliteException>(() => failing.Migrate(databasePath));

        using var connection = Open(databasePath);
        Assert.Equal([1L, 2L], ReadMigrationVersions(connection));
        Assert.DoesNotContain("must_roll_back", ReadObjectNames(connection, "table"));
    }

    [Fact]
    public async Task Concurrent_migrators_apply_each_version_exactly_once()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);

        const int workerCount = 12;
        using var ready = new CountdownEvent(workerCount);
        using var start = new ManualResetEventSlim(initialState: false);
        var migration = new SqliteMigration(
            3,
            "concurrent-upgrade",
            "CREATE TABLE concurrent_upgrade_marker(" +
            "id INTEGER PRIMARY KEY, payload BLOB NOT NULL); " +
            "INSERT INTO concurrent_upgrade_marker(id, payload) " +
            "VALUES (1, randomblob(8388608));");

        var migrations = Enumerable.Range(0, workerCount)
            .Select(_ => Task.Factory.StartNew(
                () =>
                {
                    ready.Signal();
                    start.Wait();
                    new VoxFlowDatabaseMigrator([migration]).Migrate(databasePath);
                },
                CancellationToken.None,
                TaskCreationOptions.LongRunning,
                TaskScheduler.Default))
            .ToArray();

        Assert.True(ready.Wait(TimeSpan.FromSeconds(10)), "Concurrent migrators did not become ready.");
        start.Set();
        await Task.WhenAll(migrations).WaitAsync(TimeSpan.FromSeconds(60));

        using var connection = Open(databasePath);
        Assert.Equal([1L, 2L, 3L], ReadMigrationVersions(connection));
        Assert.Equal(1L, Scalar<long>(
            connection,
            "SELECT COUNT(*) FROM concurrent_upgrade_marker;"));
    }

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

    private static string[] ReadObjectNames(SqliteConnection connection, string type)
    {
        using var command = connection.CreateCommand();
        command.CommandText =
            "SELECT name FROM sqlite_schema " +
            "WHERE type = $type AND name NOT LIKE 'sqlite_%' " +
            "ORDER BY name;";
        command.Parameters.AddWithValue("$type", type);
        using var reader = command.ExecuteReader();
        List<string> names = [];
        while (reader.Read())
        {
            names.Add(reader.GetString(0));
        }

        return [.. names];
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

    private static void AssertColumns(
        SqliteConnection connection,
        string table,
        params string[] expected) =>
        Assert.Equal(expected, ReadColumns(connection, table));

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
