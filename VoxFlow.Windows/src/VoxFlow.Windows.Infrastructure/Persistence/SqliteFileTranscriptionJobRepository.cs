using System.Text.Json;
using Microsoft.Data.Sqlite;
using VoxFlow.Windows.Application.FileTranscription;
using VoxFlow.Windows.Domain;

namespace VoxFlow.Windows.Infrastructure.Persistence;

public sealed class SqliteFileTranscriptionJobRepository : IFileTranscriptionJobRepository
{
    private readonly SqliteTransactionRunner transactionRunner;

    public SqliteFileTranscriptionJobRepository(SqliteTransactionRunner transactionRunner)
    {
        this.transactionRunner = transactionRunner
            ?? throw new ArgumentNullException(nameof(transactionRunner));
    }

    public void Create(FileTranscriptionJob job)
    {
        ArgumentNullException.ThrowIfNull(job);

        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "INSERT INTO file_transcription_jobs(" +
                "id, source_path, display_name, provider_id, language, status, duration_ms, progress, " +
                "raw_text, final_text, error_code, provider_mode, segment_count, segment_completed, " +
                "partial_failure_summary, translation_status, translated_text, translation_target_language, " +
                "translation_error_code, translation_updated_at_unix_ms, created_at_unix_ms, " +
                "updated_at_unix_ms, completed_at_unix_ms" +
                ") VALUES (" +
                "$id, $sourcePath, $displayName, $providerId, $language, $status, $durationMs, $progress, " +
                "$rawText, $finalText, $errorCode, $providerMode, $segmentCount, $segmentCompleted, " +
                "$partialFailureSummary, $translationStatus, $translatedText, $translationTargetLanguage, " +
                "$translationErrorCode, $translationUpdatedAt, $createdAt, $updatedAt, $completedAt);";
            AddParameters(command, job);
            command.ExecuteNonQuery();
            return 0;
        });
    }

    public FileTranscriptionJob? Get(string id)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);

        return transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = SelectSql + " WHERE id = $id;";
            command.Parameters.AddWithValue("$id", id);
            using var reader = command.ExecuteReader();
            return reader.Read() ? ReadJob(reader) : null;
        });
    }

    public IReadOnlyList<FileTranscriptionJob> List() =>
        transactionRunner.Read(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = SelectSql + " ORDER BY created_at_unix_ms ASC, id ASC;";
            using var reader = command.ExecuteReader();
            List<FileTranscriptionJob> jobs = [];
            while (reader.Read())
            {
                jobs.Add(ReadJob(reader));
            }

            return jobs.ToArray();
        });

    public bool Update(FileTranscriptionJob job)
    {
        ArgumentNullException.ThrowIfNull(job);

        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE file_transcription_jobs SET " +
                "status = $status, duration_ms = $durationMs, progress = $progress, " +
                "raw_text = $rawText, final_text = $finalText, error_code = $errorCode, " +
                "provider_mode = $providerMode, segment_count = $segmentCount, " +
                "segment_completed = $segmentCompleted, partial_failure_summary = $partialFailureSummary, " +
                "translation_status = $translationStatus, translated_text = $translatedText, " +
                "translation_target_language = $translationTargetLanguage, " +
                "translation_error_code = $translationErrorCode, " +
                "translation_updated_at_unix_ms = $translationUpdatedAt, " +
                "updated_at_unix_ms = $updatedAt, completed_at_unix_ms = $completedAt WHERE id = $id;";
            AddParameters(command, job);
            return command.ExecuteNonQuery() == 1;
        });
    }

    public bool Delete(string id)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);

        return transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "DELETE FROM file_transcription_jobs WHERE id = $id;";
            command.Parameters.AddWithValue("$id", id);
            return command.ExecuteNonQuery() == 1;
        });
    }

    public int MarkRunningAsInterrupted() =>
        transactionRunner.Write((connection, transaction) =>
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText =
                "UPDATE file_transcription_jobs SET status = 'interrupted' " +
                "WHERE status = 'running';";
            return command.ExecuteNonQuery();
        });

    private const string SelectSql =
        "SELECT id, source_path, display_name, provider_id, language, status, duration_ms, progress, " +
        "raw_text, final_text, error_code, provider_mode, segment_count, segment_completed, " +
        "partial_failure_summary, translation_status, translated_text, translation_target_language, " +
        "translation_error_code, translation_updated_at_unix_ms, created_at_unix_ms, " +
        "updated_at_unix_ms, completed_at_unix_ms FROM file_transcription_jobs";

    private static void AddParameters(SqliteCommand command, FileTranscriptionJob job)
    {
        command.Parameters.AddWithValue("$id", job.Id);
        command.Parameters.AddWithValue("$sourcePath", job.SourcePath);
        command.Parameters.AddWithValue("$displayName", job.DisplayName);
        command.Parameters.AddWithValue("$providerId", Serialize(job.Provider));
        command.Parameters.AddWithValue("$language", Serialize(job.Language));
        command.Parameters.AddWithValue("$status", Serialize(job.Status));
        command.Parameters.AddWithValue("$durationMs", (object?)job.DurationMs ?? DBNull.Value);
        command.Parameters.AddWithValue("$progress", job.Progress);
        command.Parameters.AddWithValue("$rawText", (object?)job.RawText ?? DBNull.Value);
        command.Parameters.AddWithValue("$finalText", (object?)job.FinalText ?? DBNull.Value);
        command.Parameters.AddWithValue("$errorCode", SerializeNullable(job.ErrorCode));
        command.Parameters.AddWithValue("$providerMode", Serialize(job.ProviderMode));
        command.Parameters.AddWithValue("$segmentCount", job.SegmentCount);
        command.Parameters.AddWithValue("$segmentCompleted", job.SegmentCompleted);
        command.Parameters.AddWithValue(
            "$partialFailureSummary",
            (object?)job.PartialFailureSummary ?? DBNull.Value);
        command.Parameters.AddWithValue("$translationStatus", Serialize(job.TranslationStatus));
        command.Parameters.AddWithValue("$translatedText", (object?)job.TranslatedText ?? DBNull.Value);
        command.Parameters.AddWithValue(
            "$translationTargetLanguage",
            (object?)job.TranslationTargetLanguage ?? DBNull.Value);
        command.Parameters.AddWithValue(
            "$translationErrorCode",
            SerializeNullable(job.TranslationErrorCode));
        command.Parameters.AddWithValue(
            "$translationUpdatedAt",
            (object?)job.TranslationUpdatedAtUnixMs ?? DBNull.Value);
        command.Parameters.AddWithValue("$createdAt", job.CreatedAtUnixMs);
        command.Parameters.AddWithValue("$updatedAt", job.UpdatedAtUnixMs);
        command.Parameters.AddWithValue(
            "$completedAt",
            (object?)job.CompletedAtUnixMs ?? DBNull.Value);
    }

    private static FileTranscriptionJob ReadJob(SqliteDataReader reader) => new(
        id: reader.GetString(0),
        sourcePath: reader.GetString(1),
        displayName: reader.GetString(2),
        provider: Deserialize<AsrProviderId>(reader.GetString(3)),
        language: Deserialize<RecognitionLanguage>(reader.GetString(4)),
        createdAtUnixMs: reader.GetInt64(20),
        status: Deserialize<FileTranscriptionJobStatus>(reader.GetString(5)),
        durationMs: reader.IsDBNull(6) ? null : reader.GetInt64(6),
        progress: reader.GetDouble(7),
        rawText: reader.IsDBNull(8) ? null : reader.GetString(8),
        finalText: reader.IsDBNull(9) ? null : reader.GetString(9),
        errorCode: DeserializeNullable<FileTranscriptionErrorCode>(reader, 10),
        providerMode: Deserialize<FileTranscriptionProviderMode>(reader.GetString(11)),
        segmentCount: reader.GetInt32(12),
        segmentCompleted: reader.GetInt32(13),
        partialFailureSummary: reader.IsDBNull(14) ? null : reader.GetString(14),
        translationStatus: Deserialize<FileTranscriptionTranslationStatus>(reader.GetString(15)),
        translatedText: reader.IsDBNull(16) ? null : reader.GetString(16),
        translationTargetLanguage: reader.IsDBNull(17) ? null : reader.GetString(17),
        translationErrorCode: DeserializeNullable<FileTranscriptionErrorCode>(reader, 18),
        translationUpdatedAtUnixMs: reader.IsDBNull(19) ? null : reader.GetInt64(19),
        updatedAtUnixMs: reader.GetInt64(21),
        completedAtUnixMs: reader.IsDBNull(22) ? null : reader.GetInt64(22));

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
