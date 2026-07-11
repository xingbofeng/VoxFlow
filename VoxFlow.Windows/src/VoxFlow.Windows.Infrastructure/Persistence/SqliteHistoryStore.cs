using Microsoft.Data.Sqlite;
using System.Text.Json;
using VoxFlow.Windows.Application.History;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteHistoryStore : IHistoryStore
{
    private readonly SqliteTransactionRunner transactionRunner;

    public SqliteHistoryStore(SqliteTransactionRunner transactionRunner)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
    }

    public HistoryMaintenanceResult WriteAndPrune(
        HistoryEntry entry,
        DateTimeOffset? deleteBeforeUtcExclusive)
    {
        ArgumentNullException.ThrowIfNull(entry);

        return transactionRunner.Write((connection, transaction) =>
        {
            Insert(connection, transaction, entry);
            var prunedCount = deleteBeforeUtcExclusive is null
                ? 0
                : DeleteBefore(connection, transaction, deleteBeforeUtcExclusive.Value);
            return new HistoryMaintenanceResult(true, prunedCount);
        });
    }

    public int PruneBefore(DateTimeOffset deleteBeforeUtcExclusive) =>
        transactionRunner.Write((connection, transaction) =>
            DeleteBefore(connection, transaction, deleteBeforeUtcExclusive));

    public IReadOnlyList<HistoryEntry> ReadAll() =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT id, source, raw_text, final_text, metadata_json, created_at_unix_ms " +
                "FROM dictation_history " +
                "ORDER BY created_at_unix_ms DESC, id ASC;";
            using var reader = command.ExecuteReader();
            List<HistoryEntry> entries = [];
            while (reader.Read())
            {
                entries.Add(new HistoryEntry(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    DeserializeMetadata(reader.GetString(4)),
                    DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(5))));
            }

            return entries.ToArray();
        });

    public int Delete(IReadOnlyCollection<string> ids)
    {
        ArgumentNullException.ThrowIfNull(ids);
        var uniqueIds = ids
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (uniqueIds.Length == 0)
        {
            return 0;
        }

        return transactionRunner.Write((connection, transaction) =>
        {
            const int parameterBatchSize = 500;
            var deleted = 0;
            for (var offset = 0; offset < uniqueIds.Length; offset += parameterBatchSize)
            {
                var count = Math.Min(parameterBatchSize, uniqueIds.Length - offset);
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                var placeholders = new string[count];
                for (var index = 0; index < count; index++)
                {
                    var parameterName = $"$id{index}";
                    placeholders[index] = parameterName;
                    command.Parameters.AddWithValue(
                        parameterName,
                        uniqueIds[offset + index]);
                }

                command.CommandText =
                    $"DELETE FROM dictation_history WHERE id IN ({string.Join(", ", placeholders)});";
                deleted += command.ExecuteNonQuery();
            }

            return deleted;
        });
    }

    public int Clear() =>
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "DELETE FROM dictation_history;";
            return command.ExecuteNonQuery();
        });

    public bool UpdateFinalText(string id, string finalText)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentNullException.ThrowIfNull(finalText);

        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE dictation_history " +
                "SET final_text = $finalText " +
                "WHERE id = $id;";
            command.Parameters.AddWithValue("$finalText", finalText);
            command.Parameters.AddWithValue("$id", id);
            return command.ExecuteNonQuery() == 1;
        });
    }

    private static void Insert(
        SqliteConnection connection,
        SqliteTransaction transaction,
        HistoryEntry entry)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "INSERT INTO dictation_history(" +
            "id, source, raw_text, final_text, metadata_json, created_at_unix_ms" +
            ") VALUES ($id, $source, $rawText, $finalText, $metadataJson, $createdAt);";
        command.Parameters.AddWithValue("$id", entry.Id);
        command.Parameters.AddWithValue("$source", entry.Source);
        command.Parameters.AddWithValue("$rawText", entry.RawText);
        command.Parameters.AddWithValue("$finalText", entry.FinalText);
        command.Parameters.AddWithValue(
            "$metadataJson",
            JsonSerializer.Serialize(entry.Metadata, DomainJson.Options));
        command.Parameters.AddWithValue("$createdAt", entry.CreatedAtUtc.ToUnixTimeMilliseconds());
        command.ExecuteNonQuery();
    }

    private static HistoryMetadata DeserializeMetadata(string json) =>
        JsonSerializer.Deserialize<HistoryMetadata>(json, DomainJson.Options)
        ?? throw new InvalidDataException("History metadata is unavailable.");

    private static int DeleteBefore(
        SqliteConnection connection,
        SqliteTransaction transaction,
        DateTimeOffset deleteBeforeUtcExclusive)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            "DELETE FROM dictation_history WHERE created_at_unix_ms < $cutoff;";
        command.Parameters.AddWithValue(
            "$cutoff",
            deleteBeforeUtcExclusive.ToUnixTimeMilliseconds());
        return command.ExecuteNonQuery();
    }
}
