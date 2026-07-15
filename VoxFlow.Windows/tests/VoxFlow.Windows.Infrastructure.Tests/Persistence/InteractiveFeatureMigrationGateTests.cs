using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Infrastructure.Persistence;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class InteractiveFeatureMigrationGateTests
{
    [Fact]
    public void Disabled_features_apply_only_the_existing_v1_v2_database_contract()
    {
        var databasePath = Path.Combine(
            Path.GetTempPath(),
            $"voxflow-disabled-features-{Guid.NewGuid():N}.db");
        try
        {
            var featureMigrations = InteractiveFeatureMigrationCatalog.For(
                WindowsInteractiveFeatureFlags.Disabled);

            Assert.Empty(featureMigrations);
            new VoxFlowDatabaseMigrator(featureMigrations).Migrate(databasePath);

            using var connection = new SqliteConnection(
                new SqliteConnectionStringBuilder
                {
                    DataSource = databasePath,
                    Mode = SqliteOpenMode.ReadWrite,
                }.ToString());
            connection.Open();
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT version FROM schema_migrations ORDER BY version;";
            using var reader = command.ExecuteReader();
            var versions = new List<long>();
            while (reader.Read())
            {
                versions.Add(reader.GetInt64(0));
            }

            Assert.Equal([1L, 2L], versions);
        }
        finally
        {
            SqliteConnection.ClearAllPools();
            File.Delete(databasePath);
            File.Delete(databasePath + "-shm");
            File.Delete(databasePath + "-wal");
        }
    }
}
