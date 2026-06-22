import Foundation

struct DictationHistoryEntry: Equatable {
    let id: String
    let rawText: String
    let finalText: String
    let language: String
    let asrProviderID: String?
    let llmProviderID: String?
    let styleID: String?
    let durationMS: Int
    let charCount: Int
    let cpm: Double
    let targetAppBundleID: String?
    let targetAppName: String?
    let processingWarningsJSON: String?
    let processingTraceJSON: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(
        id: String,
        rawText: String,
        finalText: String,
        language: String,
        asrProviderID: String?,
        llmProviderID: String?,
        styleID: String?,
        durationMS: Int,
        charCount: Int,
        cpm: Double,
        targetAppBundleID: String?,
        targetAppName: String?,
        processingWarningsJSON: String?,
        processingTraceJSON: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.id = id
        self.rawText = rawText
        self.finalText = finalText
        self.language = language
        self.asrProviderID = asrProviderID
        self.llmProviderID = llmProviderID
        self.styleID = styleID
        self.durationMS = durationMS
        self.charCount = charCount
        self.cpm = cpm
        self.targetAppBundleID = targetAppBundleID
        self.targetAppName = targetAppName
        self.processingWarningsJSON = processingWarningsJSON
        self.processingTraceJSON = processingTraceJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
protocol HistoryRepository {
    func save(_ entry: DictationHistoryEntry) throws
    func entry(id: String) throws -> DictationHistoryEntry?
    func listRecent(limit: Int) throws -> [DictationHistoryEntry]
    func listRecent(limit: Int, offset: Int) throws -> [DictationHistoryEntry]
    func search(_ query: String, limit: Int) throws -> [DictationHistoryEntry]
    func search(_ query: String, limit: Int, offset: Int) throws -> [DictationHistoryEntry]
    func softDelete(id: String, deletedAt: Date) throws
}

extension HistoryRepository {
    func listRecent(limit: Int, offset: Int) throws -> [DictationHistoryEntry] {
        let rows = try listRecent(limit: limit + offset)
        return Array(rows.dropFirst(offset))
    }

    func search(_ query: String, limit: Int, offset: Int) throws -> [DictationHistoryEntry] {
        let rows = try search(query, limit: limit + offset)
        return Array(rows.dropFirst(offset))
    }
}

final class SQLiteHistoryRepository: HistoryRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ entry: DictationHistoryEntry) throws {
        AppLogger.database.debug(
            "保存历史记录：id=\(entry.id), rawLen=\(entry.rawText.count), finalLen=\(entry.finalText.count)"
        )
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO dictation_history (
                    id, raw_text, final_text, language, asr_provider_id, llm_provider_id,
                    style_id, duration_ms, char_count, cpm, target_app_bundle_id,
                    target_app_name, processing_warnings_json, processing_trace_json,
                    created_at, updated_at, deleted_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    raw_text = excluded.raw_text,
                    final_text = excluded.final_text,
                    language = excluded.language,
                    asr_provider_id = excluded.asr_provider_id,
                    llm_provider_id = excluded.llm_provider_id,
                    style_id = excluded.style_id,
                    duration_ms = excluded.duration_ms,
                    char_count = excluded.char_count,
                    cpm = excluded.cpm,
                    target_app_bundle_id = excluded.target_app_bundle_id,
                    target_app_name = excluded.target_app_name,
                    processing_warnings_json = excluded.processing_warnings_json,
                    processing_trace_json = excluded.processing_trace_json,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    deleted_at = excluded.deleted_at
                """
            )
            try bind(entry, to: statement)
            _ = try statement.step()
        }
    }

    func entry(id: String) throws -> DictationHistoryEntry? {
        AppLogger.database.debug("查询历史记录：id=\(id)")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, raw_text, final_text, language, asr_provider_id, llm_provider_id,
                       style_id, duration_ms, char_count, cpm, target_app_bundle_id,
                       target_app_name, processing_warnings_json, processing_trace_json,
                       created_at, updated_at, deleted_at
                FROM dictation_history
                WHERE id = ?
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                AppLogger.database.warning("历史记录不存在：id=\(id)")
                return nil
            }
            return try row(from: statement)
        }
    }

    func listRecent(limit: Int) throws -> [DictationHistoryEntry] {
        AppLogger.database.debug("查询最近历史：limit=\(limit)")
        return try listRecent(limit: limit, offset: 0)
    }

    func listRecent(limit: Int, offset: Int) throws -> [DictationHistoryEntry] {
        return try query(
            """
            SELECT id, raw_text, final_text, language, asr_provider_id, llm_provider_id,
                   style_id, duration_ms, char_count, cpm, target_app_bundle_id,
                   target_app_name, processing_warnings_json, processing_trace_json,
                   created_at, updated_at, deleted_at
            FROM dictation_history
            WHERE deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT ?
            OFFSET ?
            """,
            bindings: { statement in
                try statement.bind(limit, at: 1)
                try statement.bind(offset, at: 2)
            }
        )
    }

    func search(_ queryText: String, limit: Int) throws -> [DictationHistoryEntry] {
        AppLogger.database.debug("搜索历史：queryLen=\(queryText.count), limit=\(limit)")
        return try search(queryText, limit: limit, offset: 0)
    }

    func search(_ queryText: String, limit: Int, offset: Int) throws -> [DictationHistoryEntry] {
        AppLogger.database.debug("搜索历史分页：queryLen=\(queryText.count), limit=\(limit), offset=\(offset)")
        return try query(
            """
            SELECT id, raw_text, final_text, language, asr_provider_id, llm_provider_id,
                   style_id, duration_ms, char_count, cpm, target_app_bundle_id,
                   target_app_name, processing_warnings_json, processing_trace_json,
                   created_at, updated_at, deleted_at
            FROM dictation_history
            WHERE deleted_at IS NULL
              AND (raw_text LIKE ? OR final_text LIKE ?)
            ORDER BY created_at DESC
            LIMIT ?
            OFFSET ?
            """,
            bindings: { statement in
                let pattern = "%\(queryText)%"
                try statement.bind(pattern, at: 1)
                try statement.bind(pattern, at: 2)
                try statement.bind(limit, at: 3)
                try statement.bind(offset, at: 4)
            }
        )
    }

    func softDelete(id: String, deletedAt: Date) throws {
        AppLogger.database.info("软删除历史：id=\(id), deletedAt=\(formatter.string(from: deletedAt))")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "UPDATE dictation_history SET deleted_at = ?, updated_at = ? WHERE id = ?"
            )
            let timestamp = formatter.string(from: deletedAt)
            try statement.bind(timestamp, at: 1)
            try statement.bind(timestamp, at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
    }

    private func query(
        _ sql: String,
        bindings: (SQLiteStatement) throws -> Void
    ) throws -> [DictationHistoryEntry] {
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(sql)
            try bindings(statement)
            var entries: [DictationHistoryEntry] = []
            while try statement.step() {
                entries.append(try row(from: statement))
            }
            AppLogger.database.debug("历史记录查询返回条数：count=\(entries.count)")
            return entries
        }
    }

    private func bind(_ entry: DictationHistoryEntry, to statement: SQLiteStatement) throws {
        try statement.bind(entry.id, at: 1)
        try statement.bind(entry.rawText, at: 2)
        try statement.bind(entry.finalText, at: 3)
        try statement.bind(entry.language, at: 4)
        try statement.bind(entry.asrProviderID, at: 5)
        try statement.bind(entry.llmProviderID, at: 6)
        try statement.bind(entry.styleID, at: 7)
        try statement.bind(entry.durationMS, at: 8)
        try statement.bind(entry.charCount, at: 9)
        try statement.bind(entry.cpm, at: 10)
        try statement.bind(entry.targetAppBundleID, at: 11)
        try statement.bind(entry.targetAppName, at: 12)
        try statement.bind(entry.processingWarningsJSON, at: 13)
        try statement.bind(entry.processingTraceJSON, at: 14)
        try statement.bind(formatter.string(from: entry.createdAt), at: 15)
        try statement.bind(formatter.string(from: entry.updatedAt), at: 16)
        try statement.bind(entry.deletedAt.map(formatter.string(from:)), at: 17)
    }

    private func row(from statement: SQLiteStatement) throws -> DictationHistoryEntry {
        guard let id = statement.columnString(at: 0),
              let rawText = statement.columnString(at: 1),
              let finalText = statement.columnString(at: 2),
              let language = statement.columnString(at: 3),
              let createdAtText = statement.columnString(at: 14),
              let updatedAtText = statement.columnString(at: 15),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            AppLogger.database.error("字典历史记录行数据缺失或日期格式错误")
            throw SQLiteError.stepFailed("Invalid dictation_history row.")
        }

        let deletedAt = statement.columnString(at: 16).flatMap(formatter.date(from:))
        return DictationHistoryEntry(
            id: id,
            rawText: rawText,
            finalText: finalText,
            language: language,
            asrProviderID: statement.columnString(at: 4),
            llmProviderID: statement.columnString(at: 5),
            styleID: statement.columnString(at: 6),
            durationMS: statement.columnInt(at: 7),
            charCount: statement.columnInt(at: 8),
            cpm: statement.columnDouble(at: 9),
            targetAppBundleID: statement.columnString(at: 10),
            targetAppName: statement.columnString(at: 11),
            processingWarningsJSON: statement.columnString(at: 12),
            processingTraceJSON: statement.columnString(at: 13),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
