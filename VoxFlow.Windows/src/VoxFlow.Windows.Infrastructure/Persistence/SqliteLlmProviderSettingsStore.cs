using VoxFlow.Windows.Application.Llm;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteLlmProviderSettingsStore : ILlmProviderSettingsStore
{
    private readonly SqliteTransactionRunner transactionRunner;
    private readonly TimeProvider timeProvider;

    public SqliteLlmProviderSettingsStore(
        SqliteTransactionRunner transactionRunner,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public ValueTask<LlmProviderSettings?> LoadAsync(
        LlmProviderId provider,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var value = transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT base_url, model, enabled " +
                "FROM llm_providers WHERE provider_id = $provider;";
            command.Parameters.AddWithValue("$provider", ToStorageId(provider));
            using var reader = command.ExecuteReader();
            if (!reader.Read())
            {
                return null;
            }

            if (reader.IsDBNull(0)
                || reader.IsDBNull(1)
                || !Uri.TryCreate(reader.GetString(0), UriKind.Absolute, out var baseUri)
                || string.IsNullOrWhiteSpace(reader.GetString(1)))
            {
                throw new InvalidDataException("Stored LLM provider metadata is invalid.");
            }

            try
            {
                return new LlmProviderSettings(
                    provider,
                    baseUri,
                    reader.GetString(1),
                    reader.GetInt64(2) == 1);
            }
            catch (ArgumentException exception)
            {
                throw new InvalidDataException(
                    "Stored LLM provider metadata is invalid.",
                    exception);
            }
        });
        return ValueTask.FromResult(value);
    }

    public ValueTask SaveAsync(
        LlmProviderSettings settings,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(settings);
        cancellationToken.ThrowIfCancellationRequested();
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO llm_providers(" +
                "provider_id, base_url, model, enabled, updated_at_unix_ms" +
                ") VALUES ($provider, $baseUrl, $model, $enabled, $updatedAt) " +
                "ON CONFLICT(provider_id) DO UPDATE SET " +
                "base_url = excluded.base_url, " +
                "model = excluded.model, " +
                "enabled = excluded.enabled, " +
                "updated_at_unix_ms = excluded.updated_at_unix_ms;";
            command.Parameters.AddWithValue(
                "$provider",
                ToStorageId(settings.Provider));
            command.Parameters.AddWithValue(
                "$baseUrl",
                settings.BaseUri.AbsoluteUri.TrimEnd('/'));
            command.Parameters.AddWithValue("$model", settings.Model);
            command.Parameters.AddWithValue("$enabled", settings.Enabled ? 1 : 0);
            command.Parameters.AddWithValue(
                "$updatedAt",
                timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
            _ = command.ExecuteNonQuery();
            return 0;
        });
        return ValueTask.CompletedTask;
    }

    public ValueTask DeleteAsync(
        LlmProviderId provider,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "DELETE FROM llm_providers WHERE provider_id = $provider;";
            command.Parameters.AddWithValue("$provider", ToStorageId(provider));
            _ = command.ExecuteNonQuery();
            return 0;
        });
        return ValueTask.CompletedTask;
    }

    private static string ToStorageId(LlmProviderId provider) => provider switch
    {
        LlmProviderId.OpenAI => "openai",
        _ => throw new ArgumentOutOfRangeException(nameof(provider), provider, null),
    };
}
