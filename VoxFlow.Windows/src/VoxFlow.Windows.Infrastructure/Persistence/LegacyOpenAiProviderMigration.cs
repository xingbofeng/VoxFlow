using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Credentials;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public enum LegacyOpenAiProviderMigrationStatus
{
    NoLegacyProvider,
    CredentialMissing,
    CredentialVerificationFailed,
    Completed,
    AlreadyCompleted,
}

public sealed record LegacyOpenAiProviderMigrationResult(
    LegacyOpenAiProviderMigrationStatus Status);

public sealed class LegacyOpenAiProviderMigration
{
    public const string StateSettingKey =
        "migration.llm-provider.openai.v003";

    public const string LegacyApiKeyReference = "llm/openai/api_key";

    public const string CanonicalApiKeyReference =
        "llm-provider/openai/api_key";

    private const int CurrentStateSchemaVersion = 1;
    private const string ProviderId = "openai";
    private const string PendingStatus = "pending";
    private const string CredentialMissingStatus = "credentialMissing";
    private const string CredentialVerificationFailedStatus =
        "credentialVerificationFailed";
    private const string CompletedStatus = "completed";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private readonly SqliteTransactionRunner transactionRunner;
    private readonly ICredentialVault credentialVault;
    private readonly TimeProvider timeProvider;

    public LegacyOpenAiProviderMigration(
        SqliteTransactionRunner transactionRunner,
        ICredentialVault credentialVault,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.credentialVault = credentialVault
            ?? throw new ArgumentNullException(nameof(credentialVault));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public static CredentialKey LegacyApiKey { get; } = new(
        "llm",
        ProviderId,
        "api_key");

    public static CredentialKey ProviderApiKey { get; } = new(
        "llm-provider",
        ProviderId,
        "api_key");

    public async Task<LegacyOpenAiProviderMigrationResult> RunAsync(
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var existingState = ReadState();
        if (string.Equals(
            existingState?.Status,
            CompletedStatus,
            StringComparison.Ordinal))
        {
            return Result(LegacyOpenAiProviderMigrationStatus.AlreadyCompleted);
        }

        var provider = ReadProviderBackup();
        if (provider is null)
        {
            return Result(LegacyOpenAiProviderMigrationStatus.NoLegacyProvider);
        }

        var state = new MigrationState(
            CurrentStateSchemaVersion,
            PendingStatus,
            existingState?.Backup ?? provider,
            CompletedAtUnixMs: null);
        WriteState(state, Now());

        string? migratedSecret;
        try
        {
            migratedSecret = await credentialVault.ReadSecretAsync(
                    ProviderApiKey,
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (CredentialUnavailableException)
        {
            WriteFailureState(state, CredentialVerificationFailedStatus);
            return Result(
                LegacyOpenAiProviderMigrationStatus.CredentialVerificationFailed);
        }

        if (string.IsNullOrWhiteSpace(migratedSecret))
        {
            string? legacySecret;
            try
            {
                legacySecret = await credentialVault.ReadSecretAsync(
                        LegacyApiKey,
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (CredentialUnavailableException)
            {
                WriteFailureState(state, CredentialVerificationFailedStatus);
                return Result(
                    LegacyOpenAiProviderMigrationStatus.CredentialVerificationFailed);
            }

            if (string.IsNullOrWhiteSpace(legacySecret))
            {
                WriteMissingCredentialState(state);
                return Result(LegacyOpenAiProviderMigrationStatus.CredentialMissing);
            }

            try
            {
                await credentialVault.SaveAsync(
                        ProviderApiKey,
                        legacySecret,
                        cancellationToken)
                    .ConfigureAwait(false);
                migratedSecret = await credentialVault.ReadSecretAsync(
                        ProviderApiKey,
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (CredentialUnavailableException)
            {
                WriteFailureState(state, CredentialVerificationFailedStatus);
                return Result(
                    LegacyOpenAiProviderMigrationStatus.CredentialVerificationFailed);
            }

            if (!string.Equals(
                legacySecret,
                migratedSecret,
                StringComparison.Ordinal))
            {
                WriteFailureState(state, CredentialVerificationFailedStatus);
                return Result(
                    LegacyOpenAiProviderMigrationStatus.CredentialVerificationFailed);
            }
        }

        cancellationToken.ThrowIfCancellationRequested();
        Complete(state);
        return Result(LegacyOpenAiProviderMigrationStatus.Completed);
    }

    private void Complete(MigrationState state)
    {
        var now = Now();
        var completed = state with
        {
            Status = CompletedStatus,
            CompletedAtUnixMs = now,
        };

        transactionRunner.Write((connection, transaction) =>
        {
            using (var provider = connection.CreateCommand())
            {
                provider.Transaction = transaction;
                provider.CommandText =
                    "UPDATE llm_providers SET api_key_ref = $reference, " +
                    "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                    "WHERE provider_id = $providerId;";
                provider.Parameters.AddWithValue(
                    "$reference",
                    CanonicalApiKeyReference);
                provider.Parameters.AddWithValue("$updatedAt", now);
                provider.Parameters.AddWithValue("$providerId", ProviderId);
                if (provider.ExecuteNonQuery() != 1)
                {
                    throw new InvalidOperationException(
                        "The OpenAI provider disappeared during migration.");
                }
            }

            UpsertState(connection, transaction, completed, now);
            return 0;
        });
    }

    private MigrationState? ReadState() =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT json_value FROM settings WHERE key = $key;";
            command.Parameters.AddWithValue("$key", StateSettingKey);
            var json = command.ExecuteScalar() as string;
            if (json is null)
            {
                return null;
            }

            try
            {
                var state = JsonSerializer.Deserialize<MigrationState>(
                    json,
                    JsonOptions);
                if (state is null
                    || state.SchemaVersion != CurrentStateSchemaVersion
                    || string.IsNullOrWhiteSpace(state.Status)
                    || state.Backup is null)
                {
                    throw new InvalidDataException(
                        "Stored OpenAI provider migration state is invalid.");
                }
                return state;
            }
            catch (JsonException exception)
            {
                throw new InvalidDataException(
                    "Stored OpenAI provider migration state is invalid.",
                    exception);
            }
        });

    private LegacyProviderBackup? ReadProviderBackup() =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT provider_id, base_url, model, enabled, " +
                "updated_at_unix_ms, api_key_ref " +
                "FROM llm_providers WHERE provider_id = $providerId;";
            command.Parameters.AddWithValue("$providerId", ProviderId);
            using var reader = command.ExecuteReader();
            if (!reader.Read())
            {
                return null;
            }

            return new LegacyProviderBackup(
                reader.GetString(0),
                reader.IsDBNull(1) ? null : reader.GetString(1),
                reader.IsDBNull(2) ? null : reader.GetString(2),
                reader.GetInt64(3) == 1,
                reader.GetInt64(4),
                reader.IsDBNull(5) ? null : reader.GetString(5));
        });

    private void WriteMissingCredentialState(MigrationState state)
    {
        var now = Now();
        var missing = state with
        {
            Status = CredentialMissingStatus,
            CompletedAtUnixMs = null,
        };
        transactionRunner.Write((connection, transaction) =>
        {
            using (var provider = connection.CreateCommand())
            {
                provider.Transaction = transaction;
                provider.CommandText =
                    "UPDATE llm_providers SET api_key_ref = NULL, " +
                    "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                    "WHERE provider_id = $providerId " +
                    "AND (api_key_ref IS NULL OR api_key_ref IN ($legacyRef, $canonicalRef));";
                provider.Parameters.AddWithValue("$updatedAt", now);
                provider.Parameters.AddWithValue("$providerId", ProviderId);
                provider.Parameters.AddWithValue("$legacyRef", LegacyApiKeyReference);
                provider.Parameters.AddWithValue(
                    "$canonicalRef",
                    CanonicalApiKeyReference);
                _ = provider.ExecuteNonQuery();
            }

            UpsertState(connection, transaction, missing, now);
            return 0;
        });
    }

    private void WriteFailureState(MigrationState state, string status)
    {
        var now = Now();
        WriteState(
            state with
            {
                Status = status,
                CompletedAtUnixMs = null,
            },
            now);
    }

    private void WriteState(MigrationState state, long updatedAtUnixMs) =>
        transactionRunner.Write((connection, transaction) =>
        {
            UpsertState(connection, transaction, state, updatedAtUnixMs);
            return 0;
        });

    private static void UpsertState(
        SqliteConnection connection,
        SqliteTransaction transaction,
        MigrationState state,
        long updatedAtUnixMs)
    {
        var json = JsonSerializer.Serialize(state, JsonOptions);
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
            "VALUES ($key, $json, $updatedAt) " +
            "ON CONFLICT(key) DO UPDATE SET " +
            "json_value = excluded.json_value, " +
            "updated_at_unix_ms = excluded.updated_at_unix_ms;";
        command.Parameters.AddWithValue("$key", StateSettingKey);
        command.Parameters.AddWithValue("$json", json);
        command.Parameters.AddWithValue("$updatedAt", updatedAtUnixMs);
        _ = command.ExecuteNonQuery();
    }

    private long Now() => timeProvider.GetUtcNow().ToUnixTimeMilliseconds();

    private static LegacyOpenAiProviderMigrationResult Result(
        LegacyOpenAiProviderMigrationStatus status) => new(status);

    private sealed record MigrationState(
        int SchemaVersion,
        string Status,
        LegacyProviderBackup Backup,
        long? CompletedAtUnixMs);

    private sealed record LegacyProviderBackup(
        string ProviderId,
        string? BaseUrl,
        string? Model,
        bool Enabled,
        long UpdatedAtUnixMs,
        string? LegacyApiKeyRef);
}
