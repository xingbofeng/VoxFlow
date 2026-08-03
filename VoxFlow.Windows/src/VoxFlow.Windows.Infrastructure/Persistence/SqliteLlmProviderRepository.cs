using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Llm;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteLlmProviderRepository : ILlmProviderRepository
{
    private const string SelectColumns =
        "provider_id, display_name, provider_type, base_url, model, api_key_ref, " +
        "temperature, timeout_seconds, enabled, is_default, " +
        "health_status, health_message, health_latency_ms, health_checked_at_unix_ms, " +
        "agent_capability_status, agent_capability_message, " +
        "agent_capability_checked_at_unix_ms, created_at_unix_ms, updated_at_unix_ms";

    private readonly SqliteTransactionRunner transactionRunner;

    public SqliteLlmProviderRepository(SqliteTransactionRunner transactionRunner)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
    }

    public IReadOnlyList<LlmProviderRecord> List() =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                $"SELECT {SelectColumns} FROM llm_providers " +
                "ORDER BY is_default DESC, updated_at_unix_ms DESC, provider_id ASC;";
            using var reader = command.ExecuteReader();
            List<LlmProviderRecord> providers = [];
            while (reader.Read())
            {
                providers.Add(ReadProvider(reader));
            }
            return providers.ToArray();
        });

    public LlmProviderRecord? Get(string providerId)
    {
        ValidateProviderId(providerId);
        return transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                $"SELECT {SelectColumns} FROM llm_providers " +
                "WHERE provider_id = $providerId;";
            command.Parameters.AddWithValue("$providerId", providerId);
            using var reader = command.ExecuteReader();
            return reader.Read() ? ReadProvider(reader) : null;
        });
    }

    public LlmProviderRecord? GetDefault() =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                $"SELECT {SelectColumns} FROM llm_providers " +
                "WHERE enabled = 1 AND is_default = 1 LIMIT 1;";
            using var reader = command.ExecuteReader();
            return reader.Read() ? ReadProvider(reader) : null;
        });

    public void Upsert(LlmProviderRecord provider)
    {
        ArgumentNullException.ThrowIfNull(provider);
        transactionRunner.Write((connection, transaction) =>
        {
            if (provider.IsDefault)
            {
                AcquireWriteLock(connection, transaction);
                ClearOtherDefaults(
                    connection,
                    transaction,
                    provider.Id,
                    provider.UpdatedAtUnixMs);
            }

            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO llm_providers(" +
                "provider_id, display_name, provider_type, base_url, model, api_key_ref, " +
                "temperature, timeout_seconds, enabled, is_default, " +
                "health_status, health_message, health_latency_ms, health_checked_at_unix_ms, " +
                "agent_capability_status, agent_capability_message, " +
                "agent_capability_checked_at_unix_ms, created_at_unix_ms, updated_at_unix_ms" +
                ") VALUES (" +
                "$providerId, $displayName, $providerType, $baseUrl, $model, $apiKeyRef, " +
                "$temperature, $timeoutSeconds, $enabled, $isDefault, " +
                "$healthStatus, $healthMessage, $healthLatencyMs, $healthCheckedAt, " +
                "$agentStatus, $agentMessage, $agentCheckedAt, $createdAt, $updatedAt" +
                ") ON CONFLICT(provider_id) DO UPDATE SET " +
                "display_name = excluded.display_name, " +
                "provider_type = excluded.provider_type, " +
                "base_url = excluded.base_url, " +
                "model = excluded.model, " +
                "api_key_ref = excluded.api_key_ref, " +
                "temperature = excluded.temperature, " +
                "timeout_seconds = excluded.timeout_seconds, " +
                "enabled = excluded.enabled, " +
                "is_default = excluded.is_default, " +
                "health_status = excluded.health_status, " +
                "health_message = excluded.health_message, " +
                "health_latency_ms = excluded.health_latency_ms, " +
                "health_checked_at_unix_ms = excluded.health_checked_at_unix_ms, " +
                "agent_capability_status = excluded.agent_capability_status, " +
                "agent_capability_message = excluded.agent_capability_message, " +
                "agent_capability_checked_at_unix_ms = excluded.agent_capability_checked_at_unix_ms, " +
                "updated_at_unix_ms = MAX(llm_providers.updated_at_unix_ms, excluded.updated_at_unix_ms);";
            AddProviderParameters(command, provider);
            _ = command.ExecuteNonQuery();
            return 0;
        });
    }

    public bool Delete(string providerId)
    {
        ValidateProviderId(providerId);
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "DELETE FROM llm_providers WHERE provider_id = $providerId;";
            command.Parameters.AddWithValue("$providerId", providerId);
            return command.ExecuteNonQuery() == 1;
        });
    }

    public bool SetEnabled(
        string providerId,
        bool enabled,
        long updatedAtUnixMs)
    {
        ValidateProviderId(providerId);
        ArgumentOutOfRangeException.ThrowIfNegative(updatedAtUnixMs);
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE llm_providers SET " +
                "enabled = $enabled, " +
                "is_default = CASE WHEN $enabled = 0 THEN 0 ELSE is_default END, " +
                "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                "WHERE provider_id = $providerId;";
            command.Parameters.AddWithValue("$enabled", enabled ? 1 : 0);
            command.Parameters.AddWithValue("$updatedAt", updatedAtUnixMs);
            command.Parameters.AddWithValue("$providerId", providerId);
            return command.ExecuteNonQuery() == 1;
        });
    }

    public bool SetDefault(string providerId, long updatedAtUnixMs)
    {
        ValidateProviderId(providerId);
        ArgumentOutOfRangeException.ThrowIfNegative(updatedAtUnixMs);
        return transactionRunner.Write((connection, transaction) =>
        {
            using (var acquire = connection.CreateCommand())
            {
                acquire.Transaction = transaction;
                acquire.CommandText =
                    "UPDATE llm_providers " +
                    "SET updated_at_unix_ms = updated_at_unix_ms " +
                    "WHERE provider_id = $providerId AND enabled = 1;";
                acquire.Parameters.AddWithValue("$providerId", providerId);
                if (acquire.ExecuteNonQuery() != 1)
                {
                    return false;
                }
            }

            ClearOtherDefaults(connection, transaction, providerId, updatedAtUnixMs);
            using var select = connection.CreateCommand();
            select.Transaction = transaction;
            select.CommandText =
                "UPDATE llm_providers SET " +
                "is_default = 1, " +
                "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                "WHERE provider_id = $providerId AND enabled = 1;";
            select.Parameters.AddWithValue("$updatedAt", updatedAtUnixMs);
            select.Parameters.AddWithValue("$providerId", providerId);
            return select.ExecuteNonQuery() == 1;
        });
    }

    public bool UpdateHealth(
        string providerId,
        LlmProviderHealthUpdate update)
    {
        ValidateProviderId(providerId);
        ArgumentNullException.ThrowIfNull(update);
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE llm_providers SET " +
                "health_status = $status, health_message = $message, " +
                "health_latency_ms = $latency, health_checked_at_unix_ms = $checkedAt, " +
                "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                "WHERE provider_id = $providerId;";
            command.Parameters.AddWithValue("$status", ToStorage(update.Status));
            AddNullable(command, "$message", update.SafeMessage);
            AddNullable(command, "$latency", update.LatencyMs);
            command.Parameters.AddWithValue("$checkedAt", update.CheckedAtUnixMs);
            command.Parameters.AddWithValue("$updatedAt", update.UpdatedAtUnixMs);
            command.Parameters.AddWithValue("$providerId", providerId);
            return command.ExecuteNonQuery() == 1;
        });
    }

    public bool UpdateAgentCapability(
        string providerId,
        LlmAgentCapabilityUpdate update)
    {
        ValidateProviderId(providerId);
        ArgumentNullException.ThrowIfNull(update);
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE llm_providers SET " +
                "agent_capability_status = $status, " +
                "agent_capability_message = $message, " +
                "agent_capability_checked_at_unix_ms = $checkedAt, " +
                "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
                "WHERE provider_id = $providerId;";
            command.Parameters.AddWithValue("$status", ToStorage(update.Status));
            AddNullable(command, "$message", update.SafeMessage);
            command.Parameters.AddWithValue("$checkedAt", update.CheckedAtUnixMs);
            command.Parameters.AddWithValue("$updatedAt", update.UpdatedAtUnixMs);
            command.Parameters.AddWithValue("$providerId", providerId);
            return command.ExecuteNonQuery() == 1;
        });
    }

    private static void AddProviderParameters(
        SqliteCommand command,
        LlmProviderRecord provider)
    {
        command.Parameters.AddWithValue("$providerId", provider.Id);
        command.Parameters.AddWithValue("$displayName", provider.DisplayName);
        command.Parameters.AddWithValue("$providerType", ToStorage(provider.ProviderType));
        AddNullable(command, "$baseUrl", provider.BaseUri?.AbsoluteUri.TrimEnd('/'));
        AddNullable(command, "$model", provider.DefaultModel);
        AddNullable(command, "$apiKeyRef", provider.ApiKeyRef);
        command.Parameters.AddWithValue("$temperature", provider.Temperature);
        command.Parameters.AddWithValue("$timeoutSeconds", provider.TimeoutSeconds);
        command.Parameters.AddWithValue("$enabled", provider.Enabled ? 1 : 0);
        command.Parameters.AddWithValue("$isDefault", provider.IsDefault ? 1 : 0);
        command.Parameters.AddWithValue("$healthStatus", ToStorage(provider.HealthStatus));
        AddNullable(command, "$healthMessage", provider.HealthMessage);
        AddNullable(command, "$healthLatencyMs", provider.HealthLatencyMs);
        AddNullable(command, "$healthCheckedAt", provider.HealthCheckedAtUnixMs);
        command.Parameters.AddWithValue(
            "$agentStatus",
            ToStorage(provider.AgentCapabilityStatus));
        AddNullable(command, "$agentMessage", provider.AgentCapabilityMessage);
        AddNullable(command, "$agentCheckedAt", provider.AgentCapabilityCheckedAtUnixMs);
        command.Parameters.AddWithValue("$createdAt", provider.CreatedAtUnixMs);
        command.Parameters.AddWithValue("$updatedAt", provider.UpdatedAtUnixMs);
    }

    private static LlmProviderRecord ReadProvider(SqliteDataReader reader)
    {
        var baseUri = reader.IsDBNull(3)
            ? null
            : Uri.TryCreate(reader.GetString(3), UriKind.Absolute, out var parsed)
                ? parsed
                : throw new InvalidDataException("Stored LLM provider base URL is invalid.");
        return new LlmProviderRecord(
            reader.GetString(0),
            reader.GetString(1),
            ParseProviderType(reader.GetString(2)),
            baseUri,
            NullableString(reader, 4),
            NullableString(reader, 5),
            reader.GetDouble(6),
            reader.GetInt32(7),
            reader.GetInt64(8) == 1,
            reader.GetInt64(9) == 1,
            ParseHealthStatus(reader.GetString(10)),
            NullableString(reader, 11),
            NullableInt64(reader, 12),
            NullableInt64(reader, 13),
            ParseAgentStatus(reader.GetString(14)),
            NullableString(reader, 15),
            NullableInt64(reader, 16),
            reader.GetInt64(17),
            reader.GetInt64(18));
    }

    private static void AcquireWriteLock(
        SqliteConnection connection,
        SqliteTransaction transaction)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "UPDATE llm_providers SET updated_at_unix_ms = updated_at_unix_ms WHERE 0;";
        _ = command.ExecuteNonQuery();
    }

    private static void ClearOtherDefaults(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string selectedId,
        long updatedAtUnixMs)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "UPDATE llm_providers SET " +
            "is_default = 0, " +
            "updated_at_unix_ms = MAX(updated_at_unix_ms, $updatedAt) " +
            "WHERE is_default = 1 AND provider_id <> $selectedId;";
        command.Parameters.AddWithValue("$updatedAt", updatedAtUnixMs);
        command.Parameters.AddWithValue("$selectedId", selectedId);
        _ = command.ExecuteNonQuery();
    }

    private static string? NullableString(SqliteDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);

    private static long? NullableInt64(SqliteDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetInt64(ordinal);

    private static void AddNullable(
        SqliteCommand command,
        string parameterName,
        object? value) =>
        command.Parameters.AddWithValue(parameterName, value ?? DBNull.Value);

    private static void ValidateProviderId(string providerId) =>
        ArgumentException.ThrowIfNullOrWhiteSpace(providerId);

    private static string ToStorage(LlmProviderType value) => value switch
    {
        LlmProviderType.OpenAiCompatible => "openaiCompatible",
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, null),
    };

    private static LlmProviderType ParseProviderType(string value) => value switch
    {
        "openaiCompatible" => LlmProviderType.OpenAiCompatible,
        _ => throw new InvalidDataException("Stored LLM provider type is invalid."),
    };

    private static string ToStorage(LlmProviderHealthStatus value) => value switch
    {
        LlmProviderHealthStatus.Unknown => "unknown",
        LlmProviderHealthStatus.Testing => "testing",
        LlmProviderHealthStatus.Ok => "ok",
        LlmProviderHealthStatus.Error => "error",
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, null),
    };

    private static LlmProviderHealthStatus ParseHealthStatus(string value) => value switch
    {
        "unknown" => LlmProviderHealthStatus.Unknown,
        "testing" => LlmProviderHealthStatus.Testing,
        "ok" => LlmProviderHealthStatus.Ok,
        "error" => LlmProviderHealthStatus.Error,
        _ => throw new InvalidDataException("Stored LLM provider health status is invalid."),
    };

    private static string ToStorage(LlmAgentCapabilityStatus value) => value switch
    {
        LlmAgentCapabilityStatus.Unknown => "unknown",
        LlmAgentCapabilityStatus.Supported => "supported",
        LlmAgentCapabilityStatus.Unsupported => "unsupported",
        LlmAgentCapabilityStatus.Error => "error",
        _ => throw new ArgumentOutOfRangeException(nameof(value), value, null),
    };

    private static LlmAgentCapabilityStatus ParseAgentStatus(string value) => value switch
    {
        "unknown" => LlmAgentCapabilityStatus.Unknown,
        "supported" => LlmAgentCapabilityStatus.Supported,
        "unsupported" => LlmAgentCapabilityStatus.Unsupported,
        "error" => LlmAgentCapabilityStatus.Error,
        _ => throw new InvalidDataException(
            "Stored LLM provider Agent capability status is invalid."),
    };
}
