import Foundation

enum AppDatabase {
    static func migrator(clock: any AppClock = SystemClock()) -> DatabaseMigrator {
        AppLogger.database.info("AppDatabase.migrator 创建")
        return DatabaseMigrator(
            migrations: [
                DatabaseMigration(id: 1, name: "initial_schema") { connection in
                    try connection.execute(initialSchemaSQL)
                },
                DatabaseMigration(id: 2, name: "dictation_history_processing_trace") { connection in
                    try connection.addColumnIfNeeded(
                        table: "dictation_history",
                        column: "processing_trace_json",
                        definition: "TEXT"
                    )
                },
                DatabaseMigration(id: 3, name: "voice_tasks") { connection in
                    try connection.execute(voiceTasksSQL)
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
                    try connection.execute(voiceCorrectionSQL)
                },
                DatabaseMigration(id: 8, name: "voice_correction_scope_specific_unique_index") { connection in
                    try connection.execute(voiceCorrectionUniqueIndexSQL)
                },
                DatabaseMigration(id: 9, name: "voice_correction_targets") { connection in
                    try connection.execute(voiceCorrectionTargetsSQL)
                    try connection.addColumnIfNeeded(
                        table: "voice_correction_rules",
                        column: "target_id",
                        definition: "TEXT"
                    )
                    try connection.execute(voiceCorrectionTargetBackfillSQL)
                },
                DatabaseMigration(id: 10, name: "home_dashboard_query_indexes") { connection in
                    try connection.execute(homeDashboardQueryIndexesSQL)
                },
                DatabaseMigration(id: 11, name: "screenshot_records_table") { connection in
                    try connection.execute(screenshotRecordsSQL)
                }
            ],
            clock: clock
        )
    }

    static func ensureRequiredRuntimeTables(_ databaseQueue: DatabaseQueue) throws {
        try databaseQueue.write { connection in
            try connection.execute(screenshotRecordsSQL)
        }
    }

    static let voiceTasksSQL = """
    CREATE TABLE IF NOT EXISTS voice_tasks (
        id TEXT PRIMARY KEY,
        mode TEXT NOT NULL,
        stage TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'inProgress',
        target_app_bundle_id TEXT,
        target_app_name TEXT,
        target_app_pid INTEGER,
        target_window_id TEXT,
        target_window_title TEXT,
        audio_relative_path TEXT,
        raw_transcript TEXT,
        context_json TEXT,
        final_text TEXT,
        output_result TEXT,
        failure_json TEXT,
        asr_metadata_json TEXT,
        warnings_json TEXT NOT NULL DEFAULT '[]',
        trace_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_voice_tasks_status ON voice_tasks(status);
    CREATE INDEX IF NOT EXISTS idx_voice_tasks_created_at ON voice_tasks(created_at);
    CREATE INDEX IF NOT EXISTS idx_voice_tasks_mode_created_at
    ON voice_tasks(mode, created_at DESC);
    """

    static let homeDashboardQueryIndexesSQL = """
    CREATE INDEX IF NOT EXISTS idx_dictation_history_deleted_created_at
    ON dictation_history(deleted_at, created_at DESC);

    CREATE INDEX IF NOT EXISTS idx_voice_tasks_mode_created_at
    ON voice_tasks(mode, created_at DESC);
    """

    static let screenshotRecordsSQL = """
    CREATE TABLE IF NOT EXISTS screenshot_records (
        id TEXT PRIMARY KEY,
        ocr_text TEXT NOT NULL DEFAULT '',
        translated_text TEXT,
        summary_text TEXT,
        image_path TEXT,
        char_count INTEGER NOT NULL DEFAULT 0,
        is_favorited INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_screenshot_records_created_at
    ON screenshot_records(created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_screenshot_records_deleted_created
    ON screenshot_records(deleted_at, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_screenshot_records_favorited
    ON screenshot_records(is_favorited, deleted_at);
    """

    static let voiceCorrectionSQL = """
    CREATE TABLE IF NOT EXISTS voice_correction_rules (
        id TEXT PRIMARY KEY,
        original TEXT NOT NULL,
        replacement TEXT NOT NULL,
        match_policy TEXT NOT NULL,
        scope_type TEXT NOT NULL,
        scope_value TEXT,
        allowed_modes_json TEXT NOT NULL,
        lifecycle TEXT NOT NULL,
        source TEXT NOT NULL,
        case_sensitive INTEGER NOT NULL DEFAULT 0,
        confidence REAL NOT NULL,
        observed_count INTEGER NOT NULL DEFAULT 0,
        applied_count INTEGER NOT NULL DEFAULT 0,
        reverted_count INTEGER NOT NULL DEFAULT 0,
        provider_id TEXT,
        model_id TEXT,
        language TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_applied_at TEXT
    );
    \(voiceCorrectionUniqueIndexSQL)
    CREATE INDEX IF NOT EXISTS idx_voice_correction_rules_lifecycle
    ON voice_correction_rules(lifecycle, enabled);

    CREATE TABLE IF NOT EXISTS voice_correction_events (
        id TEXT PRIMARY KEY,
        rule_id TEXT,
        original TEXT NOT NULL,
        replacement TEXT NOT NULL,
        range_location INTEGER NOT NULL,
        range_length INTEGER NOT NULL,
        scope_type TEXT NOT NULL,
        scope_value TEXT,
        source TEXT NOT NULL,
        event_type TEXT NOT NULL,
        created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_voice_correction_events_created_at
    ON voice_correction_events(created_at DESC);

    CREATE TABLE IF NOT EXISTS voice_correction_learning_suppression (
        id TEXT PRIMARY KEY,
        original TEXT NOT NULL,
        replacement TEXT NOT NULL,
        bundle_identifier TEXT,
        suppressed_until TEXT NOT NULL,
        created_at TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_voice_correction_suppression_pair
    ON voice_correction_learning_suppression(
        original COLLATE NOCASE,
        replacement COLLATE NOCASE,
        IFNULL(bundle_identifier, '')
    );
    """

    static let voiceCorrectionUniqueIndexSQL = """
    DROP INDEX IF EXISTS idx_voice_correction_active_scope_original;
    CREATE UNIQUE INDEX IF NOT EXISTS idx_voice_correction_active_scope_original
    ON voice_correction_rules(
        scope_type,
        IFNULL(scope_value, ''),
        original COLLATE NOCASE,
        IFNULL(provider_id, ''),
        IFNULL(model_id, ''),
        IFNULL(language, '')
    )
    WHERE lifecycle = 'active';
    """

    static let voiceCorrectionTargetsSQL = """
    CREATE TABLE IF NOT EXISTS voice_correction_targets (
        id TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        normalized_text TEXT NOT NULL,
        scope_type TEXT NOT NULL,
        scope_value TEXT,
        lifecycle TEXT NOT NULL,
        source TEXT NOT NULL,
        observed_count INTEGER NOT NULL DEFAULT 0,
        applied_count INTEGER NOT NULL DEFAULT 0,
        reverted_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_applied_at TEXT
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_voice_correction_targets_scope_text
    ON voice_correction_targets(
        scope_type,
        IFNULL(scope_value, ''),
        normalized_text COLLATE NOCASE
    );
    CREATE INDEX IF NOT EXISTS idx_voice_correction_targets_updated_at
    ON voice_correction_targets(updated_at DESC);
    """

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

    static let initialSchemaSQL = """
    CREATE TABLE IF NOT EXISTS dictation_history (
        id TEXT PRIMARY KEY,
        raw_text TEXT NOT NULL,
        final_text TEXT NOT NULL,
        language TEXT NOT NULL,
        asr_provider_id TEXT,
        llm_provider_id TEXT,
        style_id TEXT,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        char_count INTEGER NOT NULL DEFAULT 0,
        cpm REAL NOT NULL DEFAULT 0,
        target_app_bundle_id TEXT,
        target_app_name TEXT,
        processing_warnings_json TEXT,
        processing_trace_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_dictation_history_created_at
    ON dictation_history(created_at);

    CREATE INDEX IF NOT EXISTS idx_dictation_history_deleted_at
    ON dictation_history(deleted_at);

    CREATE INDEX IF NOT EXISTS idx_dictation_history_deleted_created_at
    ON dictation_history(deleted_at, created_at DESC);

    CREATE TABLE IF NOT EXISTS style_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        subtitle TEXT,
        mode TEXT NOT NULL DEFAULT 'conservative',
        prompt TEXT NOT NULL,
        sample_input TEXT,
        sample_output TEXT,
        llm_provider_id TEXT,
        model TEXT,
        temperature REAL NOT NULL DEFAULT 0.2,
        enabled INTEGER NOT NULL DEFAULT 1,
        built_in INTEGER NOT NULL DEFAULT 0,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS asr_providers (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        provider_type TEXT NOT NULL,
        capabilities_json TEXT NOT NULL,
        tags_json TEXT NOT NULL,
        config_json TEXT NOT NULL DEFAULT '{}',
        enabled INTEGER NOT NULL DEFAULT 0,
        is_default INTEGER NOT NULL DEFAULT 0,
        last_health_status TEXT,
        last_health_message TEXT,
        last_checked_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS llm_providers (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        provider_type TEXT NOT NULL DEFAULT 'openaiCompatible',
        base_url TEXT NOT NULL,
        default_model TEXT NOT NULL,
        api_key_ref TEXT NOT NULL,
        temperature REAL NOT NULL DEFAULT 0.2,
        timeout_seconds REAL NOT NULL DEFAULT 30,
        enabled INTEGER NOT NULL DEFAULT 0,
        is_default INTEGER NOT NULL DEFAULT 0,
        last_health_status TEXT,
        last_health_message TEXT,
        last_latency_ms INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS transcription_jobs (
        id TEXT PRIMARY KEY,
        source_file_path TEXT NOT NULL,
        source_file_name TEXT NOT NULL,
        source_file_bookmark BLOB,
        status TEXT NOT NULL,
        progress REAL NOT NULL DEFAULT 0,
        raw_text TEXT,
        final_text TEXT,
        asr_provider_id TEXT,
        style_id TEXT,
        error_message TEXT,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT
    );

    CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body_markdown TEXT NOT NULL,
        source_type TEXT NOT NULL DEFAULT 'manual',
        source_id TEXT,
        tags_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_notes_updated_at
    ON notes(updated_at);

    CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    """
}
