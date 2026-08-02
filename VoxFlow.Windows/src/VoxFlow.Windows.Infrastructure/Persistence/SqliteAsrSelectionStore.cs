using System.Text.Json;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Persistence;

/// <summary>
/// Persists the active ASR selection across process restarts. Credentials remain
/// in the vault; this store only remembers which provider the user selected.
/// </summary>
public sealed class SqliteAsrSelectionStore
{
    public const string SettingsKey = "asr.selection";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
    };

    private readonly SqliteTransactionRunner transactionRunner;
    private readonly TimeProvider timeProvider;

    public SqliteAsrSelectionStore(
        SqliteTransactionRunner transactionRunner,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public AsrSelectionDocument? Load()
    {
        var json = transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT json_value FROM settings WHERE key = $key;";
            command.Parameters.AddWithValue("$key", SettingsKey);
            return command.ExecuteScalar() as string;
        });
        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        try
        {
            return JsonSerializer.Deserialize<AsrSelectionDocument>(json, JsonOptions);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public void Save(AsrSelection? selection)
    {
        if (selection is null)
        {
            _ = transactionRunner.Write((connection, transaction) =>
            {
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText = "DELETE FROM settings WHERE key = $key;";
                command.Parameters.AddWithValue("$key", SettingsKey);
                return command.ExecuteNonQuery();
            });
            return;
        }

        var document = new AsrSelectionDocument(
            SchemaVersion: AsrSelectionDocument.CurrentSchemaVersion,
            Provider: selection.Provider.ToString(),
            QwenVariant: selection.QwenVariant?.ToString());
        var json = JsonSerializer.Serialize(document, JsonOptions);
        var now = timeProvider.GetUtcNow().ToUnixTimeMilliseconds();
        _ = transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
                "VALUES ($key, $json, $updated) " +
                "ON CONFLICT(key) DO UPDATE SET " +
                "json_value = excluded.json_value, " +
                "updated_at_unix_ms = excluded.updated_at_unix_ms;";
            command.Parameters.AddWithValue("$key", SettingsKey);
            command.Parameters.AddWithValue("$json", json);
            command.Parameters.AddWithValue("$updated", now);
            return command.ExecuteNonQuery();
        });
    }
}

public sealed record AsrSelectionDocument(
    int SchemaVersion,
    string Provider,
    string? QwenVariant)
{
    public const int CurrentSchemaVersion = 1;

    public AsrSelection? ToSelection()
    {
        if (SchemaVersion != CurrentSchemaVersion
            || string.IsNullOrWhiteSpace(Provider)
            || !Enum.TryParse<AsrProviderId>(Provider, out var provider))
        {
            return null;
        }

        if (provider != AsrProviderId.Qwen)
        {
            return new AsrSelection(provider, null);
        }

        return !string.IsNullOrWhiteSpace(QwenVariant)
            && Enum.TryParse<QwenVariant>(QwenVariant, out var variant)
                ? new AsrSelection(provider, variant)
                : null;
    }
}
