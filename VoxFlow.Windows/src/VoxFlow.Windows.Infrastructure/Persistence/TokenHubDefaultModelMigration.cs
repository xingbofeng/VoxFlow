using System.Text.Json;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public enum TokenHubDefaultModelMigrationStatus
{
    Migrated,
    NoMatchingProvider,
    AlreadyCompleted,
}

public sealed record TokenHubDefaultModelMigrationResult(
    TokenHubDefaultModelMigrationStatus Status,
    int MigratedProviderCount);

/// <summary>
/// Moves only the exact legacy TokenHub template default to the replacement
/// default. A durable marker makes this a startup migration rather than an
/// ongoing policy, so later user-created or user-edited providers are never
/// rewritten.
/// </summary>
public sealed class TokenHubDefaultModelMigration
{
    public const string StateSettingKey =
        "migration.llm-provider.tokenhub-default-model.v001";

    private const string TokenHubBaseUrl =
        "https://tokenhub.tencentmaas.com/v1";
    private const string LegacyDefaultModel = "qwen3.5-plus";
    private const string CurrentDefaultModel = "deepseek-v4-flash";
    private const int StateSchemaVersion = 1;

    private readonly SqliteTransactionRunner transactionRunner;
    private readonly TimeProvider timeProvider;

    public TokenHubDefaultModelMigration(
        SqliteTransactionRunner transactionRunner,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public TokenHubDefaultModelMigrationResult Run()
    {
        var now = timeProvider.GetUtcNow().ToUnixTimeMilliseconds();
        ArgumentOutOfRangeException.ThrowIfNegative(now);
        return transactionRunner.Write((connection, transaction) =>
        {
            using (var marker = connection.CreateCommand())
            {
                marker.Transaction = transaction;
                marker.CommandText =
                    "SELECT 1 FROM settings WHERE key = $key LIMIT 1;";
                marker.Parameters.AddWithValue("$key", StateSettingKey);
                if (marker.ExecuteScalar() is not null)
                {
                    return new TokenHubDefaultModelMigrationResult(
                        TokenHubDefaultModelMigrationStatus.AlreadyCompleted,
                        0);
                }
            }

            int migratedCount;
            using (var update = connection.CreateCommand())
            {
                update.Transaction = transaction;
                update.CommandText =
                    "UPDATE llm_providers SET " +
                    "model = $currentModel, " +
                    "health_status = 'unknown', health_message = NULL, " +
                    "health_latency_ms = NULL, health_checked_at_unix_ms = NULL, " +
                    "agent_capability_status = 'unknown', " +
                    "agent_capability_message = NULL, " +
                    "agent_capability_checked_at_unix_ms = NULL, " +
                    "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                    "WHERE base_url = $baseUrl AND model = $legacyModel;";
                update.Parameters.AddWithValue("$currentModel", CurrentDefaultModel);
                update.Parameters.AddWithValue("$updatedAt", now);
                update.Parameters.AddWithValue("$baseUrl", TokenHubBaseUrl);
                update.Parameters.AddWithValue("$legacyModel", LegacyDefaultModel);
                migratedCount = update.ExecuteNonQuery();
            }

            var state = JsonSerializer.Serialize(new MigrationState(
                StateSchemaVersion,
                migratedCount,
                now));
            using (var marker = connection.CreateCommand())
            {
                marker.Transaction = transaction;
                marker.CommandText =
                    "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
                    "VALUES ($key, $json, $updatedAt);";
                marker.Parameters.AddWithValue("$key", StateSettingKey);
                marker.Parameters.AddWithValue("$json", state);
                marker.Parameters.AddWithValue("$updatedAt", now);
                _ = marker.ExecuteNonQuery();
            }

            return new TokenHubDefaultModelMigrationResult(
                migratedCount == 0
                    ? TokenHubDefaultModelMigrationStatus.NoMatchingProvider
                    : TokenHubDefaultModelMigrationStatus.Migrated,
                migratedCount);
        });
    }

    private sealed record MigrationState(
        int SchemaVersion,
        int MigratedProviderCount,
        long CompletedAtUnixMs);
}
