CREATE TABLE screenshot_records (
    id TEXT NOT NULL PRIMARY KEY CHECK (
        length(trim(id)) > 0 AND length(id) <= 128
    ),
    media_type TEXT NOT NULL DEFAULT 'screenshot' CHECK (
        media_type = 'screenshot'
    ),
    original_image_path TEXT NOT NULL CHECK (
        original_image_path GLOB 'Screenshots/*'
        AND original_image_path NOT LIKE '%/../%'
        AND original_image_path NOT LIKE '%/./%'
        AND instr(original_image_path, ':') = 0
    ),
    rendered_image_path TEXT NOT NULL CHECK (
        rendered_image_path GLOB 'Screenshots/*'
        AND rendered_image_path NOT LIKE '%/../%'
        AND rendered_image_path NOT LIKE '%/./%'
        AND instr(rendered_image_path, ':') = 0
    ),
    thumbnail_path TEXT NOT NULL CHECK (
        thumbnail_path GLOB 'Screenshots/*'
        AND thumbnail_path NOT LIKE '%/../%'
        AND thumbnail_path NOT LIKE '%/./%'
        AND instr(thumbnail_path, ':') = 0
    ),
    translated_image_path TEXT NULL CHECK (
        translated_image_path IS NULL OR (
            translated_image_path GLOB 'Screenshots/*'
            AND translated_image_path NOT LIKE '%/../%'
            AND translated_image_path NOT LIKE '%/./%'
            AND instr(translated_image_path, ':') = 0
        )
    ),
    width_px INTEGER NOT NULL CHECK (width_px > 0),
    height_px INTEGER NOT NULL CHECK (height_px > 0),
    file_size_bytes INTEGER NOT NULL CHECK (file_size_bytes >= 0),
    source_display_id TEXT NULL,
    source_window_title TEXT NULL,
    ocr_text TEXT NOT NULL DEFAULT '',
    refined_text TEXT NULL,
    translated_text TEXT NULL,
    summary_text TEXT NULL,
    searchable_text TEXT NOT NULL DEFAULT '',
    character_count INTEGER NOT NULL DEFAULT 0 CHECK (character_count >= 0),
    is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
    created_at_unix_ms INTEGER NOT NULL CHECK (created_at_unix_ms >= 0),
    updated_at_unix_ms INTEGER NOT NULL CHECK (
        updated_at_unix_ms >= created_at_unix_ms
    ),
    deleted_at_unix_ms INTEGER NULL CHECK (
        deleted_at_unix_ms IS NULL
        OR deleted_at_unix_ms >= created_at_unix_ms
    )
);

CREATE INDEX idx_screenshot_records_created
    ON screenshot_records(created_at_unix_ms DESC, id ASC)
    WHERE deleted_at_unix_ms IS NULL;

CREATE INDEX idx_screenshot_records_favorite
    ON screenshot_records(is_favorite, created_at_unix_ms DESC, id ASC)
    WHERE deleted_at_unix_ms IS NULL;

CREATE INDEX idx_screenshot_records_updated
    ON screenshot_records(updated_at_unix_ms DESC, id ASC);

CREATE INDEX idx_screenshot_records_searchable
    ON screenshot_records(searchable_text);
