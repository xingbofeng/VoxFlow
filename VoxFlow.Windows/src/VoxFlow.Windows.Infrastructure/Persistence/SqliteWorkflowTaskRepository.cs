using System.Text.Json;
using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.Workflows;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteWorkflowTaskRepository : IWorkflowTaskRepository
{
    private const string SelectColumns =
        "id, kind, stage, status, generation, raw_text, partial_text, final_text, " +
        "provider_id, model, target_json, context_json, trace_json, output_json, " +
        "failure_json, warnings_json, created_at_unix_ms, updated_at_unix_ms, " +
        "completed_at_unix_ms";

    private readonly SqliteTransactionRunner transactionRunner;

    public SqliteWorkflowTaskRepository(SqliteTransactionRunner transactionRunner)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
    }

    public void Create(WorkflowTaskRecord task)
    {
        ArgumentNullException.ThrowIfNull(task);
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO workflow_tasks(" + SelectColumns + ") VALUES (" +
                "$id, $kind, $stage, $status, $generation, $rawText, $partialText, " +
                "$finalText, $providerId, $model, $targetJson, $contextJson, " +
                "$traceJson, $outputJson, $failureJson, $warningsJson, $createdAt, " +
                "$updatedAt, $completedAt);";
            AddParameters(command, task);
            _ = command.ExecuteNonQuery();
            return 0;
        });
    }

    public WorkflowTaskRecord? Get(string id)
    {
        ValidateId(id);
        return transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                $"SELECT {SelectColumns} FROM workflow_tasks WHERE id = $id;";
            command.Parameters.AddWithValue("$id", id);
            using var reader = command.ExecuteReader();
            return reader.Read() ? ReadTask(reader) : null;
        });
    }

    public WorkflowTaskPage Search(WorkflowTaskQuery query)
    {
        ArgumentNullException.ThrowIfNull(query);
        return transactionRunner.Read(connection =>
        {
            var filter = BuildFilter(query);
            int total;
            using (var count = connection.CreateCommand())
            {
                count.CommandText =
                    "SELECT COUNT(*) FROM workflow_tasks" + filter.Sql + ";";
                AddFilterParameters(count, query, filter.SearchPattern);
                total = Convert.ToInt32(
                    count.ExecuteScalar(),
                    System.Globalization.CultureInfo.InvariantCulture);
            }

            using var command = connection.CreateCommand();
            command.CommandText =
                $"SELECT {SelectColumns} FROM workflow_tasks" + filter.Sql +
                " ORDER BY created_at_unix_ms DESC, id ASC LIMIT $limit OFFSET $offset;";
            AddFilterParameters(command, query, filter.SearchPattern);
            command.Parameters.AddWithValue("$limit", query.Limit);
            command.Parameters.AddWithValue("$offset", query.Offset);
            using var reader = command.ExecuteReader();
            List<WorkflowTaskRecord> tasks = [];
            while (reader.Read())
            {
                tasks.Add(ReadTask(reader));
            }

            return new WorkflowTaskPage(
                tasks.ToArray(),
                total,
                query.Offset,
                query.Limit);
        });
    }

    public bool TryUpdate(
        WorkflowTaskRecord task,
        Guid expectedGeneration)
    {
        ArgumentNullException.ThrowIfNull(task);
        if (expectedGeneration == Guid.Empty)
        {
            throw new ArgumentException(
                "A non-empty expected generation is required.",
                nameof(expectedGeneration));
        }

        return transactionRunner.Write((connection, transaction) =>
        {
            var current = ReadById(connection, transaction, task.Id);
            if (current is null
                || !CanTransition(current, task, expectedGeneration))
            {
                return false;
            }

            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE workflow_tasks SET " +
                "stage = $stage, status = $status, raw_text = $rawText, " +
                "partial_text = $partialText, final_text = $finalText, " +
                "provider_id = $providerId, model = $model, target_json = $targetJson, " +
                "context_json = $contextJson, trace_json = $traceJson, " +
                "output_json = $outputJson, failure_json = $failureJson, " +
                "warnings_json = $warningsJson, updated_at_unix_ms = $updatedAt, " +
                "completed_at_unix_ms = $completedAt " +
                "WHERE id = $id AND generation = $expectedGeneration " +
                "AND status IN ('pending', 'running') AND updated_at_unix_ms = $expectedUpdatedAt;";
            AddParameters(command, task);
            command.Parameters.AddWithValue(
                "$expectedGeneration",
                expectedGeneration.ToString("D"));
            command.Parameters.AddWithValue(
                "$expectedUpdatedAt",
                current.UpdatedAtUnixMs);
            return command.ExecuteNonQuery() == 1;
        });
    }

    public bool Delete(string id)
    {
        ValidateId(id);
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "DELETE FROM workflow_tasks WHERE id = $id;";
            command.Parameters.AddWithValue("$id", id);
            return command.ExecuteNonQuery() == 1;
        });
    }

    public IReadOnlyList<string> ListActiveIds() =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT id FROM workflow_tasks " +
                "WHERE status IN ('pending', 'running') ORDER BY id ASC;";
            using var reader = command.ExecuteReader();
            List<string> ids = [];
            while (reader.Read())
            {
                ids.Add(reader.GetString(0));
            }
            return ids.ToArray();
        });

    public int PruneTerminalBefore(long cutoffUnixMs)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(cutoffUnixMs);
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "DELETE FROM workflow_tasks " +
                "WHERE status NOT IN ('pending', 'running') " +
                "AND completed_at_unix_ms < $cutoff;";
            command.Parameters.AddWithValue("$cutoff", cutoffUnixMs);
            return command.ExecuteNonQuery();
        });
    }

    public int MarkActiveAsInterrupted(long interruptedAtUnixMs)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(interruptedAtUnixMs);
        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE workflow_tasks SET status = 'interrupted', " +
                "updated_at_unix_ms = MAX(updated_at_unix_ms, $interruptedAt), " +
                "completed_at_unix_ms = MAX(updated_at_unix_ms, $interruptedAt) " +
                "WHERE status IN ('pending', 'running');";
            command.Parameters.AddWithValue("$interruptedAt", interruptedAtUnixMs);
            return command.ExecuteNonQuery();
        });
    }

    private static bool CanTransition(
        WorkflowTaskRecord current,
        WorkflowTaskRecord next,
        Guid expectedGeneration)
    {
        if (current.IsTerminal
            || current.Generation != expectedGeneration
            || next.Generation != expectedGeneration
            || !string.Equals(current.Id, next.Id, StringComparison.Ordinal)
            || current.Kind != next.Kind
            || current.CreatedAtUnixMs != next.CreatedAtUnixMs
            || next.UpdatedAtUnixMs <= current.UpdatedAtUnixMs)
        {
            return false;
        }

        var statusAllowed = current.Status switch
        {
            WorkflowTaskStatus.Pending => next.Status is
                WorkflowTaskStatus.Pending
                or WorkflowTaskStatus.Running
                or WorkflowTaskStatus.Failed
                or WorkflowTaskStatus.Cancelled
                or WorkflowTaskStatus.Interrupted,
            WorkflowTaskStatus.Running => next.Status is not WorkflowTaskStatus.Pending,
            _ => false,
        };
        if (!statusAllowed)
        {
            return false;
        }

        if (next.Status == WorkflowTaskStatus.Completed)
        {
            return next.Stage == WorkflowTaskStage.Completed
                && CanAdvanceStage(current.Stage, next.Stage);
        }
        if (WorkflowTaskRecord.IsTerminalStatus(next.Status))
        {
            return next.Stage == current.Stage
                || CanAdvanceStage(current.Stage, next.Stage);
        }
        return CanAdvanceStage(current.Stage, next.Stage);
    }

    private static bool CanAdvanceStage(
        WorkflowTaskStage current,
        WorkflowTaskStage next)
    {
        if (current == next)
        {
            return true;
        }

        return current switch
        {
            WorkflowTaskStage.CapturingSelection => next is
                WorkflowTaskStage.Processing,
            WorkflowTaskStage.Recording => next is
                WorkflowTaskStage.Transcribing
                or WorkflowTaskStage.CollectingContext
                or WorkflowTaskStage.Processing,
            WorkflowTaskStage.Transcribing => next is
                WorkflowTaskStage.CollectingContext
                or WorkflowTaskStage.Processing,
            WorkflowTaskStage.CollectingContext => next is
                WorkflowTaskStage.Processing,
            WorkflowTaskStage.Processing => next is
                WorkflowTaskStage.WaitingForUser
                or WorkflowTaskStage.Operating
                or WorkflowTaskStage.Outputting
                or WorkflowTaskStage.Completed,
            WorkflowTaskStage.WaitingForUser => next is
                WorkflowTaskStage.Processing
                or WorkflowTaskStage.Operating
                or WorkflowTaskStage.Outputting
                or WorkflowTaskStage.Completed,
            WorkflowTaskStage.Operating => next is
                WorkflowTaskStage.Processing
                or WorkflowTaskStage.WaitingForUser
                or WorkflowTaskStage.Outputting
                or WorkflowTaskStage.Completed,
            WorkflowTaskStage.Outputting => next is WorkflowTaskStage.Completed,
            WorkflowTaskStage.Completed => false,
            _ => false,
        };
    }

    private static WorkflowTaskRecord? ReadById(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string id)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText =
            $"SELECT {SelectColumns} FROM workflow_tasks WHERE id = $id;";
        command.Parameters.AddWithValue("$id", id);
        using var reader = command.ExecuteReader();
        return reader.Read() ? ReadTask(reader) : null;
    }

    private static WorkflowTaskRecord ReadTask(SqliteDataReader reader)
    {
        if (!Guid.TryParseExact(reader.GetString(4), "D", out var generation))
        {
            throw new InvalidDataException(
                "Stored workflow task generation is invalid.");
        }

        return new WorkflowTaskRecord(
            reader.GetString(0),
            Parse<WorkflowTaskKind>(reader.GetString(1)),
            Parse<WorkflowTaskStage>(reader.GetString(2)),
            Parse<WorkflowTaskStatus>(reader.GetString(3)),
            generation,
            NullableString(reader, 5),
            NullableString(reader, 6),
            NullableString(reader, 7),
            NullableString(reader, 8),
            NullableString(reader, 9),
            NullableJson(reader, 10),
            NullableJson(reader, 11),
            NullableJson(reader, 12),
            NullableJson(reader, 13),
            NullableJson(reader, 14),
            NullableJson(reader, 15),
            reader.GetInt64(16),
            reader.GetInt64(17),
            reader.IsDBNull(18) ? null : reader.GetInt64(18));
    }

    private static void AddParameters(
        SqliteCommand command,
        WorkflowTaskRecord task)
    {
        command.Parameters.AddWithValue("$id", task.Id);
        command.Parameters.AddWithValue("$kind", Serialize(task.Kind));
        command.Parameters.AddWithValue("$stage", Serialize(task.Stage));
        command.Parameters.AddWithValue("$status", Serialize(task.Status));
        command.Parameters.AddWithValue(
            "$generation",
            task.Generation.ToString("D"));
        AddNullable(command, "$rawText", task.RawText);
        AddNullable(command, "$partialText", task.PartialText);
        AddNullable(command, "$finalText", task.FinalText);
        AddNullable(command, "$providerId", task.ProviderId);
        AddNullable(command, "$model", task.Model);
        AddJson(command, "$targetJson", task.TargetJson);
        AddJson(command, "$contextJson", task.ContextJson);
        AddJson(command, "$traceJson", task.TraceJson);
        AddJson(command, "$outputJson", task.OutputJson);
        AddJson(command, "$failureJson", task.FailureJson);
        AddJson(command, "$warningsJson", task.WarningsJson);
        command.Parameters.AddWithValue("$createdAt", task.CreatedAtUnixMs);
        command.Parameters.AddWithValue("$updatedAt", task.UpdatedAtUnixMs);
        AddNullable(command, "$completedAt", task.CompletedAtUnixMs);
    }

    private static (string Sql, string? SearchPattern) BuildFilter(
        WorkflowTaskQuery query)
    {
        List<string> clauses = [];
        if (query.Kind is not null)
        {
            clauses.Add("kind = $kind");
        }

        string? searchPattern = null;
        if (query.SearchText is not null)
        {
            searchPattern = "%" + EscapeLike(query.SearchText) + "%";
            clauses.Add(
                "(raw_text LIKE $search ESCAPE '\\' COLLATE NOCASE " +
                "OR partial_text LIKE $search ESCAPE '\\' COLLATE NOCASE " +
                "OR final_text LIKE $search ESCAPE '\\' COLLATE NOCASE)");
        }

        return (
            clauses.Count == 0 ? string.Empty : " WHERE " + string.Join(" AND ", clauses),
            searchPattern);
    }

    private static void AddFilterParameters(
        SqliteCommand command,
        WorkflowTaskQuery query,
        string? searchPattern)
    {
        if (query.Kind is not null)
        {
            command.Parameters.AddWithValue("$kind", Serialize(query.Kind.Value));
        }
        if (searchPattern is not null)
        {
            command.Parameters.AddWithValue("$search", searchPattern);
        }
    }

    private static string EscapeLike(string value) => value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("%", "\\%", StringComparison.Ordinal)
        .Replace("_", "\\_", StringComparison.Ordinal);

    private static string? NullableString(SqliteDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);

    private static JsonElement? NullableJson(SqliteDataReader reader, int ordinal)
    {
        if (reader.IsDBNull(ordinal))
        {
            return null;
        }
        using var document = JsonDocument.Parse(reader.GetString(ordinal));
        return document.RootElement.Clone();
    }

    private static void AddJson(
        SqliteCommand command,
        string parameterName,
        JsonElement? value) =>
        AddNullable(command, parameterName, value?.GetRawText());

    private static void AddNullable(
        SqliteCommand command,
        string parameterName,
        object? value) =>
        command.Parameters.AddWithValue(parameterName, value ?? DBNull.Value);

    private static string Serialize<T>(T value)
        where T : struct, Enum =>
        JsonSerializer.Serialize(value, DomainJson.Options).Trim('"');

    private static T Parse<T>(string value)
        where T : struct, Enum
    {
        try
        {
            return JsonSerializer.Deserialize<T>(
                JsonSerializer.Serialize(value),
                DomainJson.Options);
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException(
                "Stored workflow task enum value is invalid.",
                exception);
        }
    }

    private static void ValidateId(string id) =>
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
}
