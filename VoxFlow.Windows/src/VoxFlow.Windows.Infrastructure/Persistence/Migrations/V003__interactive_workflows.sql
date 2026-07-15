ALTER TABLE llm_providers RENAME TO llm_providers_v001;

CREATE TABLE llm_providers (
    provider_id TEXT NOT NULL PRIMARY KEY CHECK (length(trim(provider_id)) > 0),
    display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
    provider_type TEXT NOT NULL CHECK (provider_type = 'openaiCompatible'),
    base_url TEXT NULL CHECK (base_url IS NULL OR length(trim(base_url)) > 0),
    model TEXT NULL CHECK (model IS NULL OR length(trim(model)) > 0),
    api_key_ref TEXT NULL CHECK (api_key_ref IS NULL OR length(trim(api_key_ref)) > 0),
    temperature REAL NOT NULL DEFAULT 0.2 CHECK (
        temperature >= 0 AND temperature <= 2
    ),
    timeout_seconds INTEGER NOT NULL DEFAULT 300 CHECK (
        timeout_seconds >= 1 AND timeout_seconds <= 600
    ),
    enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
    is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
    health_status TEXT NOT NULL DEFAULT 'unknown' CHECK (
        health_status IN ('unknown', 'testing', 'ok', 'error')
    ),
    health_message TEXT NULL,
    health_latency_ms INTEGER NULL CHECK (
        health_latency_ms IS NULL OR health_latency_ms >= 0
    ),
    health_checked_at_unix_ms INTEGER NULL CHECK (
        health_checked_at_unix_ms IS NULL OR health_checked_at_unix_ms >= 0
    ),
    agent_capability_status TEXT NOT NULL DEFAULT 'unknown' CHECK (
        agent_capability_status IN ('unknown', 'supported', 'unsupported', 'error')
    ),
    agent_capability_message TEXT NULL,
    agent_capability_checked_at_unix_ms INTEGER NULL CHECK (
        agent_capability_checked_at_unix_ms IS NULL OR agent_capability_checked_at_unix_ms >= 0
    ),
    created_at_unix_ms INTEGER NOT NULL CHECK (created_at_unix_ms >= 0),
    updated_at_unix_ms INTEGER NOT NULL CHECK (
        updated_at_unix_ms >= created_at_unix_ms
    )
);

INSERT INTO llm_providers (
    provider_id,
    display_name,
    provider_type,
    base_url,
    model,
    api_key_ref,
    temperature,
    timeout_seconds,
    enabled,
    is_default,
    health_status,
    agent_capability_status,
    created_at_unix_ms,
    updated_at_unix_ms
)
SELECT
    provider_id,
    CASE lower(provider_id)
        WHEN 'openai' THEN 'OpenAI'
        ELSE provider_id
    END,
    'openaiCompatible',
    base_url,
    model,
    CASE lower(provider_id)
        WHEN 'openai' THEN 'llm/openai/api_key'
        ELSE NULL
    END,
    0.2,
    300,
    enabled,
    CASE WHEN lower(provider_id) = 'openai' AND enabled = 1 THEN 1 ELSE 0 END,
    'unknown',
    'unknown',
    updated_at_unix_ms,
    updated_at_unix_ms
FROM llm_providers_v001;

DROP TABLE llm_providers_v001;

CREATE UNIQUE INDEX ux_llm_providers_single_default
    ON llm_providers(is_default)
    WHERE is_default = 1;

CREATE INDEX idx_llm_providers_enabled_default
    ON llm_providers(enabled DESC, is_default DESC, updated_at_unix_ms DESC, provider_id ASC);

CREATE TABLE workflow_tasks (
    id TEXT NOT NULL PRIMARY KEY CHECK (length(trim(id)) > 0),
    kind TEXT NOT NULL CHECK (
        kind IN ('selectionTranslation', 'selectionSummary', 'agentCompose')
    ),
    stage TEXT NOT NULL CHECK (
        stage IN (
            'capturingSelection',
            'recording',
            'transcribing',
            'collectingContext',
            'processing',
            'waitingForUser',
            'operating',
            'outputting',
            'completed'
        )
    ),
    status TEXT NOT NULL CHECK (
        status IN (
            'pending',
            'running',
            'partiallyCompleted',
            'completed',
            'failed',
            'cancelled',
            'interrupted'
        )
    ),
    generation TEXT NOT NULL CHECK (length(trim(generation)) > 0),
    raw_text TEXT NULL,
    partial_text TEXT NULL,
    final_text TEXT NULL,
    provider_id TEXT NULL,
    model TEXT NULL,
    target_json TEXT NULL CHECK (target_json IS NULL OR json_valid(target_json)),
    context_json TEXT NULL CHECK (context_json IS NULL OR json_valid(context_json)),
    trace_json TEXT NULL CHECK (trace_json IS NULL OR json_valid(trace_json)),
    output_json TEXT NULL CHECK (output_json IS NULL OR json_valid(output_json)),
    failure_json TEXT NULL CHECK (failure_json IS NULL OR json_valid(failure_json)),
    warnings_json TEXT NULL CHECK (warnings_json IS NULL OR json_valid(warnings_json)),
    created_at_unix_ms INTEGER NOT NULL CHECK (created_at_unix_ms >= 0),
    updated_at_unix_ms INTEGER NOT NULL CHECK (
        updated_at_unix_ms >= created_at_unix_ms
    ),
    completed_at_unix_ms INTEGER NULL CHECK (
        completed_at_unix_ms IS NULL OR completed_at_unix_ms >= created_at_unix_ms
    )
);

CREATE INDEX idx_workflow_tasks_created_at
    ON workflow_tasks(created_at_unix_ms DESC, id ASC);

CREATE INDEX idx_workflow_tasks_kind_created_at
    ON workflow_tasks(kind, created_at_unix_ms DESC, id ASC);

CREATE INDEX idx_workflow_tasks_status_updated_at
    ON workflow_tasks(status, updated_at_unix_ms ASC, id ASC);
