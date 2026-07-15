CREATE TABLE schema_migrations (
    version INTEGER NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at_unix_ms INTEGER NOT NULL
);

CREATE TABLE settings (
    key TEXT NOT NULL PRIMARY KEY,
    json_value TEXT NOT NULL CHECK (json_valid(json_value)),
    updated_at_unix_ms INTEGER NOT NULL CHECK (updated_at_unix_ms >= 0)
);

CREATE TABLE asr_providers (
    provider_id TEXT NOT NULL PRIMARY KEY,
    selected_model_id TEXT NULL,
    enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
    config_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(config_json)),
    updated_at_unix_ms INTEGER NOT NULL CHECK (updated_at_unix_ms >= 0)
);

CREATE TABLE llm_providers (
    provider_id TEXT NOT NULL PRIMARY KEY,
    base_url TEXT NULL,
    model TEXT NULL,
    enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
    updated_at_unix_ms INTEGER NOT NULL CHECK (updated_at_unix_ms >= 0)
);

CREATE TABLE credentials (
    credential_id TEXT NOT NULL PRIMARY KEY,
    owner_kind TEXT NOT NULL,
    owner_id TEXT NOT NULL,
    field_name TEXT NOT NULL,
    scope TEXT NOT NULL CHECK (scope = 'CurrentUser'),
    protection_version INTEGER NOT NULL CHECK (protection_version > 0),
    ciphertext BLOB NOT NULL CHECK (length(ciphertext) > 0),
    updated_at_unix_ms INTEGER NOT NULL CHECK (updated_at_unix_ms >= 0)
);

CREATE TABLE models (
    model_id TEXT NOT NULL PRIMARY KEY,
    version TEXT NOT NULL,
    state TEXT NOT NULL,
    bytes INTEGER NOT NULL DEFAULT 0 CHECK (bytes >= 0),
    total_bytes INTEGER NOT NULL DEFAULT 0 CHECK (total_bytes >= bytes),
    install_path TEXT NULL,
    error_code TEXT NULL,
    updated_at_unix_ms INTEGER NOT NULL CHECK (updated_at_unix_ms >= 0)
);

CREATE TABLE dictation_history (
    id TEXT NOT NULL PRIMARY KEY,
    source TEXT NOT NULL,
    raw_text TEXT NOT NULL,
    final_text TEXT NOT NULL,
    metadata_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(metadata_json)),
    created_at_unix_ms INTEGER NOT NULL CHECK (created_at_unix_ms >= 0)
);

CREATE TABLE ui_state (
    key TEXT NOT NULL PRIMARY KEY,
    json_value TEXT NOT NULL CHECK (json_valid(json_value)),
    updated_at_unix_ms INTEGER NOT NULL CHECK (updated_at_unix_ms >= 0)
);

CREATE INDEX idx_credentials_owner
    ON credentials(owner_kind, owner_id);

CREATE INDEX idx_dictation_history_created_at
    ON dictation_history(created_at_unix_ms DESC);

CREATE INDEX idx_dictation_history_source_created_at
    ON dictation_history(source, created_at_unix_ms DESC);

CREATE INDEX idx_models_state
    ON models(state);

CREATE UNIQUE INDEX ux_credentials_owner_field
    ON credentials(owner_kind, owner_id, field_name);
