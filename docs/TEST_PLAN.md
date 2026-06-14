# VoxFlow Test Plan

## Automated Tests

Run:

```bash
swift test
```

Current automated coverage includes:

- Hotkey state transitions and right Command behavior.
- Transcription final/partial timeout behavior.
- Pasteboard snapshot and restore.
- Input source classification.
- LLM URL normalization, response parsing, Keychain migration, and fallback-friendly configuration.
- ASR manager selection and Qwen3 model availability gates.
- Audio preprocessing, RMS, and waveform model behavior.
- SQLite connection, queue, migrations, schema, and repositories.
- App environment and dependency container assembly.
- Workbench route coverage and repository-backed summary loading.
- Forbidden product-name repository guard.

## Optional Integration Tests

Live tests are skipped unless explicitly enabled:

```bash
VOICEINPUT_TEST_BASE_URL="https://api.example.com/v1" \
VOICEINPUT_TEST_API_KEY="..." \
VOICEINPUT_TEST_MODEL="..." \
swift test --filter LLMRefinerTests/testConfiguredOpenAICompatibleServiceRefinesMixedLanguageText
```

```bash
VOICEINPUT_TEST_QWEN3_LIVE=1 swift test --filter Qwen3LiveSmokeTests
```

## Build Verification

Run:

```bash
make build
```

Final release acceptance should run:

```bash
make clean && make build && swift test
```

## Manual Verification

- Launch the built app and confirm the menu bar icon appears.
- Open the workbench from the menu.
- Confirm the existing settings window still opens.
- Grant required permissions and perform a real right Command dictation.
- Confirm text is injected into the original target app.
- Confirm clipboard and input source restore after injection.
- Save an LLM API key and confirm it persists through Keychain after restart.

