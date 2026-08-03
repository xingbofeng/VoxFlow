using Microsoft.Data.Sqlite;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteConnectionFactory
{
    private readonly string connectionString;

    public SqliteConnectionFactory(string databasePath, bool pooling = true)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(databasePath);

        var fullPath = Path.GetFullPath(databasePath);
        connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = fullPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Pooling = pooling,
            ForeignKeys = true,
            DefaultTimeout = 30,
        }.ToString();
    }

    public SqliteConnection Open()
    {
        var connection = new SqliteConnection(connectionString);

        try
        {
            connection.Open();
            Configure(connection);
            return connection;
        }
        catch
        {
            connection.Dispose();
            throw;
        }
    }

    internal SqliteConnection OpenConnection() => Open();

    private static void Configure(SqliteConnection connection)
    {
        using var command = connection.CreateCommand();
        command.CommandText =
            "PRAGMA foreign_keys = ON; " +
            "PRAGMA journal_mode = WAL; " +
            "PRAGMA synchronous = NORMAL; " +
            "PRAGMA busy_timeout = 30000;";
        command.ExecuteNonQuery();
    }
}
