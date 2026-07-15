using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class SqliteTransactionRunnerTests
{
    [Fact]
    public void Write_commits_all_operations_as_one_transaction()
    {
        using var fixture = new SqliteTestDatabase();

        fixture.Runner.Write((connection, transaction) =>
        {
            InsertSetting(connection, transaction, "theme", "\"dark\"");
            InsertSetting(connection, transaction, "language", "\"zh-CN\"");
            return 0;
        });

        var count = fixture.Runner.Read(connection => Scalar<long>(
            connection,
            "SELECT COUNT(*) FROM settings;"));
        Assert.Equal(2, count);
    }

    [Fact]
    public void Write_rolls_back_every_operation_when_the_callback_fails()
    {
        using var fixture = new SqliteTestDatabase();

        Assert.Throws<InvalidOperationException>(() =>
            fixture.Runner.Write<int>((connection, transaction) =>
            {
                InsertSetting(connection, transaction, "theme", "\"dark\"");
                throw new InvalidOperationException("second operation failed");
            }));

        var count = fixture.Runner.Read(connection => Scalar<long>(
            connection,
            "SELECT COUNT(*) FROM settings;"));
        Assert.Equal(0, count);
    }

    [Fact]
    public void Concurrent_writes_are_serialized_without_database_locked_failures()
    {
        using var fixture = new SqliteTestDatabase();

        Parallel.For(0, 50, index =>
            fixture.Runner.Write((connection, transaction) =>
            {
                InsertSetting(
                    connection,
                    transaction,
                    $"key-{index}",
                    index.ToString(System.Globalization.CultureInfo.InvariantCulture));
                return 0;
            }));

        var count = fixture.Runner.Read(connection => Scalar<long>(
            connection,
            "SELECT COUNT(*) FROM settings;"));
        Assert.Equal(50, count);
    }

    [Fact]
    public void Factory_opens_file_connections_with_foreign_keys_and_wal_enabled()
    {
        using var fixture = new SqliteTestDatabase();

        fixture.Runner.Read(connection =>
        {
            Assert.Equal(1L, Scalar<long>(connection, "PRAGMA foreign_keys;"));
            Assert.Equal("wal", Scalar<string>(connection, "PRAGMA journal_mode;"));
            return 0;
        });
    }

    private static void InsertSetting(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string key,
        string jsonValue)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
            "VALUES ($key, $json, 1);";
        command.Parameters.AddWithValue("$key", key);
        command.Parameters.AddWithValue("$json", jsonValue);
        command.ExecuteNonQuery();
    }

    private static T Scalar<T>(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        return (T)command.ExecuteScalar()!;
    }

    private sealed class SqliteTestDatabase : IDisposable
    {
        private readonly TemporaryDirectory directory = new();

        public SqliteTestDatabase()
        {
            var databasePath = Path.Combine(directory.Path, "voxflow.db");
            new VoxFlowDatabaseMigrator().Migrate(databasePath);
            Runner = new SqliteTransactionRunner(
                new SqliteConnectionFactory(databasePath, pooling: false));
        }

        public SqliteTransactionRunner Runner { get; }

        public void Dispose()
        {
            Runner.Dispose();
            directory.Dispose();
        }
    }
}
