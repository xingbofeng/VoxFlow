# VoxFlow PRD

## Product Positioning

VoxFlow is a macOS voice input workbench for Chinese users, developers, and knowledge workers. It keeps the core interaction simple: hold the right Command key, speak, release, and insert text at the current cursor position.

## Goals

- Preserve the existing dictation loop: hotkey, recording, ASR, optional conservative LLM refinement, injection, clipboard restore, input source restore.
- Add a full workbench window with Home, Glossary, Styles, File Transcription, Notes, Dictation Models, Settings, and Help.
- Store local data in SQLite and API keys in Keychain.
- Keep all network features optional and explicit.
- Make failures recoverable: ASR and LLM failures must fall back without losing the current dictation.

## User Stories

- As a developer, I can dictate mixed Chinese-English technical text and keep terms accurate through glossary and replacement rules.
- As a knowledge worker, I can review recent dictation history, search it, copy it, delete it, and save useful entries as notes.
- As a privacy-conscious user, I can choose local/system/cloud providers and understand what data leaves the machine.
- As a writer, I can apply conservative styles without the model inventing content.
- As a power user, I can transcribe local audio or video files into text and save the result.

## Acceptance Criteria

- The app builds and launches as VoxFlow.
- The menu bar dictation loop still works without requiring the workbench window.
- Main workbench navigation contains every required page.
- SQLite migrations create the required local tables.
- API keys are stored only in Keychain and never in SQLite or UserDefaults.
- `swift test` and `make build` pass.

## Context-Aware Voice Workflows

### Change Scope

This change introduces three new capabilities on top of the existing dictation loop:

1. **Application style routing** — automatically select a style profile based on the active application.
2. **Reliable voice tasks** — persist every dictation session as a `VoiceTask` with independently recoverable stages.
3. **Agent compose ("帮我说")** — read the current window context together with user dictation, let the LLM generate text, and place the result on the clipboard (no automatic sending).

### Key Features

#### Smart Application Configuration

A one-time LLM-powered scan enumerates installed applications, groups them by style, and presents the result for user confirmation before anything is persisted. No background classification runs without explicit user approval.

#### Built-in Application Registry

High-frequency applications ship with pre-defined style mappings so they skip the LLM classification step entirely:

- WeChat → chat
- VS Code → coding
- (additional entries as determined during implementation)

#### VoiceTask Persistence

A `VoiceTask` row is created at the moment recording starts. Each processing stage (recording, ASR, LLM refinement, injection) is persisted independently so that a crash at any point can be recovered without losing prior work.

#### Agent Compose ("帮我说")

When triggered, the system reads the current window context (application, window title, selected text if available) and combines it with the user's dictation. The LLM generates output text which is placed **only on the clipboard** — no automatic sending, typing simulation, or injection occurs.

#### Dual Hotkey Actions

Separate key bindings are provided for standard dictation and "帮我说". The shortcut manager validates bindings at configuration time and rejects conflicting assignments.

#### Output Protection

Before pasting dictation results, the injector re-validates that the target window still matches the window that was active when recording started. If the target has changed, the result falls back to the clipboard instead of injecting into an unexpected context.

### Acceptance Goals

- Existing right-Command dictation behavior is fully preserved — no changes to the current hold-to-record, release-to-transcribe loop.
- Recording start latency remains under 100 ms.
- Context collection (window info, selected text) completes within a 500 ms target.
- SQLite migration from the current schema (migration ID 2 → 3) is lossless; no data is dropped or rewritten.
- All 253+ existing tests continue to pass without modification.
- `swift test` and `make build` pass.
- Agent compose mode never automatically sends, types, or injects generated text — clipboard only.

### Out of Scope

- Per-app send adapters (e.g., pressing Enter in WeChat after paste).
- Visual context persistence (screenshots or OCR of surrounding content).
- Automatic retry or reconnection of voice tasks on application startup.

