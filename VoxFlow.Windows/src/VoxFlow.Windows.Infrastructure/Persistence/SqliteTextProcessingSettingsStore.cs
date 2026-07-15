using System.Text.Json;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteTextProcessingSettingsStore : ITextProcessingSettingsStore
{
    private const string SettingsKey = "text_processing.deterministic";
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
    };

    private readonly SqliteTransactionRunner transactionRunner;
    private readonly TimeProvider timeProvider;

    public SqliteTextProcessingSettingsStore(
        SqliteTransactionRunner transactionRunner,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public ValueTask<DeterministicTextProcessingSettings> LoadAsync(
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var json = transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT json_value FROM settings WHERE key = $key;";
            command.Parameters.AddWithValue("$key", SettingsKey);
            return command.ExecuteScalar() as string;
        });
        if (json is null)
        {
            return ValueTask.FromResult(DeterministicTextProcessingSettings.Default);
        }

        try
        {
            var settings = JsonSerializer.Deserialize<DeterministicTextProcessingSettings>(
                json,
                JsonOptions)
                ?? throw new InvalidDataException(
                    "Stored text-processing settings are unavailable.");
            if (settings.SchemaVersion != DeterministicTextProcessingSettings.CurrentSchemaVersion)
            {
                throw new InvalidDataException(
                    "Stored text-processing settings use an unsupported schema version.");
            }

            return ValueTask.FromResult(settings);
        }
        catch (InvalidDataException)
        {
            throw;
        }
        catch (Exception exception) when (exception is
            JsonException or
            NotSupportedException or
            ArgumentException)
        {
            throw new InvalidDataException(
                "Stored text-processing settings are invalid.",
                exception);
        }
    }

    public ValueTask SaveAsync(
        DeterministicTextProcessingSettings settings,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(settings);
        cancellationToken.ThrowIfCancellationRequested();
        if (settings.SchemaVersion != DeterministicTextProcessingSettings.CurrentSchemaVersion)
        {
            throw new ArgumentException(
                "Only the current text-processing settings schema can be saved.",
                nameof(settings));
        }

        var json = JsonSerializer.Serialize(settings, JsonOptions);
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
                "VALUES ($key, $json, $updatedAt) " +
                "ON CONFLICT(key) DO UPDATE SET " +
                "json_value = excluded.json_value, " +
                "updated_at_unix_ms = excluded.updated_at_unix_ms;";
            command.Parameters.AddWithValue("$key", SettingsKey);
            command.Parameters.AddWithValue("$json", json);
            command.Parameters.AddWithValue(
                "$updatedAt",
                timeProvider.GetUtcNow().ToUnixTimeMilliseconds());
            _ = command.ExecuteNonQuery();
            return 0;
        });
        return ValueTask.CompletedTask;
    }
}
