# VoxFlow Privacy

## Local Data

VoxFlow stores local workbench data in SQLite under:

```text
~/Library/Application Support/VoiceInput/voiceinput.sqlite
```

The legacy directory name is intentionally preserved so VoxFlow upgrades do not orphan existing user data.

This includes dictation history, glossary terms, replacement rules, style profiles, provider metadata, transcription jobs, notes, voice tasks, and non-sensitive settings.

## Secrets

API keys are stored in macOS Keychain through `KeychainCredentialStore`.

VoxFlow must not store API keys in:

- UserDefaults
- SQLite
- Logs
- Test snapshots
- Export archives

Older plaintext LLM keys written to UserDefaults are migrated to Keychain and removed.

## Network Use

Network behavior is opt-in:

- LLM refinement is disabled by default.
- LLM requests send recognized text only when the user enables refinement or a style that requires it.
- Local/system ASR can be used without uploading audio to an LLM provider.
- Cloud ASR providers must clearly disclose that audio may leave the machine before they are enabled.
- Agent compose ("帮我说") sends user dictation and collected context to the configured LLM provider when invoked.

## Context Collection

Agent compose collects context from the current window to improve generation quality:

- **Window metadata**: Application name, window title, and bundle identifier.
- **Accessibility text**: Visible text, selected text, and input area content from the focused UI element.
- **Visual fallback**: A transient screenshot of the current window, used only when accessibility text is insufficient (< 50 characters). This screenshot is never saved to disk or uploaded — it exists only for the duration of a single task.

### Security safeguards:

- Secure text fields (password fields) are detected and blocked — no context is collected from them.
- The context pipeline never auto-scrolls windows or modifies the UI.
- Screenshots are transient and never persisted in the database, logs, or uploads.
- Context collection runs on a background queue with a 500ms timeout.
- All collected context is tagged with its source for transparency.

## Permissions

VoxFlow uses the following macOS permissions:

- **Microphone**: Required for all voice recording.
- **Speech Recognition**: Required for Apple Speech ASR engine.
- **Accessibility**: Required for text injection (Command-V) and context collection.
- **Screen Recording**: Required for visual context fallback screenshots. Only requested when agent compose first needs visual context.

## Logging

`AppLogger` redacts the following before sending text to OSLog:

- Bearer tokens and API key-shaped values
- Context text content (visible text, selected text, input area text)
- Screenshot references and image data paths
- User home directory paths

## Manual Controls

Future settings must include:

- Clear history.
- Clear cache/model downloads.
- Export local data without secrets.
- Import local data without overwriting Keychain secrets unless explicitly configured.
