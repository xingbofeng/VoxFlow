using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class LlmProviderSettingsStoreTests
{
    [Fact]
    public async Task OpenAI_metadata_round_trips_upserts_and_deletes_without_any_secret_field()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        using var runner = new SqliteTransactionRunner(
            new SqliteConnectionFactory(databasePath, pooling: false));
        var store = new SqliteLlmProviderSettingsStore(runner);

        Assert.Null(await store.LoadAsync(LlmProviderId.OpenAI, CancellationToken.None));

        await store.SaveAsync(
            new LlmProviderSettings(
                LlmProviderId.OpenAI,
                new Uri("https://api.openai.com/v1"),
                "gpt-first",
                Enabled: true),
            CancellationToken.None);
        await store.SaveAsync(
            new LlmProviderSettings(
                LlmProviderId.OpenAI,
                new Uri("https://api.openai.com/v1/"),
                "gpt-second",
                Enabled: false),
            CancellationToken.None);

        Assert.Equal(
            new LlmProviderSettings(
                LlmProviderId.OpenAI,
                new Uri("https://api.openai.com/v1"),
                "gpt-second",
                Enabled: false),
            await store.LoadAsync(LlmProviderId.OpenAI, CancellationToken.None));
        runner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT COUNT(*), COUNT(base_url), COUNT(model) " +
                "FROM llm_providers WHERE provider_id = 'openai';";
            using var reader = command.ExecuteReader();
            Assert.True(reader.Read());
            Assert.Equal(1, reader.GetInt32(0));
            Assert.Equal(1, reader.GetInt32(1));
            Assert.Equal(1, reader.GetInt32(2));
            return 0;
        });

        await store.DeleteAsync(LlmProviderId.OpenAI, CancellationToken.None);
        Assert.Null(await store.LoadAsync(LlmProviderId.OpenAI, CancellationToken.None));
    }

    [Fact]
    public async Task Corrupt_non_https_or_blank_metadata_is_rejected_on_read()
    {
        using var directory = new TemporaryDirectory();
        var databasePath = Path.Combine(directory.Path, "voxflow.db");
        new VoxFlowDatabaseMigrator().Migrate(databasePath);
        using var runner = new SqliteTransactionRunner(
            new SqliteConnectionFactory(databasePath, pooling: false));
        runner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO llm_providers(provider_id, base_url, model, enabled, updated_at_unix_ms) " +
                "VALUES ('openai', 'http://unsafe.invalid/v1', '', 1, 0);";
            command.ExecuteNonQuery();
            return 0;
        });
        var store = new SqliteLlmProviderSettingsStore(runner);

        await Assert.ThrowsAsync<InvalidDataException>(async () =>
            await store.LoadAsync(LlmProviderId.OpenAI, CancellationToken.None));
    }
}
