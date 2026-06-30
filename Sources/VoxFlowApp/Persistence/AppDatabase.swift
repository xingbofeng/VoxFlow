import Foundation

enum AppDatabase {
    static func migrator(clock: any AppClock = SystemClock()) -> DatabaseMigrator {
        AppLogger.database.info("AppDatabase.migrator 创建")
        return DatabaseMigrator(
            migrations: [
                DatabaseMigration(id: 1, name: "initial_schema") { connection in
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 2, name: "dictation_history_processing_trace") { connection in
                    try connection.addColumnIfNeeded(
                        table: "dictation_history",
                        column: "processing_trace_json",
                        definition: "TEXT"
                    )
                },
                DatabaseMigration(id: 3, name: "voice_tasks") { connection in
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 4, name: "llm_provider_timeout_30s") { connection in
                    try connection.execute(
                        "UPDATE llm_providers SET timeout_seconds = 30 WHERE timeout_seconds = 8"
                    )
                },
                DatabaseMigration(id: 5, name: "voice_task_asr_metadata") { connection in
                    try connection.addColumnIfNeeded(
                        table: "voice_tasks",
                        column: "asr_metadata_json",
                        definition: "TEXT"
                    )
                },
                DatabaseMigration(id: 6, name: "drop_legacy_glossary_and_replacement_tables") { connection in
                    try connection.execute(
                        """
                        DROP TABLE IF EXISTS glossary_terms;
                        DROP TABLE IF EXISTS replacement_rules;
                        """
                    )
                },
                DatabaseMigration(id: 7, name: "voice_correction") { connection in
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 8, name: "voice_correction_scope_specific_unique_index") { connection in
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 9, name: "voice_correction_targets") { connection in
                    try applyBundledSchema(on: connection)
                    try connection.addColumnIfNeeded(
                        table: "voice_correction_rules",
                        column: "target_id",
                        definition: "TEXT"
                    )
                    try connection.execute(voiceCorrectionTargetBackfillSQL)
                },
                DatabaseMigration(id: 10, name: "home_dashboard_query_indexes") { connection in
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 11, name: "screenshot_records_table") { connection in
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 12, name: "asset_items_source_of_truth") { connection in
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 13, name: "voice_tasks_asset_backfill") { connection in
                    try applyBundledSchema(on: connection)
                    try connection.execute(voiceTaskAssetBackfillSQL)
                },
                DatabaseMigration(id: 14, name: "screenshot_records_asset_backfill") { connection in
                    try applyBundledSchema(on: connection)
                    try connection.execute(screenshotRecordAssetBackfillSQL)
                },
                DatabaseMigration(id: 15, name: "voice_tasks_asset_repair") { connection in
                    try applyBundledSchema(on: connection)
                    try connection.execute(voiceTaskAssetBackfillSQL)
                },
                DatabaseMigration(id: 16, name: "screenshot_records_media_columns") { connection in
                    // 先为老库幂等补齐媒体列，再应用 bundled schema。
                    // 顺序很重要：schema 快照包含引用 media_type 的索引，
                    // 必须在列存在后才能成功创建索引。
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "media_type",
                        definition: "TEXT NOT NULL DEFAULT 'screenshot'"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "video_path",
                        definition: "TEXT"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "thumbnail_path",
                        definition: "TEXT"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "duration_ms",
                        definition: "INTEGER NOT NULL DEFAULT 0"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "width",
                        definition: "INTEGER NOT NULL DEFAULT 0"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "height",
                        definition: "INTEGER NOT NULL DEFAULT 0"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "file_size_bytes",
                        definition: "INTEGER NOT NULL DEFAULT 0"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "audio_mode",
                        definition: "TEXT NOT NULL DEFAULT 'none'"
                    )
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 17, name: "screenshot_records_subtitle_columns") { connection in
                    // 为老库幂等补齐字幕字段，再应用 bundled schema 快照。
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "subtitle_status",
                        definition: "TEXT NOT NULL DEFAULT 'none'"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "subtitle_draft_path",
                        definition: "TEXT"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "subtitle_srt_path",
                        definition: "TEXT"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "subtitled_video_path",
                        definition: "TEXT"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "subtitle_error_message",
                        definition: "TEXT"
                    )
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: "subtitle_updated_at",
                        definition: "TEXT"
                    )
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 18, name: "asset_items_fts") { connection in
                    try applyBundledSchema(on: connection)
                    try rebuildAssetItemsFTS(on: connection)
                },
                DatabaseMigration(id: 19, name: "hotword_columns") { connection in
                    try connection.addColumnIfNeeded(
                        table: "voice_correction_targets",
                        column: "hit_count",
                        definition: "INTEGER NOT NULL DEFAULT 0"
                    )
                    try connection.addColumnIfNeeded(
                        table: "voice_correction_targets",
                        column: "is_blocklisted",
                        definition: "INTEGER NOT NULL DEFAULT 0"
                    )
                    try connection.addColumnIfNeeded(
                        table: "voice_correction_targets",
                        column: "last_hit_at",
                        definition: "TEXT"
                    )
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 20, name: "voice_correction_evidence") { connection in
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 21, name: "style_profiles_auto_match") { connection in
                    // 为老库幂等补齐 style 自动匹配列；新库由 bundled schema 直接建表。
                    // allow_auto_match 默认 0：既有 style 不主动加入 AI router 候选，
                    // 用户必须显式打开参与自动匹配 (OpenSpec §4.1)。
                    try connection.addColumnIfNeeded(
                        table: "style_profiles",
                        column: "allow_auto_match",
                        definition: "INTEGER NOT NULL DEFAULT 0"
                    )
                    try connection.addColumnIfNeeded(
                        table: "style_profiles",
                        column: "auto_match_description",
                        definition: "TEXT"
                    )
                    try applyBundledSchema(on: connection)
                },
                DatabaseMigration(id: 22, name: "style_profiles_output_format") { connection in
                    try connection.addColumnIfNeeded(
                        table: "style_profiles",
                        column: "output_format_json",
                        definition: "TEXT"
                    )
                    try applyBundledSchema(on: connection)
                }
            ],
            clock: clock
        )
    }

    static func bootstrapFromSnapshotIfEnabled(on databaseQueue: DatabaseQueue) throws {
        #if DEBUG
        guard shouldBootstrapFromSnapshotFromEnvironment else {
            return
        }

        AppLogger.database.warning("AppDatabase bootstrap from bundled AppDatabaseSchema.sql")
        try databaseQueue.write { connection in
            try applyBundledSchema(on: connection)
        }
        AppLogger.database.warning("AppDatabase bootstrap from bundled schema finished")
        #endif
    }

    private static var shouldBootstrapFromSnapshotFromEnvironment: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--voxflow-apply-db-schema") {
            return true
        }

        guard let value = ProcessInfo.processInfo.environment["VOXFLOW_DB_SCHEMA_SQL"] else {
            return false
        }
        return value == "1" || value.lowercased() == "true" || value.lowercased() == "yes"
        #else
        return false
        #endif
    }

    static func loadBundledSchemaSQL() throws -> String {
        guard let schemaURL = VoxFlowAppResourceBundle.url(forResource: "AppDatabaseSchema", withExtension: "sql")
            ?? VoxFlowAppResourceBundle.url(
                forResource: "AppDatabaseSchema",
                withExtension: "sql",
                subdirectory: "Persistence"
            )
        else {
            throw AppDatabaseSchemaError.missingBundledSchema
        }
        return try String(contentsOf: schemaURL, encoding: .utf8)
    }

    private static func applyBundledSchema(on connection: SQLiteConnection) throws {
        try connection.execute(try loadBundledSchemaSQL())
    }

    private static func rebuildAssetItemsFTS(on connection: SQLiteConnection) throws {
        try connection.execute("INSERT INTO asset_items_fts(asset_items_fts) VALUES('rebuild')")
    }

    static func ensureRequiredRuntimeTables(_ databaseQueue: DatabaseQueue) throws {
        try databaseQueue.write { connection in
            try applyBundledSchema(on: connection)
        }
    }

    enum AppDatabaseSchemaError: LocalizedError {
        case missingBundledSchema

        var errorDescription: String? {
            switch self {
            case .missingBundledSchema:
                return "Bundled AppDatabaseSchema.sql not found."
            }
        }
    }

    static let voiceCorrectionTargetBackfillSQL = """
    INSERT OR IGNORE INTO voice_correction_targets (
        id, text, normalized_text, scope_type, scope_value,
        lifecycle, source, observed_count, applied_count, reverted_count,
        created_at, updated_at, last_applied_at
    )
    SELECT
        lower(hex(randomblob(4))) || '-' ||
            lower(hex(randomblob(2))) || '-4' ||
            substr(lower(hex(randomblob(2))), 2) || '-' ||
            substr('89ab', abs(random()) % 4 + 1, 1) ||
            substr(lower(hex(randomblob(2))), 2) || '-' ||
            lower(hex(randomblob(6))),
        trim(replacement),
        lower(trim(replacement)),
        scope_type,
        scope_value,
        CASE
            WHEN SUM(CASE WHEN lifecycle = 'active' AND enabled = 1 THEN 1 ELSE 0 END) > 0 THEN 'active'
            WHEN SUM(CASE WHEN lifecycle = 'candidate' THEN 1 ELSE 0 END) > 0 THEN 'candidate'
            ELSE 'suspended'
        END,
        CASE
            WHEN SUM(CASE WHEN source = 'manual' THEN 1 ELSE 0 END) > 0 THEN 'manual'
            WHEN SUM(CASE WHEN source = 'automaticLearning' THEN 1 ELSE 0 END) > 0 THEN 'automaticLearning'
            ELSE 'imported'
        END,
        SUM(observed_count),
        SUM(applied_count),
        SUM(reverted_count),
        MIN(created_at),
        MAX(updated_at),
        MAX(last_applied_at)
    FROM voice_correction_rules
    WHERE target_id IS NULL
      AND trim(replacement) != ''
    GROUP BY scope_type, IFNULL(scope_value, ''), lower(trim(replacement));

    UPDATE voice_correction_rules
    SET target_id = (
        SELECT target.id
        FROM voice_correction_targets AS target
        WHERE target.scope_type = voice_correction_rules.scope_type
          AND IFNULL(target.scope_value, '') = IFNULL(voice_correction_rules.scope_value, '')
          AND target.normalized_text = lower(trim(voice_correction_rules.replacement))
        LIMIT 1
    )
    WHERE target_id IS NULL
      AND trim(replacement) != '';
    """

    private static let voiceTaskAssetBackfillSQLTemplate = """
    WITH eligible_voice_tasks AS (
        SELECT
            id,
            mode,
            raw_transcript,
            final_text,
            output_result,
            target_app_bundle_id,
            target_app_name,
            COALESCE(completed_at, updated_at, created_at) AS asset_created_at,
            CASE
                WHEN mode IN ('agentCompose', 'agentDispatch')
                  AND raw_transcript IS NOT NULL
                  AND trim(raw_transcript) != ''
                THEN raw_transcript
                ELSE final_text
            END AS asset_text
        FROM voice_tasks
        WHERE mode IN ('dictation', 'agentCompose', 'agentDispatch')
          AND status IN ('completed', 'partiallyCompleted')
          AND final_text IS NOT NULL
          AND trim(final_text) != ''
          AND IFNULL(output_result, '') NOT LIKE '%%"kind":"failed"%%'
          AND IFNULL(output_result, '') NOT LIKE '%%"kind":"cancelled"%%'
    ),
    normalized_voice_tasks AS (
        SELECT
            id,
            raw_transcript,
            output_result,
            target_app_bundle_id,
            target_app_name,
            asset_created_at,
            asset_text,
            trim(replace(replace(asset_text, char(13), ' '), char(10), ' ')) AS collapsed_title
        FROM eligible_voice_tasks
        WHERE asset_text IS NOT NULL
          AND trim(asset_text) != ''
    )
    INSERT OR IGNORE INTO asset_items (
        id,
        source,
        content_type,
        title,
        preview_text,
        text,
        raw_text,
        image_path,
        file_path,
        url,
        color_value,
        source_app_name,
        source_app_bundle_id,
        content_hash,
        capture_reason,
        metadata_json,
        created_at,
        updated_at,
        deleted_at
    )
    SELECT
        'dictation-' || id,
        'dictation',
        'text',
        CASE
            WHEN collapsed_title = '' THEN '%@'
            WHEN length(collapsed_title) > 80 THEN substr(collapsed_title, 1, 80)
            ELSE collapsed_title
        END,
        asset_text,
        asset_text,
        raw_transcript,
        NULL,
        NULL,
        NULL,
        NULL,
        target_app_name,
        target_app_bundle_id,
        'dictation-' || id,
        CASE
            WHEN IFNULL(output_result, '') LIKE '%%"kind":"inserted"%%' THEN 'dictationCompleted'
            ELSE 'fallbackCopied'
        END,
        NULL,
        asset_created_at,
        asset_created_at,
        NULL
    FROM normalized_voice_tasks;
    """

    static var voiceTaskAssetBackfillSQL: String {
        String(
            format: voiceTaskAssetBackfillSQLTemplate,
            L10n.localize("db.voice_task.default_title", comment: "")
        )
    }

    static let screenshotRecordAssetBackfillSQL = """
    WITH eligible_screenshots AS (
        SELECT
            id,
            ocr_text,
            image_path,
            created_at,
            updated_at,
            trim(replace(replace(ocr_text, char(13), ' '), char(10), ' ')) AS collapsed_text
        FROM screenshot_records
        WHERE deleted_at IS NULL
          AND image_path IS NOT NULL
          AND trim(image_path) != ''
    )
    INSERT OR IGNORE INTO asset_items (
        id,
        source,
        content_type,
        title,
        preview_text,
        text,
        raw_text,
        image_path,
        file_path,
        url,
        color_value,
        source_app_name,
        source_app_bundle_id,
        content_hash,
        capture_reason,
        metadata_json,
        created_at,
        updated_at,
        deleted_at
    )
    SELECT
        'screenshot-' || id,
        'screenshot',
        'image',
        CASE
            WHEN collapsed_text = '' THEN 'Image'
            WHEN length(collapsed_text) > 80 THEN substr(collapsed_text, 1, 80)
            ELSE collapsed_text
        END,
        NULLIF(ocr_text, ''),
        NULLIF(ocr_text, ''),
        NULL,
        image_path,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        'screenshot-' || id,
        'screenshotCaptured',
        NULL,
        created_at,
        updated_at,
        NULL
    FROM eligible_screenshots;
    """
}
