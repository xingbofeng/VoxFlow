using System.Text.Json;
using VoxFlow.Windows.Application.Text;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteGlossaryStore : IGlossaryStore
{
    private const string SettingsKey = "text_processing.glossary";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly SqliteTransactionRunner transactionRunner;
    private readonly TimeProvider timeProvider;

    public SqliteGlossaryStore(
        SqliteTransactionRunner transactionRunner,
        TimeProvider? timeProvider = null)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public ValueTask<GlossaryDocument> LoadAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var json = Read();
        if (json is null)
        {
            return ValueTask.FromResult(GlossaryDocument.Default);
        }

        try
        {
            var document = JsonSerializer.Deserialize<GlossaryDocument>(json, JsonOptions)
                ?? throw new InvalidDataException("Stored glossary is unavailable.");
            if (document.SchemaVersion != GlossaryDocument.CurrentSchemaVersion)
            {
                throw new InvalidDataException("Stored glossary uses an unsupported schema version.");
            }

            return ValueTask.FromResult(document.Normalize());
        }
        catch (InvalidDataException)
        {
            throw;
        }
        catch (Exception exception) when (exception is JsonException or NotSupportedException)
        {
            throw new InvalidDataException("Stored glossary is invalid.", exception);
        }
    }

    public ValueTask SaveAsync(
        GlossaryDocument document,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(document);
        cancellationToken.ThrowIfCancellationRequested();
        Write(JsonSerializer.Serialize(document.Normalize(), JsonOptions));
        return ValueTask.CompletedTask;
    }

    private string? Read() => transactionRunner.Read(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT json_value FROM settings WHERE key = $key;";
        command.Parameters.AddWithValue("$key", SettingsKey);
        return command.ExecuteScalar() as string;
    });

    private void Write(string json) => transactionRunner.Write((connection, transaction) =>
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
}
