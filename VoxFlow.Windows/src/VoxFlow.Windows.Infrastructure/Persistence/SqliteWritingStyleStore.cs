using System.Text.Json;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteWritingStyleStore : IWritingStyleStore
{
    private const string SettingsKey = "text_processing.writing_styles";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly SqliteTransactionRunner transactionRunner;
    private readonly TimeProvider timeProvider;

    public SqliteWritingStyleStore(
        SqliteTransactionRunner transactionRunner,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public ValueTask<WritingStyleDocument> LoadAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var json = transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT json_value FROM settings WHERE key = $key;";
            command.Parameters.AddWithValue("$key", SettingsKey);
            return command.ExecuteScalar() as string;
        });
        if (json is null)
        {
            return ValueTask.FromResult(WritingStyleDocument.Default);
        }

        try
        {
            var document = JsonSerializer.Deserialize<WritingStyleDocument>(json, JsonOptions)
                ?? throw new InvalidDataException("Stored writing styles are unavailable.");
            if (document.SchemaVersion != WritingStyleDocument.CurrentSchemaVersion)
            {
                throw new InvalidDataException("Stored writing styles use an unsupported schema version.");
            }

            return ValueTask.FromResult(document.Normalize());
        }
        catch (InvalidDataException)
        {
            throw;
        }
        catch (Exception exception) when (exception is JsonException or NotSupportedException)
        {
            throw new InvalidDataException("Stored writing styles are invalid.", exception);
        }
    }

    public ValueTask SaveAsync(
        WritingStyleDocument document,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(document);
        cancellationToken.ThrowIfCancellationRequested();
        var json = JsonSerializer.Serialize(document.Normalize(), JsonOptions);
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO settings(key, json_value, updated_at_unix_ms) " +
                "VALUES ($key, $json, $updatedAt) " +
                "ON CONFLICT(key) DO UPDATE SET json_value = excluded.json_value, " +
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
