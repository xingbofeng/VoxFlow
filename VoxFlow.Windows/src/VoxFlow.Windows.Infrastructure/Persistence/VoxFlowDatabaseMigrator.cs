using Microsoft.Data.Sqlite;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class VoxFlowDatabaseMigrator
{
    private const string InitialMigrationResource =
        "VoxFlow.Windows.Infrastructure.Persistence.Migrations.V001__initial.sql";

    private const string FileTranscriptionMigrationResource =
        "VoxFlow.Windows.Infrastructure.Persistence.Migrations.V002__file_transcription.sql";

    private readonly IReadOnlyList<SqliteMigration> migrations;

    public VoxFlowDatabaseMigrator(IEnumerable<SqliteMigration>? additionalMigrations = null)
    {
        List<SqliteMigration> configured =
        [
            LoadInitialMigration(),
            LoadFileTranscriptionMigration(),
        ];
        if (additionalMigrations is not null)
        {
            configured.AddRange(additionalMigrations);
        }

        migrations = ValidateAndOrder(configured);
    }

    public void Migrate(string databasePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(databasePath);

        var fullPath = Path.GetFullPath(databasePath);
        var directory = Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var factory = new SqliteConnectionFactory(fullPath, pooling: false);
        using var connection = factory.OpenConnection();

        foreach (var migration in migrations)
        {
            ApplyIfNeeded(connection, migration);
        }
    }

    private static void ApplyIfNeeded(SqliteConnection connection, SqliteMigration migration)
    {
        using var transaction = connection.BeginTransaction(deferred: false);

        try
        {
            if (IsApplied(connection, transaction, migration.Version))
            {
                transaction.Commit();
                return;
            }

            using (var command = connection.CreateCommand())
            {
                command.Transaction = transaction;
                command.CommandText = migration.Sql;
                command.ExecuteNonQuery();
            }

            using (var ledger = connection.CreateCommand())
            {
                ledger.Transaction = transaction;
                ledger.CommandText =
                    "INSERT INTO schema_migrations(version, name, applied_at_unix_ms) " +
                    "VALUES ($version, $name, $appliedAt);";
                ledger.Parameters.AddWithValue("$version", migration.Version);
                ledger.Parameters.AddWithValue("$name", migration.Name);
                ledger.Parameters.AddWithValue(
                    "$appliedAt",
                    DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                ledger.ExecuteNonQuery();
            }

            transaction.Commit();
        }
        catch
        {
            try
            {
                transaction.Rollback();
            }
            catch (SqliteException)
            {
                // Preserve the migration failure; a rollback error cannot make it actionable.
            }

            throw;
        }
    }

    private static bool IsApplied(
        SqliteConnection connection,
        SqliteTransaction transaction,
        long version)
    {
        if (!MigrationLedgerExists(connection, transaction))
        {
            return false;
        }

        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "SELECT EXISTS(" +
            "SELECT 1 FROM schema_migrations WHERE version = $version" +
            ");";
        command.Parameters.AddWithValue("$version", version);
        return Convert.ToInt64(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture) == 1;
    }

    private static bool MigrationLedgerExists(
        SqliteConnection connection,
        SqliteTransaction transaction)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "SELECT EXISTS(" +
            "SELECT 1 FROM sqlite_schema " +
            "WHERE type = 'table' AND name = 'schema_migrations'" +
            ");";
        return Convert.ToInt64(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture) == 1;
    }

    private static SqliteMigration LoadInitialMigration()
    {
        var assembly = typeof(VoxFlowDatabaseMigrator).Assembly;
        using var stream = assembly.GetManifestResourceStream(InitialMigrationResource)
            ?? throw new InvalidOperationException(
                $"Embedded database migration '{InitialMigrationResource}' was not found.");
        using var reader = new StreamReader(stream);
        return new SqliteMigration(1, "initial", reader.ReadToEnd());
    }

    private static SqliteMigration LoadFileTranscriptionMigration()
    {
        var assembly = typeof(VoxFlowDatabaseMigrator).Assembly;
        using var stream = assembly.GetManifestResourceStream(FileTranscriptionMigrationResource)
            ?? throw new InvalidOperationException(
                $"Embedded database migration '{FileTranscriptionMigrationResource}' was not found.");
        using var reader = new StreamReader(stream);
        return new SqliteMigration(2, "file_transcription", reader.ReadToEnd());
    }

    private static IReadOnlyList<SqliteMigration> ValidateAndOrder(
        IEnumerable<SqliteMigration> configured)
    {
        var ordered = configured.OrderBy(migration => migration.Version).ToArray();
        var duplicate = ordered
            .GroupBy(migration => migration.Version)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
        {
            throw new ArgumentException(
                $"Migration version {duplicate.Key} is configured more than once.",
                nameof(configured));
        }

        return ordered;
    }
}
