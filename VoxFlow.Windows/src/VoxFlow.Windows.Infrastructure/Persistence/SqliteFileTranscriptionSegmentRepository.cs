using System.Text.Json;
using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteFileTranscriptionSegmentRepository : IFileTranscriptionSegmentRepository
{
    private readonly SqliteTransactionRunner transactionRunner;

    public SqliteFileTranscriptionSegmentRepository(SqliteTransactionRunner transactionRunner)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
    }

    public void Upsert(FileTranscriptionSegment segment)
    {
        ArgumentNullException.ThrowIfNull(segment);

        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO file_transcription_segments(" +
                "job_id, segment_index, start_ms, end_ms, status, provider_id, text, retry_count, provider_mode, " +
                "fallback_reason, error_code" +
                ") VALUES (" +
                "$jobId, $index, $startMs, $endMs, $status, $provider, $text, $retryCount, $providerMode, " +
                "$fallbackReason, $errorCode" +
                ") ON CONFLICT(job_id, segment_index) DO UPDATE SET " +
                "start_ms = excluded.start_ms, end_ms = excluded.end_ms, status = excluded.status, " +
                "provider_id = excluded.provider_id, " +
                "text = excluded.text, retry_count = excluded.retry_count, " +
                "provider_mode = excluded.provider_mode, fallback_reason = excluded.fallback_reason, " +
                "error_code = excluded.error_code;";
            AddParameters(command, segment);
            command.ExecuteNonQuery();
            return 0;
        });
    }

    public IReadOnlyList<FileTranscriptionSegment> ListByJob(string jobId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);

        return transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT job_id, segment_index, start_ms, end_ms, status, provider_id, text, retry_count, " +
                "provider_mode, fallback_reason, error_code " +
                "FROM file_transcription_segments WHERE job_id = $jobId " +
                "ORDER BY segment_index ASC;";
            command.Parameters.AddWithValue("$jobId", jobId);
            using var reader = command.ExecuteReader();
            List<FileTranscriptionSegment> segments = [];
            while (reader.Read())
            {
                segments.Add(ReadSegment(reader));
            }

            return segments.ToArray();
        });
    }

    public int DeleteByJob(string jobId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(jobId);

        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "DELETE FROM file_transcription_segments WHERE job_id = $jobId;";
            command.Parameters.AddWithValue("$jobId", jobId);
            return command.ExecuteNonQuery();
        });
    }

    public int MarkRunningAsInterrupted() =>
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE file_transcription_segments SET status = 'interrupted' " +
                "WHERE status = 'running';";
            return command.ExecuteNonQuery();
        });

    private static void AddParameters(SqliteCommand command, FileTranscriptionSegment segment)
    {
        command.Parameters.AddWithValue("$jobId", segment.JobId);
        command.Parameters.AddWithValue("$index", segment.Index);
        command.Parameters.AddWithValue("$startMs", segment.StartMs);
        command.Parameters.AddWithValue("$endMs", segment.EndMs);
        command.Parameters.AddWithValue("$status", Serialize(segment.Status));
        command.Parameters.AddWithValue("$provider", Serialize(segment.Provider));
        command.Parameters.AddWithValue("$text", (object?)segment.Text ?? DBNull.Value);
        command.Parameters.AddWithValue("$retryCount", segment.RetryCount);
        command.Parameters.AddWithValue("$providerMode", Serialize(segment.ProviderMode));
        command.Parameters.AddWithValue("$fallbackReason", Serialize(segment.FallbackReason));
        command.Parameters.AddWithValue("$errorCode", SerializeNullable(segment.ErrorCode));
    }

    private static FileTranscriptionSegment ReadSegment(SqliteDataReader reader) => new(
        reader.GetString(0),
        reader.GetInt32(1),
        reader.GetInt64(2),
        reader.GetInt64(3),
        Deserialize<FileTranscriptionSegmentStatus>(reader.GetString(4)),
        Deserialize<AsrProviderId>(reader.GetString(5)),
        reader.IsDBNull(6) ? null : reader.GetString(6),
        reader.GetInt32(7),
        Deserialize<FileTranscriptionProviderMode>(reader.GetString(8)),
        Deserialize<SegmentFallbackReason>(reader.GetString(9)),
        DeserializeNullable<FileTranscriptionErrorCode>(reader, 10));

    private static string Serialize<T>(T value) where T : struct, Enum =>
        JsonSerializer.Serialize(value, DomainJson.Options).Trim('"');

    private static object SerializeNullable<T>(T? value) where T : struct, Enum =>
        value is null ? DBNull.Value : Serialize(value.Value);

    private static T Deserialize<T>(string value) where T : struct, Enum =>
        JsonSerializer.Deserialize<T>($"\"{value}\"", DomainJson.Options);

    private static T? DeserializeNullable<T>(SqliteDataReader reader, int ordinal)
        where T : struct, Enum =>
        reader.IsDBNull(ordinal) ? null : Deserialize<T>(reader.GetString(ordinal));
}
