using VoxFlow.Windows.Application.Models;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Models;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Models;

public sealed class SqliteModelInstallStateRepositoryTests
{
    [Fact]
    public async Task State_survives_repository_recreation()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        var expected = new ModelInstallRecord(
            "qwen3-asr-0.6b",
            "model-revision",
            ModelInstallPhase.Downloading,
            321,
            1_000,
            installPath: null,
            errorCode: null);

        using (var runner = new SqliteTransactionRunner(new SqliteConnectionFactory(databasePath, pooling: false)))
        {
            var repository = new SqliteModelInstallStateRepository(runner);
            await repository.SaveAsync(expected, CancellationToken.None);
        }

        using var reloadedRunner = new SqliteTransactionRunner(new SqliteConnectionFactory(databasePath, pooling: false));
        var reloaded = new SqliteModelInstallStateRepository(reloadedRunner);
        Assert.Equal(expected, await reloaded.LoadAsync(expected.ModelId, CancellationToken.None));
    }

    [Fact]
    public async Task Missing_model_reads_as_not_downloaded_state()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        using var runner = new SqliteTransactionRunner(new SqliteConnectionFactory(databasePath, pooling: false));
        var repository = new SqliteModelInstallStateRepository(runner);

        var state = await repository.LoadAsync("qwen3-asr-1.7b", CancellationToken.None);

        Assert.Null(state);
    }
}
