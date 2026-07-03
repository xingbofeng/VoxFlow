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
    // 文件转写流水线扩展（OpenSpec revamp-file-transcription-and-notes §1.3）。
    let providerMode: String?
    let segmentCount: Int
    let segmentCompleted: Int
    let partialFailureSummary: String?
    // 全文翻译后处理字段（OpenSpec revamp-file-transcription-and-notes §1.3）。
    let translatedText: String?
    let translationTargetLanguage: String?
    let translationProvider: String?
    let translationStatus: String
    let translationError: String?
    let translationUpdatedAt: Date?

    init(
        id: String,
        sourceFilePath: String,
        sourceFileName: String,
        status: String,
        progress: Double,
        rawText: String?,
        finalText: String?,
        asrProviderID: String?,
        styleID: String?,
        errorMessage: String?,
        durationMS: Int,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?,
        providerMode: String? = nil,
        segmentCount: Int = 0,
        segmentCompleted: Int = 0,
        partialFailureSummary: String? = nil,
        translatedText: String? = nil,
        translationTargetLanguage: String? = nil,
        translationProvider: String? = nil,
        translationStatus: String = TranslationStatus.none.rawValue,
        translationError: String? = nil,
        translationUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.sourceFilePath = sourceFilePath
        self.sourceFileName = sourceFileName
        self.status = status
        self.progress = progress
        self.rawText = rawText
        self.finalText = finalText
        self.asrProviderID = asrProviderID
        self.styleID = styleID
        self.errorMessage = errorMessage
        self.durationMS = durationMS
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.providerMode = providerMode
        self.segmentCount = segmentCount
        self.segmentCompleted = segmentCompleted
        self.partialFailureSummary = partialFailureSummary
        self.translatedText = translatedText
        self.translationTargetLanguage = translationTargetLanguage
        self.translationProvider = translationProvider
        self.translationStatus = translationStatus
        self.translationError = translationError
        self.translationUpdatedAt = translationUpdatedAt
    }
}

enum TranslationStatus: String {
    case none
    case pending
    case running
    case completed
    case failed
}

enum TranscriptionSegmentStatus: String {
    case pending
    case running
    case completed
    case failed
    case interrupted
    case cancelled
}

enum TranscriptionProviderMode: String {
    case nativeFile
    case segmentedCompatible
    case notRecommendedForLongFiles
}

enum SegmentFallbackReason: String {
    case emptyResult
    case timeout
    case providerError
    case duplicateText
    case lowConfidence
}

struct TranscriptionSegmentRecord: Equatable {
    let id: String
    let jobID: String
    let index: Int
    let startMS: Int
    let endMS: Int
    let status: String
    let rawText: String?
    let finalText: String?
    let promptContext: String?
    let fallbackReason: String?
    let retryCount: Int
    let providerID: String?
    let providerMode: String?
    let errorMessage: String?
    let durationMS: Int
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?

    init(
        id: String,
        jobID: String,
        index: Int,
        startMS: Int,
        endMS: Int,
        status: String = TranscriptionSegmentStatus.pending.rawValue,
        rawText: String? = nil,
        finalText: String? = nil,
        promptContext: String? = nil,
        fallbackReason: String? = nil,
        retryCount: Int = 0,
        providerID: String? = nil,
        providerMode: String? = nil,
        errorMessage: String? = nil,
        durationMS: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.index = index
        self.startMS = startMS
        self.endMS = endMS
        self.status = status
        self.rawText = rawText
        self.finalText = finalText
        self.promptContext = promptContext
        self.fallbackReason = fallbackReason
        self.retryCount = retryCount
        self.providerID = providerID
        self.providerMode = providerMode
        self.errorMessage = errorMessage
        self.durationMS = durationMS
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

protocol TranscriptionJobRepository {
    func save(_ job: TranscriptionJobRecord) throws
    func job(id: String) throws -> TranscriptionJobRecord?
    func list() throws -> [TranscriptionJobRecord]
    func delete(id: String) throws
    func updateStatus(id: String, status: String, progress: Double, updatedAt: Date) throws
    func updateSegmentsAndProgress(
        id: String,
        status: String,
        progress: Double,
        segmentCount: Int,
        segmentCompleted: Int,
        partialFailureSummary: String?,
        updatedAt: Date
    ) throws
    func updateTranslation(
        id: String,
        translatedText: String?,
        targetLanguage: String?,
        provider: String?,
        status: TranslationStatus,
        error: String?,
        updatedAt: Date
    ) throws
}

protocol TranscriptionSegmentRepository {
    func save(_ segment: TranscriptionSegmentRecord) throws
    func segments(forJob jobID: String) throws -> [TranscriptionSegmentRecord]
    func deleteAll(forJob jobID: String) throws
    func delete(id: String) throws
    func markRunningSegmentsInterrupted(jobID: String, updatedAt: Date) throws
}

final class SQLiteTranscriptionJobRepository: TranscriptionJobRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ job: TranscriptionJobRecord) throws {
        AppLogger.database.debug("保存转录任务：id=\(job.id), status=\(job.status)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO transcription_jobs (
                    id, source_file_path, source_file_name, status, progress,
                    raw_text, final_text, asr_provider_id, style_id, error_message,
                    duration_ms, created_at, updated_at, completed_at,
                    provider_mode, segment_count, segment_completed, partial_failure_summary,
                    translated_text, translation_target_language, translation_provider,
                    translation_status, translation_error, translation_updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    completed_at = excluded.completed_at,
                    provider_mode = excluded.provider_mode,
                    segment_count = excluded.segment_count,
                    segment_completed = excluded.segment_completed,
                    partial_failure_summary = excluded.partial_failure_summary,
                    translated_text = excluded.translated_text,
                    translation_target_language = excluded.translation_target_language,
                    translation_provider = excluded.translation_provider,
                    translation_status = excluded.translation_status,
                    translation_error = excluded.translation_error,
                    translation_updated_at = excluded.translation_updated_at
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
            try statement.bind(job.providerMode, at: 15)
            try statement.bind(job.segmentCount, at: 16)
            try statement.bind(job.segmentCompleted, at: 17)
            try statement.bind(job.partialFailureSummary, at: 18)
            try statement.bind(job.translatedText, at: 19)
            try statement.bind(job.translationTargetLanguage, at: 20)
            try statement.bind(job.translationProvider, at: 21)
            try statement.bind(job.translationStatus, at: 22)
            try statement.bind(job.translationError, at: 23)
            try statement.bind(job.translationUpdatedAt.map(formatter.string(from:)), at: 24)
            _ = try statement.step()
        }
        AppLogger.database.info("转录任务已保存：id=\(job.id)")
    }

    func job(id: String) throws -> TranscriptionJobRecord? {
        AppLogger.database.debug("查询转录任务：id=\(id)")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, source_file_path, source_file_name, status, progress,
                       raw_text, final_text, asr_provider_id, style_id, error_message,
                       duration_ms, created_at, updated_at, completed_at,
                       provider_mode, segment_count, segment_completed, partial_failure_summary,
                       translated_text, translation_target_language, translation_provider,
                       translation_status, translation_error, translation_updated_at
                FROM transcription_jobs
                WHERE id = ?
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                AppLogger.database.warning("转录任务不存在：id=\(id)")
                return nil
            }
            return try row(from: statement)
        }
    }

    func updateStatus(id: String, status: String, progress: Double, updatedAt: Date) throws {
        AppLogger.database.debug(
            "更新转录任务状态：id=\(id), status=\(status), progress=\(progress)"
        )
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

    func updateSegmentsAndProgress(
        id: String,
        status: String,
        progress: Double,
        segmentCount: Int,
        segmentCompleted: Int,
        partialFailureSummary: String?,
        updatedAt: Date
    ) throws {
        AppLogger.database.debug(
            "更新转录任务段级进度：id=\(id), status=\(status), segments=\(segmentCompleted)/\(segmentCount)"
        )
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE transcription_jobs
                SET status = ?,
                    progress = ?,
                    segment_count = ?,
                    segment_completed = ?,
                    partial_failure_summary = ?,
                    updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(status, at: 1)
            try statement.bind(progress, at: 2)
            try statement.bind(segmentCount, at: 3)
            try statement.bind(segmentCompleted, at: 4)
            try statement.bind(partialFailureSummary, at: 5)
            try statement.bind(formatter.string(from: updatedAt), at: 6)
            try statement.bind(id, at: 7)
            _ = try statement.step()
        }
    }

    func updateTranslation(
        id: String,
        translatedText: String?,
        targetLanguage: String?,
        provider: String?,
        status: TranslationStatus,
        error: String?,
        updatedAt: Date
    ) throws {
        AppLogger.database.debug(
            "更新转录任务翻译：id=\(id), status=\(status.rawValue), target=\(targetLanguage ?? "nil")"
        )
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE transcription_jobs
                SET translated_text = ?,
                    translation_target_language = ?,
                    translation_provider = ?,
                    translation_status = ?,
                    translation_error = ?,
                    translation_updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(translatedText, at: 1)
            try statement.bind(targetLanguage, at: 2)
            try statement.bind(provider, at: 3)
            try statement.bind(status.rawValue, at: 4)
            try statement.bind(error, at: 5)
            try statement.bind(formatter.string(from: updatedAt), at: 6)
            try statement.bind(id, at: 7)
            _ = try statement.step()
        }
    }

    func list() throws -> [TranscriptionJobRecord] {
        AppLogger.database.debug("列出转录任务")
        return try databaseQueue.read { connection in
            let stmt = try connection.prepare(
                """
                SELECT id, source_file_path, source_file_name, status, progress,
                       raw_text, final_text, asr_provider_id, style_id, error_message,
                       duration_ms, created_at, updated_at, completed_at,
                       provider_mode, segment_count, segment_completed, partial_failure_summary,
                       translated_text, translation_target_language, translation_provider,
                       translation_status, translation_error, translation_updated_at
                FROM transcription_jobs
                ORDER BY created_at DESC
                """
            )
            var records: [TranscriptionJobRecord] = []
            while try stmt.step() { records.append(try row(from: stmt)) }
            AppLogger.database.debug("转录任务列表返回 count=\(records.count)")
            return records
        }
    }

    func delete(id: String) throws {
        AppLogger.database.warning("删除转录任务：id=\(id)")
        try databaseQueue.write { connection in
            // 显式级联清理 segments；SQLite 默认不开启 foreign_keys，
            // 这里不依赖 ON DELETE CASCADE，避免遗漏清理。
            let segmentStmt = try connection.prepare(
                "DELETE FROM transcription_segments WHERE job_id = ?"
            )
            try segmentStmt.bind(id, at: 1); _ = try segmentStmt.step()
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

        let translationStatusRaw = statement.columnString(at: 21) ?? TranslationStatus.none.rawValue
        let translationUpdatedAt = statement.columnString(at: 23).flatMap(formatter.date(from:))

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
            completedAt: statement.columnString(at: 13).flatMap(formatter.date(from:)),
            providerMode: statement.columnString(at: 14),
            segmentCount: statement.columnInt(at: 15),
            segmentCompleted: statement.columnInt(at: 16),
            partialFailureSummary: statement.columnString(at: 17),
            translatedText: statement.columnString(at: 18),
            translationTargetLanguage: statement.columnString(at: 19),
            translationProvider: statement.columnString(at: 20),
            translationStatus: translationStatusRaw,
            translationError: statement.columnString(at: 22),
            translationUpdatedAt: translationUpdatedAt
        )
    }
}

final class SQLiteTranscriptionSegmentRepository: TranscriptionSegmentRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ segment: TranscriptionSegmentRecord) throws {
        AppLogger.database.debug(
            "保存转录段：id=\(segment.id), job=\(segment.jobID), index=\(segment.index), status=\(segment.status)"
        )
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO transcription_segments (
                    id, job_id, segment_index, start_ms, end_ms, status,
                    raw_text, final_text, prompt_context, fallback_reason, retry_count,
                    provider_id, provider_mode, error_message, duration_ms,
                    created_at, updated_at, completed_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    job_id = excluded.job_id,
                    segment_index = excluded.segment_index,
                    start_ms = excluded.start_ms,
                    end_ms = excluded.end_ms,
                    status = excluded.status,
                    raw_text = excluded.raw_text,
                    final_text = excluded.final_text,
                    prompt_context = excluded.prompt_context,
                    fallback_reason = excluded.fallback_reason,
                    retry_count = excluded.retry_count,
                    provider_id = excluded.provider_id,
                    provider_mode = excluded.provider_mode,
                    error_message = excluded.error_message,
                    duration_ms = excluded.duration_ms,
                    updated_at = excluded.updated_at,
                    completed_at = excluded.completed_at
                """
            )
            try statement.bind(segment.id, at: 1)
            try statement.bind(segment.jobID, at: 2)
            try statement.bind(segment.index, at: 3)
            try statement.bind(segment.startMS, at: 4)
            try statement.bind(segment.endMS, at: 5)
            try statement.bind(segment.status, at: 6)
            try statement.bind(segment.rawText, at: 7)
            try statement.bind(segment.finalText, at: 8)
            try statement.bind(segment.promptContext, at: 9)
            try statement.bind(segment.fallbackReason, at: 10)
            try statement.bind(segment.retryCount, at: 11)
            try statement.bind(segment.providerID, at: 12)
            try statement.bind(segment.providerMode, at: 13)
            try statement.bind(segment.errorMessage, at: 14)
            try statement.bind(segment.durationMS, at: 15)
            try statement.bind(formatter.string(from: segment.createdAt), at: 16)
            try statement.bind(formatter.string(from: segment.updatedAt), at: 17)
            try statement.bind(segment.completedAt.map(formatter.string(from:)), at: 18)
            _ = try statement.step()
        }
    }

    func segments(forJob jobID: String) throws -> [TranscriptionSegmentRecord] {
        AppLogger.database.debug("列出转录段：job=\(jobID)")
        return try databaseQueue.read { connection in
            let stmt = try connection.prepare(
                """
                SELECT id, job_id, segment_index, start_ms, end_ms, status,
                       raw_text, final_text, prompt_context, fallback_reason, retry_count,
                       provider_id, provider_mode, error_message, duration_ms,
                       created_at, updated_at, completed_at
                FROM transcription_segments
                WHERE job_id = ?
                ORDER BY segment_index ASC
                """
            )
            try stmt.bind(jobID, at: 1)
            var records: [TranscriptionSegmentRecord] = []
            while try stmt.step() { records.append(try row(from: stmt)) }
            return records
        }
    }

    func deleteAll(forJob jobID: String) throws {
        AppLogger.database.warning("删除转录段（按 job）：job=\(jobID)")
        try databaseQueue.write { connection in
            let stmt = try connection.prepare(
                "DELETE FROM transcription_segments WHERE job_id = ?"
            )
            try stmt.bind(jobID, at: 1); _ = try stmt.step()
        }
    }

    func delete(id: String) throws {
        AppLogger.database.warning("删除转录段：id=\(id)")
        try databaseQueue.write { connection in
            let stmt = try connection.prepare(
                "DELETE FROM transcription_segments WHERE id = ?"
            )
            try stmt.bind(id, at: 1); _ = try stmt.step()
        }
    }

    func markRunningSegmentsInterrupted(jobID: String, updatedAt: Date) throws {
        AppLogger.database.warning("标记中断转录段：job=\(jobID)")
        try databaseQueue.write { connection in
            let stmt = try connection.prepare(
                """
                UPDATE transcription_segments
                SET status = ?, updated_at = ?, completed_at = ?
                WHERE job_id = ? AND status = ?
                """
            )
            try stmt.bind(TranscriptionSegmentStatus.interrupted.rawValue, at: 1)
            try stmt.bind(formatter.string(from: updatedAt), at: 2)
            try stmt.bind(formatter.string(from: updatedAt), at: 3)
            try stmt.bind(jobID, at: 4)
            try stmt.bind(TranscriptionSegmentStatus.running.rawValue, at: 5)
            _ = try stmt.step()
        }
    }

    private func row(from statement: SQLiteStatement) throws -> TranscriptionSegmentRecord {
        guard let id = statement.columnString(at: 0),
              let jobID = statement.columnString(at: 1),
              let status = statement.columnString(at: 5),
              let createdAtText = statement.columnString(at: 15),
              let updatedAtText = statement.columnString(at: 16),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid transcription_segments row.")
        }

        return TranscriptionSegmentRecord(
            id: id,
            jobID: jobID,
            index: statement.columnInt(at: 2),
            startMS: statement.columnInt(at: 3),
            endMS: statement.columnInt(at: 4),
            status: status,
            rawText: statement.columnString(at: 6),
            finalText: statement.columnString(at: 7),
            promptContext: statement.columnString(at: 8),
            fallbackReason: statement.columnString(at: 9),
            retryCount: statement.columnInt(at: 10),
            providerID: statement.columnString(at: 11),
            providerMode: statement.columnString(at: 12),
            errorMessage: statement.columnString(at: 13),
            durationMS: statement.columnInt(at: 14),
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: statement.columnString(at: 17).flatMap(formatter.date(from:))
        )
    }
}
