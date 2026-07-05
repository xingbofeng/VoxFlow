# Privacy And Data

VoxFlow is local-first by default. The app stores working context on your Mac unless you explicitly configure a cloud ASR or LLM provider.

## Local Data

Stored locally:

- Dictation history
- Screenshot and screen recording records
- OCR text
- Clipboard assets
- Notes
- Personal correction rules and learned candidates
- Non-secret settings
- Local diagnostic files when enabled

Default data directory:

```text
~/Library/Application Support/VoxFlow/
```

Primary database:

```text
voxflow.sqlite
```

## Credentials

API keys and cloud credentials are stored in the local `credentials.json` file under the app data directory.

Keep this file private. It is not written to UserDefaults, SQLite, logs, test snapshots, or exported diagnostic archives.

## Cloud Calls

VoxFlow sends data externally only when a configured feature requires it:

- Apple Speech may process audio according to macOS system behavior.
- Local ASR models keep audio on-device.
- Cloud ASR sends recorded audio to the selected provider.
- LLM correction sends recognized text to the configured LLM provider.
- Ask AI sends the user's question and chat context to the configured LLM provider.
- Translation or summary can use Apple system translation, local models, or a configured LLM depending on settings.

## Clipboard And Screenshots

Clipboard assets are saved locally for launcher and Workbench review. Noise filters skip meaningless high-frequency changes.

Clipboard image OCR can be used as a one-off OCR entry. Screenshots captured with `⌘⇧A` are stored locally with OCR text so they can be searched and reviewed later.

## Startup Storage Failures

If persistent storage cannot be opened, VoxFlow no longer silently switches to temporary in-memory storage. The app asks before continuing in a session-only mode where new history, assets, and settings may be lost after restart.

## Diagnostics

Diagnostic traces are local by default. LLM trace diagnostics can contain prompt, request, or response details and should stay opt-in. Crash logs and diagnostic upload behavior are controlled by settings.

For the public privacy policy, see [PRIVACY.md](PRIVACY.md).
