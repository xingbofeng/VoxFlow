import Foundation

enum AppDatabaseSchemaValidator {
    static func validate(connection: SQLiteConnection) throws {
        for table in expectedTables {
            try validate(table: table, connection: connection)
        }
        for index in expectedIndexes {
            try validate(index: index, connection: connection)
        }
    }

    private static func validate(table: ExpectedTable, connection: SQLiteConnection) throws {
        let actualColumns = try columns(in: table.name, connection: connection)
        guard !actualColumns.isEmpty else {
            throw AppDatabaseSchemaDriftError.missingTable(table.name)
        }
        let missingColumns = table.columns.filter { !actualColumns.contains($0) }
        guard missingColumns.isEmpty else {
            throw AppDatabaseSchemaDriftError.missingColumns(
                table: table.name,
                columns: missingColumns
            )
        }
    }

    private static func validate(index: ExpectedIndex, connection: SQLiteConnection) throws {
        let indexes = try indexes(on: index.table, connection: connection)
        guard indexes.contains(index.name) else {
            throw AppDatabaseSchemaDriftError.missingIndex(
                table: index.table,
                index: index.name
            )
        }
    }

    private static func columns(in table: String, connection: SQLiteConnection) throws -> Set<String> {
        let statement = try connection.prepare("PRAGMA table_info('\(escapedIdentifier(table))')")
        var columns: Set<String> = []
        while try statement.step() {
            if let name = statement.columnString(at: 1) {
                columns.insert(name)
            }
        }
        return columns
    }

    private static func indexes(on table: String, connection: SQLiteConnection) throws -> Set<String> {
        let statement = try connection.prepare("PRAGMA index_list('\(escapedIdentifier(table))')")
        var indexes: Set<String> = []
        while try statement.step() {
            if let name = statement.columnString(at: 1) {
                indexes.insert(name)
            }
        }
        return indexes
    }

    private static func escapedIdentifier(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private struct ExpectedTable {
        let name: String
        let columns: [String]
    }

    private struct ExpectedIndex {
        let table: String
        let name: String
    }

    private static let expectedTables: [ExpectedTable] = [
        ExpectedTable(
            name: "dictation_history",
            columns: [
                "id", "raw_text", "final_text", "language", "asr_provider_id",
                "llm_provider_id", "style_id", "duration_ms", "char_count", "cpm",
                "target_app_bundle_id", "target_app_name", "processing_warnings_json",
                "processing_trace_json", "created_at", "updated_at", "deleted_at"
            ]
        ),
        ExpectedTable(
            name: "voice_tasks",
            columns: [
                "id", "mode", "stage", "status", "target_app_bundle_id", "target_app_name",
                "target_app_pid", "target_window_id", "target_window_title",
                "audio_relative_path", "raw_transcript", "context_json", "final_text",
                "output_result", "failure_json", "asr_metadata_json", "warnings_json",
                "trace_json", "created_at", "updated_at", "completed_at"
            ]
        ),
        ExpectedTable(
            name: "screenshot_records",
            columns: [
                "id", "ocr_text", "translated_text", "summary_text", "image_path",
                "char_count", "is_favorited", "created_at", "updated_at", "deleted_at",
                "media_type", "video_path", "thumbnail_path", "duration_ms", "width", "height",
                "file_size_bytes", "audio_mode",
                "subtitle_status", "subtitle_draft_path", "subtitle_srt_path",
                "subtitled_video_path", "subtitle_error_message", "subtitle_updated_at"
            ]
        ),
        ExpectedTable(
            name: "asset_items",
            columns: [
                "id", "source", "content_type", "title", "preview_text", "text", "raw_text",
                "image_path", "file_path", "url", "color_value", "source_app_name",
                "source_app_bundle_id", "content_hash", "capture_reason", "metadata_json",
                "created_at", "updated_at", "deleted_at"
            ]
        ),
        ExpectedTable(
            name: "asset_items_fts",
            columns: [
                "title", "preview_text", "text", "source_app_name",
                "url", "file_path", "color_value"
            ]
        ),
        ExpectedTable(
            name: "voice_correction_rules",
            columns: [
                "id", "original", "replacement", "match_policy", "scope_type",
                "scope_value", "allowed_modes_json", "lifecycle", "source",
                "case_sensitive", "confidence", "observed_count", "applied_count",
                "reverted_count", "provider_id", "model_id", "language", "enabled",
                "created_at", "updated_at", "last_applied_at", "target_id"
            ]
        ),
        ExpectedTable(
            name: "voice_correction_events",
            columns: [
                "id", "rule_id", "original", "replacement", "range_location",
                "range_length", "scope_type", "scope_value", "source", "event_type",
                "created_at"
            ]
        ),
        ExpectedTable(
            name: "voice_correction_targets",
            columns: [
                "id", "text", "normalized_text", "scope_type", "scope_value", "lifecycle",
                "source", "observed_count", "applied_count", "reverted_count",
                "created_at", "updated_at", "last_applied_at",
                "hit_count", "is_blocklisted", "last_hit_at"
            ]
        )
    ]

    private static let expectedIndexes: [ExpectedIndex] = [
        ExpectedIndex(table: "dictation_history", name: "idx_dictation_history_created_at"),
        ExpectedIndex(table: "voice_tasks", name: "idx_voice_tasks_status"),
        ExpectedIndex(table: "voice_tasks", name: "idx_voice_tasks_created_at"),
        ExpectedIndex(table: "voice_tasks", name: "idx_voice_tasks_mode_created_at"),
        ExpectedIndex(table: "screenshot_records", name: "idx_screenshot_records_created_at"),
        ExpectedIndex(table: "screenshot_records", name: "idx_screenshot_records_deleted_created"),
        ExpectedIndex(table: "screenshot_records", name: "idx_screenshot_records_favorited"),
        ExpectedIndex(table: "screenshot_records", name: "idx_screenshot_records_media_type"),
        ExpectedIndex(table: "asset_items", name: "idx_asset_items_deleted_created_at"),
        ExpectedIndex(table: "asset_items", name: "idx_asset_items_source_deleted_created_at"),
        ExpectedIndex(table: "asset_items", name: "idx_asset_items_content_hash"),
        ExpectedIndex(table: "voice_correction_rules", name: "idx_voice_correction_rules_lifecycle"),
        ExpectedIndex(table: "voice_correction_events", name: "idx_voice_correction_events_created_at"),
        ExpectedIndex(table: "voice_correction_targets", name: "idx_voice_correction_targets_updated_at")
    ]
}

enum AppDatabaseSchemaDriftError: Error, Equatable, LocalizedError {
    case missingTable(String)
    case missingColumns(table: String, columns: [String])
    case missingIndex(table: String, index: String)

    var errorDescription: String? {
        switch self {
        case .missingTable(let table):
            return "Database schema drift: missing table \(table)."
        case .missingColumns(let table, let columns):
            return "Database schema drift: table \(table) missing columns \(columns.joined(separator: ", "))."
        case .missingIndex(let table, let index):
            return "Database schema drift: table \(table) missing index \(index)."
        }
    }
}
