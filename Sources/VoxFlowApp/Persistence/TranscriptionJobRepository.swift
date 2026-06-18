import Foundation

struct TranscriptionJobRecord: Equatable {
    let id: String
    let sourceFilePath: String
    let sourceFileName: String
    let status: String
    let progress: Double
    let rawText: String?
    let finalText: String?
    let asrProviderID: String?
    let styleID: String?
    let errorMessage: String?
    let durationMS: Int
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
}

protocol TranscriptionJobRepository {
    func save(_ job: TranscriptionJobRecord) throws
    func job(id: String) throws -> TranscriptionJobRecord?
    func list() throws -> [TranscriptionJobRecord]
    func delete(id: String) throws
    func updateStatus(id: String, status: String, progress: Double, updatedAt: Date) throws
}

final class SQLiteTranscriptionJobRepository: TranscriptionJobRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ job: TranscriptionJobRecord) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO transcription_jobs (
                    id, source_file_path, source_file_name, status, progress,
                    raw_text, final_text, asr_provider_id, style_id, error_message,
                    duration_ms, created_at, updated_at, completed_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    source_file_path = excluded.source_file_path,
                    source_file_name = excluded.source_file_name,
                    status = excluded.status,
                    progress = excluded.progress,
                    raw_text = excluded.raw_text,
                    final_text = excluded.final_text,
                    asr_provider_id = excluded.asr_provider_id,
                    style_id = excluded.style_id,
                    error_message = excluded.error_message,
                    duration_ms = excluded.duration_ms,
                    updated_at = excluded.updated_at,
                    completed_at = excluded.completed_at
                """
            )
            try statement.bind(job.id, at: 1)
            try statement.bind(job.sourceFilePath, at: 2)
            try statement.bind(job.sourceFileName, at: 3)
            try statement.bind(job.status, at: 4)
            try statement.bind(job.progress, at: 5)
            try statement.bind(job.rawText, at: 6)
            try statement.bind(job.finalText, at: 7)
            try statement.bind(job.asrProviderID, at: 8)
            try statement.bind(job.styleID, at: 9)
            try statement.bind(job.errorMessage, at: 10)
            try statement.bind(job.durationMS, at: 11)
            try statement.bind(formatter.string(from: job.createdAt), at: 12)
            try statement.bind(formatter.string(from: job.updatedAt), at: 13)
            try statement.bind(job.completedAt.map(formatter.string(from:)), at: 14)
            _ = try statement.step()
        }
    }

    func job(id: String) throws -> TranscriptionJobRecord? {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, source_file_path, source_file_name, status, progress,
                       raw_text, final_text, asr_provider_id, style_id, error_message,
                       duration_ms, created_at, updated_at, completed_at
                FROM transcription_jobs
                WHERE id = ?
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                return nil
            }
            return try row(from: statement)
        }
    }

    func updateStatus(id: String, status: String, progress: Double, updatedAt: Date) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE transcription_jobs
                SET status = ?, progress = ?, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(status, at: 1)
            try statement.bind(progress, at: 2)
            try statement.bind(formatter.string(from: updatedAt), at: 3)
            try statement.bind(id, at: 4)
            _ = try statement.step()
        }
    }

    func list() throws -> [TranscriptionJobRecord] {
        return try databaseQueue.read { connection in
            let stmt = try connection.prepare("SELECT id, source_file_path, source_file_name, status, progress, raw_text, final_text, asr_provider_id, style_id, error_message, duration_ms, created_at, updated_at, completed_at FROM transcription_jobs ORDER BY created_at DESC")
            var records: [TranscriptionJobRecord] = []
            while try stmt.step() { records.append(try row(from: stmt)) }
            return records
        }
    }

    func delete(id: String) throws {
        try databaseQueue.write { connection in
            let stmt = try connection.prepare("DELETE FROM transcription_jobs WHERE id = ?")
            try stmt.bind(id, at: 1); _ = try stmt.step()
        }
    }

    private func row(from statement: SQLiteStatement) throws -> TranscriptionJobRecord {
        guard let id = statement.columnString(at: 0),
              let sourceFilePath = statement.columnString(at: 1),
              let sourceFileName = statement.columnString(at: 2),
              let status = statement.columnString(at: 3),
              let createdAtText = statement.columnString(at: 11),
              let updatedAtText = statement.columnString(at: 12),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid transcription_jobs row.")
        }

        return TranscriptionJobRecord(
            id: id,
            sourceFilePath: sourceFilePath,
            sourceFileName: sourceFileName,
            status: status,
            progress: statement.columnDouble(at: 4),
            rawText: statement.columnString(at: 5),
            finalText: statement.columnString(at: 6),
            asrProviderID: statement.columnString(at: 7),
            styleID: statement.columnString(at: 8),
            errorMessage: statement.columnString(at: 9),
            durationMS: statement.columnInt(at: 10),
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: statement.columnString(at: 13).flatMap(formatter.date(from:))
        )
    }
}
