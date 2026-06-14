import Foundation

enum AppDatabase {
    static func migrator(clock: any AppClock = SystemClock()) -> DatabaseMigrator {
        DatabaseMigrator(
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
                }
            ],
            clock: clock
        )
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
        warnings_json TEXT NOT NULL DEFAULT '[]',
        trace_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_voice_tasks_status ON voice_tasks(status);
    CREATE INDEX IF NOT EXISTS idx_voice_tasks_created_at ON voice_tasks(created_at);
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

    CREATE TABLE IF NOT EXISTS glossary_terms (
        id TEXT PRIMARY KEY,
        term TEXT NOT NULL,
        aliases_json TEXT NOT NULL DEFAULT '[]',
        category TEXT NOT NULL DEFAULT 'general',
        enabled INTEGER NOT NULL DEFAULT 1,
        priority INTEGER NOT NULL DEFAULT 100,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

    CREATE UNIQUE INDEX IF NOT EXISTS idx_glossary_terms_unique
    ON glossary_terms(lower(term), category);

    CREATE TABLE IF NOT EXISTS replacement_rules (
        id TEXT PRIMARY KEY,
        source TEXT NOT NULL,
        target TEXT NOT NULL,
        match_mode TEXT NOT NULL DEFAULT 'contains',
        apply_stage TEXT NOT NULL DEFAULT 'beforeLLM',
        category TEXT NOT NULL DEFAULT 'general',
        enabled INTEGER NOT NULL DEFAULT 1,
        priority INTEGER NOT NULL DEFAULT 100,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

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
        timeout_seconds REAL NOT NULL DEFAULT 8,
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
