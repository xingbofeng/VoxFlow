CREATE TABLE file_transcription_jobs (
    id TEXT NOT NULL PRIMARY KEY,
    source_path TEXT NOT NULL,
    display_name TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    language TEXT NOT NULL,
    status TEXT NOT NULL,
    duration_ms INTEGER NULL CHECK (duration_ms IS NULL OR duration_ms >= 0),
    progress REAL NOT NULL DEFAULT 0 CHECK (progress >= 0 AND progress <= 1),
    raw_text TEXT NULL,
    final_text TEXT NULL,
    error_code TEXT NULL,
    provider_mode TEXT NOT NULL DEFAULT 'segmentedPcm',
    segment_count INTEGER NOT NULL DEFAULT 0 CHECK (segment_count >= 0),
    segment_completed INTEGER NOT NULL DEFAULT 0 CHECK (
        segment_completed >= 0 AND segment_completed <= segment_count
    ),
    partial_failure_summary TEXT NULL,
    translation_status TEXT NOT NULL DEFAULT 'notRequested',
    translated_text TEXT NULL,
    translation_target_language TEXT NULL,
    translation_error_code TEXT NULL,
    translation_updated_at_unix_ms INTEGER NULL CHECK (
        translation_updated_at_unix_ms IS NULL OR translation_updated_at_unix_ms >= 0
    ),
    created_at_unix_ms INTEGER NOT NULL CHECK (created_at_unix_ms >= 0),
    updated_at_unix_ms INTEGER NOT NULL CHECK (updated_at_unix_ms >= 0),
    completed_at_unix_ms INTEGER NULL CHECK (
        completed_at_unix_ms IS NULL OR completed_at_unix_ms >= 0
    )
);

CREATE TABLE file_transcription_segments (
    job_id TEXT NOT NULL,
    segment_index INTEGER NOT NULL CHECK (segment_index >= 0),
    start_ms INTEGER NOT NULL CHECK (start_ms >= 0),
    end_ms INTEGER NOT NULL CHECK (end_ms >= start_ms),
    status TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    text TEXT NULL,
    retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    provider_mode TEXT NOT NULL,
    fallback_reason TEXT NOT NULL,
    error_code TEXT NULL,
    PRIMARY KEY (job_id, segment_index),
    FOREIGN KEY (job_id) REFERENCES file_transcription_jobs(id) ON DELETE CASCADE
);

CREATE INDEX idx_file_transcription_jobs_created_at
    ON file_transcription_jobs(created_at_unix_ms DESC, id ASC);

CREATE INDEX idx_file_transcription_jobs_status
    ON file_transcription_jobs(status, created_at_unix_ms ASC, id ASC);

CREATE INDEX idx_file_transcription_segments_job_index
    ON file_transcription_segments(job_id, segment_index ASC);

CREATE INDEX idx_file_transcription_segments_status
    ON file_transcription_segments(status, job_id, segment_index ASC);
