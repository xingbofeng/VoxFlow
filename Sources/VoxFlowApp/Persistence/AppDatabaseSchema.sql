-- VoxFlow SQLite schema snapshot (2026-06-23)

CREATE TABLE IF NOT EXISTS schema_migrations (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TEXT NOT NULL
);

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
    deleted_at TEXT,
    -- 多媒体扩展列：旧截图行通过默认值自动归为 screenshot 类型。
    media_type TEXT NOT NULL DEFAULT 'screenshot',
    video_path TEXT,
    thumbnail_path TEXT,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    file_size_bytes INTEGER NOT NULL DEFAULT 0,
    audio_mode TEXT NOT NULL DEFAULT 'none'
);

CREATE INDEX IF NOT EXISTS idx_screenshot_records_created_at
ON screenshot_records(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_screenshot_records_deleted_created
ON screenshot_records(deleted_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_screenshot_records_favorited
ON screenshot_records(is_favorited, deleted_at);
CREATE INDEX IF NOT EXISTS idx_screenshot_records_media_type
ON screenshot_records(media_type, deleted_at);

CREATE TABLE IF NOT EXISTS asset_items (
    id TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    content_type TEXT NOT NULL,
    title TEXT NOT NULL,
    preview_text TEXT,
    text TEXT,
    raw_text TEXT,
    image_path TEXT,
    file_path TEXT,
    url TEXT,
    color_value TEXT,
    source_app_name TEXT,
    source_app_bundle_id TEXT,
    content_hash TEXT NOT NULL,
    capture_reason TEXT NOT NULL,
    metadata_json TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_asset_items_deleted_created_at
ON asset_items(deleted_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_asset_items_source_deleted_created_at
ON asset_items(source, deleted_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_asset_items_content_hash
ON asset_items(content_hash);

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
    last_applied_at TEXT,
    target_id TEXT
);

DROP INDEX IF EXISTS idx_voice_correction_active_scope_original;
CREATE UNIQUE INDEX IF NOT EXISTS idx_voice_correction_active_scope_original
ON voice_correction_rules(
    scope_type,
    IFNULL(scope_value, ''),
    original COLLATE NOCASE,
    IFNULL(provider_id, ''),
    IFNULL(model_id, ''),
    IFNULL(language, '')
) WHERE lifecycle = 'active';

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
