using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Features;
using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Infrastructure.Persistence;
using VoxFlow.Windows.Testing;

namespace VoxFlow.Windows.Infrastructure.Tests.Persistence;

public sealed class TokenHubDefaultModelMigrationTests
{
    [Fact]
    public void Only_the_exact_legacy_TokenHub_default_is_migrated_once()
    {
        using var fixture = new MigrationDatabase();
        fixture.SeedProvider(
            "legacy-default",
            "https://tokenhub.tencentmaas.com/v1",
            "qwen3.5-plus");
        fixture.SeedProvider(
            "custom-model",
            "https://tokenhub.tencentmaas.com/v1",
            "user-selected-model");
        fixture.SeedProvider(
            "other-endpoint",
            "https://example.test/v1",
            "qwen3.5-plus");
        fixture.SeedProvider(
            "trailing-slash",
            "https://tokenhub.tencentmaas.com/v1/",
            "qwen3.5-plus");

        var first = fixture.Migration.Run();
        var second = fixture.Migration.Run();

        Assert.Equal(TokenHubDefaultModelMigrationStatus.Migrated, first.Status);
        Assert.Equal(1, first.MigratedProviderCount);
        Assert.Equal(
            TokenHubDefaultModelMigrationStatus.AlreadyCompleted,
            second.Status);
        Assert.Equal(0, second.MigratedProviderCount);
        Assert.Equal(
            "deepseek-v4-flash",
            fixture.Repository.Get("legacy-default")?.DefaultModel);
        Assert.Equal(
            LlmProviderHealthStatus.Unknown,
            fixture.Repository.Get("legacy-default")?.HealthStatus);
        Assert.Equal(
            LlmAgentCapabilityStatus.Unknown,
            fixture.Repository.Get("legacy-default")?.AgentCapabilityStatus);
        Assert.Equal(
            "user-selected-model",
            fixture.Repository.Get("custom-model")?.DefaultModel);
        Assert.Equal(
            "qwen3.5-plus",
            fixture.Repository.Get("other-endpoint")?.DefaultModel);
        Assert.Equal(
            "qwen3.5-plus",
            fixture.Repository.Get("trailing-slash")?.DefaultModel);
        Assert.Equal(1, fixture.CountMigrationMarkers());
    }

    [Fact]
    public void A_no_match_startup_is_completed_and_never_rewrites_a_later_user_provider()
    {
        using var fixture = new MigrationDatabase();

        var first = fixture.Migration.Run();
        fixture.SeedProvider(
            "created-later",
            "https://tokenhub.tencentmaas.com/v1",
            "qwen3.5-plus");
        var second = fixture.Migration.Run();

        Assert.Equal(
            TokenHubDefaultModelMigrationStatus.NoMatchingProvider,
            first.Status);
        Assert.Equal(
            TokenHubDefaultModelMigrationStatus.AlreadyCompleted,
            second.Status);
        Assert.Equal(
            "qwen3.5-plus",
            fixture.Repository.Get("created-later")?.DefaultModel);
        Assert.Equal(1, fixture.CountMigrationMarkers());
    }

    private sealed class MigrationDatabase : IDisposable
    {
        private readonly TemporaryDirectory directory = new();
        private readonly SqliteConnectionFactory factory;
        private readonly SqliteTransactionRunner runner;

        public MigrationDatabase()
        {
            DatabasePath = Path.Combine(directory.Path, "voxflow.db");
            var flags = new WindowsInteractiveFeatureFlags(
                selectionTransformEnabled: true,
                builtinAgentEnabled: true);
            new VoxFlowDatabaseMigrator(
                InteractiveFeatureMigrationCatalog.For(flags))
                .Migrate(DatabasePath);
            factory = new SqliteConnectionFactory(DatabasePath, pooling: false);
            runner = new SqliteTransactionRunner(factory);
            Repository = new SqliteLlmProviderRepository(runner);
            Migration = new TokenHubDefaultModelMigration(
                runner,
                new ControlledTimeProvider(
                    DateTimeOffset.FromUnixTimeMilliseconds(1_000)));
        }

        public string DatabasePath { get; }

        public SqliteLlmProviderRepository Repository { get; }

        public TokenHubDefaultModelMigration Migration { get; }

        public void SeedProvider(string id, string baseUrl, string model)
        {
            using var connection = factory.Open();
            using var command = connection.CreateCommand();
            command.CommandText =
                "INSERT INTO llm_providers(" +
                "provider_id, display_name, provider_type, base_url, model, " +
                "api_key_ref, temperature, timeout_seconds, enabled, is_default, " +
                "health_status, health_message, health_latency_ms, " +
                "health_checked_at_unix_ms, agent_capability_status, " +
                "agent_capability_message, agent_capability_checked_at_unix_ms, " +
                "created_at_unix_ms, updated_at_unix_ms" +
                ") VALUES (" +
                "$id, $id, 'openaiCompatible', $baseUrl, $model, NULL, 0.2, 120, 1, 0, " +
                "'ok', 'old_health', 12, 100, 'supported', 'old_agent', 100, 100, 100);";
            command.Parameters.AddWithValue("$id", id);
            command.Parameters.AddWithValue("$baseUrl", baseUrl);
            command.Parameters.AddWithValue("$model", model);
            Assert.Equal(1, command.ExecuteNonQuery());
        }

        public int CountMigrationMarkers()
        {
            using var connection = factory.Open();
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT COUNT(*) FROM settings WHERE key = $key;";
            command.Parameters.AddWithValue(
                "$key",
                TokenHubDefaultModelMigration.StateSettingKey);
            return Convert.ToInt32(command.ExecuteScalar());
        }

        public void Dispose()
        {
            runner.Dispose();
            directory.Dispose();
        }
    }
}
