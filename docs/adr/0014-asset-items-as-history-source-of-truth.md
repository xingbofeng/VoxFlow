# Asset Items As History Source Of Truth

VoxFlow will make `Asset` the canonical history concept for reusable input context, covering dictation text, screenshot images, and clipboard records. OCR text remains derived copyable text on a screenshot Asset rather than a separate Asset. We will migrate existing dictation and screenshot history into an `asset_items` store rather than keeping a long-term aggregate view over `dictation_history`, `voice_tasks`, `screenshot_records`, and `clipboard_assets`, because the product now treats these records as one user-facing asset surface in Home and Palette.

## Considered Options

- Keep existing history tables and build an aggregate Asset view: rejected because it preserves older source-specific boundaries in the primary product surface and forces every action, filter, delete, and search path to branch by legacy source.
- Create `asset_items` as the source of truth and migrate existing records: accepted because this makes Home asset management and Palette recent assets operate on one model, even though it requires a breaking migration and careful compatibility shims for existing feature entry points.

## Consequences

Old source-specific tables may be migrated, deprecated, or removed once their remaining feature contracts are covered by `asset_items`. Existing user history data does not need to be preserved during this breaking migration. Feature code that still needs dictation-specific or screenshot-specific metadata should access it through Asset detail fields or explicit compatibility adapters rather than treating legacy tables as the user-facing history source.

The first Palette release will not expose the Ask AI `Tab` affordance because AI chat attachment is outside the phase-one action set. Clipboard recording is enabled by default and does not special-case copied secrets; user-copied pasteboard content is treated as user-owned asset input. VoxFlow internal pasteboard writes are still ignored to prevent duplicate/noisy Assets from injection, screenshot capture, fallback copy, or asset replay flows.
