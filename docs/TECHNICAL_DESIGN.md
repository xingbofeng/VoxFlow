# VoxFlow Technical Design

## Architecture

VoxFlow is split into AppKit runtime, SwiftUI workbench, domain services, data repositories, and infrastructure utilities.

- AppKit owns the menu bar app lifecycle, global hotkey event tap, HUD, paste injection, and window coordination.
- SwiftUI owns the main workbench shell and future settings/detail forms.
- Domain services will orchestrate dictation, text processing, history, glossary, styles, providers, file jobs, notes, metrics, permissions, and import/export.
- Data repositories hide SQLite details behind protocols.
- Infrastructure owns Keychain, logging, paths, clock, and network adapters.

## Current Implemented Foundation

- `DependencyContainer` and `AppEnvironment` assemble live and in-memory dependencies.
- `WindowCoordinator` opens the workbench and existing settings window.
- `ApplicationSupportPaths` centralizes `voiceinput.sqlite`, `Exports`, and `Models`.
- `CredentialStore` and `KeychainCredentialStore` store API keys.
- `AppLogger` redacts sensitive tokens before OSLog.
- `SQLiteConnection`, `DatabaseQueue`, `DatabaseMigrator`, and `AppDatabase` provide database access and migration.
- SQLite repositories exist for history, glossary, replacement rules, styles, ASR providers, LLM providers, transcription jobs, notes, and settings.

## Data Storage

Local data lives in:

```text
~/Library/Application Support/VoiceInput/voiceinput.sqlite
~/Library/Application Support/VoiceInput/Exports/
~/Library/Application Support/VoiceInput/Models/
```

The legacy directory name remains a compatibility boundary for existing installations.

The initial migration creates:

- `schema_migrations`
- `dictation_history`
- `glossary_terms`
- `replacement_rules`
- `style_profiles`
- `asr_providers`
- `llm_providers`
- `transcription_jobs`
- `notes`
- `app_settings`

`llm_providers` stores `api_key_ref` only. Real secrets live in Keychain.

## Failure Handling

- LLM refinement failure falls back to the raw recognized text.
- Qwen3-ASR unavailable state falls back to Apple Speech selection rules.
- Database initialization failure currently falls back to an in-memory container so the menu bar app can continue launching; future work should surface a recoverable error in the workbench.
