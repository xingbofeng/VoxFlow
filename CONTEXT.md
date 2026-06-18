# VoxFlow Project Context

## Domain Language

- **VoxFlow / 随声写**: The menu-bar application and shipped `VoxFlow.app` bundle. `VoiceInput` remains only in compatibility paths and internal module identifiers.
- **Right Command session**: One press-hold-release interaction that owns a single transcription.
- **Partial result**: A non-final text update emitted by Apple Speech while recording.
- **Final result**: Apple's final transcription after `endAudio()`.
- **Bounded timeout**: The 15 second fallback after right Command release that accepts the latest partial result if no final result arrives.
- **Refinement**: Optional conservative correction through an OpenAI-compatible API.
- **Text processing pipeline**: The post-ASR path that applies conservative refinement and future glossary/style rules while preserving fallback to raw text.
- **PromptBuilder**: The pure builder that combines conservative correction rules, selected style guidance, and enabled glossary terms into an LLM system prompt.
- **App style rule**: A Settings-backed mapping from target app bundle/name to a style profile used during post-ASR refinement.
- **ASR Provider**: A descriptor and runtime entry for a speech recognition backend, including capabilities, privacy summary, availability, and fallback behavior.
- **Capability tag**: A user-facing and filterable ASR Provider label such as local, streaming, cloud, multilingual, or punctuation.
- **Injection**: Temporarily placing text on the pasteboard and posting Command-V to the focused application.
- **HUD**: The bottom-centered non-activating capsule shown during recording and refinement.
- **Workbench window**: The regular macOS application window shown in Dock, `Command+Tab`, and Force Quit while the menu-bar dictation controls remain available.
- **Notes recording flow**: The notes page flow that starts recording, streams transcription into the editor, finishes, and saves a note.
- **VoiceTask**: A persistent record tracking a voice operation across its entire lifecycle: recording, transcription, context collection, processing, and output. Created at recording start, persisted at each stage, so partial work survives crashes.
- **VoiceTask mode**: Either `dictation` (existing right-Command transcription with optional style correction) or `agentCompose` ("帮我说" - context-aware LLM generation from user dictation plus window context).
- **VoiceTask stage**: A step in the task lifecycle: `recording`, `transcribing`, `collectingContext`, `processing`, `outputting`. Stages advance monotonically; backwards transitions are rejected.
- **Agent Compose ("帮我说")**: A voice mode that reads the current window's context (Accessibility text, window title, optionally a screenshot fallback) and uses an LLM to generate text guided by the user's dictation intent. Output is copy-only: no keyboard injection or auto-send.
- **ContextSnapshot**: A structured object holding collected context for a single agent-compose request: trimmed text, source markers, window metadata. Screenshots are transient and never persisted.
- **Installed application**: A discovered macOS application with name, Bundle ID, icon reference, path, and system category, produced by scanning `/Applications`, `~/Applications`, and system directories.
- **Known application registry**: A built-in, versioned, static mapping from Bundle IDs to suggested style IDs. Registry hits skip LLM classification and are labeled "system preset."
- **Application style recommendation**: A temporary suggestion (from registry or LLM classification) with source and confidence. Remains preview-only until the user explicitly confirms, at which point it becomes an app style rule.
- **VoiceAction**: An enum (`dictation`, `agentCompose`) representing a bindable hotkey action. Each action has an independent trigger; conflicts between actions are blocked.
- **OutputResult**: A structured result from the output stage: `injected` (dictation success), `copied` (agent compose success), or various failure modes with recovery paths.
- **OutputService**: The service that selects between injection (dictation mode) and clipboard copy (agent compose mode), returning a structured OutputResult. Replaces ad-hoc injection logic.
- **HistoryRecoveryAction**: An enum (`copy`, `reinject`, `regenerate`, `retranscribe`, `delete`) representing a recovery operation available on a history/task detail. Available actions are computed from task mode, status, and data availability. Retries never silently overwrite the original transcription or result.

## Module Boundaries

| Module | Owns | Must not own |
| --- | --- | --- |
| `AppDelegate` | Menu construction, permissions prompts, hotkey entry, HUD callback wiring | Audio math, URL parsing, pasteboard serialization, dictation state machine |
| `AppPresentationPolicy` | App activation policy and main-window restore rules | Window layout or menu construction |
| `WindowPlacementPolicy` | Pure visible-screen centering and recovery rules for the workbench window | SwiftUI content or app lifecycle |
| `KeyMonitor` | CGEvent tap and right Command transitions | Recording lifecycle |
| `AudioRecorder` | AVAudioEngine and RMS extraction | Speech requests |
| `SpeechRecognizer` | Speech request/task and callbacks | Audio engine |
| `TranscriptionSession` | Final/partial/release/timeout completion semantics | AppKit or asynchronous timers |
| `DictationStateMachine` | Legal dictation state transitions | ASR, audio, UI, persistence |
| `DictationOrchestrator` | Recording lifecycle, ASR engine callbacks, timeout fallback, text pipeline, injection, history save | Menu construction, permission prompts, view layout |
| `TextProcessingPipeline` | Replacement stages, optional LLM refinement, prompt context collection, and fallback warnings | ASR, audio capture, text injection |
| `PromptBuilder` | Pure prompt assembly from conservative rules, default style, and enabled glossary terms | Repository access, network requests, history persistence |
| `AppStyleRuleStore` / `SettingsBackedStyleSelector` | Persisted app-to-style mappings and runtime style resolution for a dictation target | Prompt construction, LLM network requests, SwiftUI layout |
| `ASRProviderRegistry` | ASR provider descriptors, capability filtering, default provider selection, fallback chain, engine creation | Download UI, AppKit window ownership |
| `ASRProviderViewModel` | Dictation model page state, provider records, tag filtering, local model path/download/delete operations | ASR engine implementation details |
| `CloudASRProviderClient` | Basic cloud ASR connection/file transcription protocol shape | Concrete third-party API behavior |
| `SettingsViewModel` | SwiftUI settings state, persisted app settings, shortcut preferences, device/permission snapshots, data actions | Hotkey event capture, real permission requests |
| `FileTranscriptionViewModel` | File import validation, transcription job queue state, progress/cancel/retry, export, save-as-note | Concrete ASR provider internals, note editing UI |
| `FileTranscriptionWorking` | File-to-text worker contract for mock and real ASR implementations | Job persistence or SwiftUI state |
| `NotesViewModel` | Note CRUD, notes recording flow state, Markdown draft state, search, history/file-transcription import, tag normalization, Markdown export | File transcription queue execution, audio capture implementation |
| `NotesRecordingService` | AudioRecorder-to-ASR transcription bridge for notes recording | Note persistence or SwiftUI layout |
| `OverlayWindowController` | NSPanel visibility, sizing, animation | Recognition state |
| `WaveformModel` | Envelope and bar heights | Drawing |
| `TextInjector` | Input source switching, paste, clipboard restoration | Recognition or LLM calls |
| `LLMRefiner` | Configuration, endpoint normalization, API request/response | UI |
| `LanguageManager` | Supported locales and persisted selection | Speech task lifetime |
| `CredentialStore` / `KeychainCredentialStore` | API key persistence and migration target | Non-sensitive preferences, logging |
| `AppLogger` | OSLog output and sensitive-token redaction | Secrets, user content transformation |
| `ApplicationSupportPaths` | Legacy `VoiceInput` Application Support paths retained for database, exports, and model compatibility | File transfer, network downloads |
| `AppClock` | Testable wall-clock and sleep abstraction | Business state transitions by itself |
| `HistoryRepository` | Persisted dictation history records and search/delete queries | ASR lifecycle, text injection |
| `VoiceTaskCoordinator` | Unified entry point for dictation and agent-compose modes; wraps DictationOrchestrator; creates and advances VoiceTask records at each stage | Menu construction, view layout, audio engine |
| `OutputService` | Mode-aware output selection (inject vs. copy), structured OutputResult, clipboard fallback on injection failure | ASR lifecycle, prompt construction |
| `AgentPromptBuilder` | Pure prompt assembly for agent-compose mode: app metadata, style guidance, context snapshot, user dictation into a fixed agent prompt | Repository access, network requests, history persistence |
| `InstalledApplicationProvider` | Local macOS app directory scanning, Bundle ID extraction, icon reference, deduplication | LLM classification, style rule persistence |
| `KnownApplicationRegistry` | Static versioned Bundle ID to style ID mapping, registry lookup and hit/miss reporting | LLM requests, user rule management |
| `ApplicationStyleRecommendationService` | Merges registry hits and LLM classifications into preview-only recommendations; writes rules only on user confirmation | Direct rule persistence, prompt construction |
| `ContextPipeline` | Parallel context collection (Accessibility text, window metadata, optional visual fallback), deduplication, trimming, timeout enforcement | ASR lifecycle, text injection |

## Architecture Decisions

### ADR-001: Paste Instead Of Accessibility Value Mutation

Text is injected with the clipboard and Command-V because it works across more native, Electron, browser, and custom text controls than direct Accessibility value mutation.

### ADR-002: Switch CJK Input Sources Before Paste

CJK input methods can intercept or transform synthetic keyboard events. VoxFlow temporarily selects ABC/US for paste, then restores the exact prior input source.

### ADR-003: Final Result With Timeout Fallback

Apple Speech and local ASR final-result latency is not fixed. VoxFlow completes immediately on a final result and otherwise waits up to 15 seconds before accepting the latest partial result. If ASR errors after partial text has arrived, the latest partial is used instead of dropping the dictation.

### ADR-004: LLM Is Conservative And Optional

Refinement is off unless configured and enabled. API failure falls back to raw text. The prompt forbids rewriting and asks for byte-for-byte preservation when no obvious error exists.

### ADR-005: Host-Native SwiftPM Build

The default Make target builds for the current host architecture. A signed bundle is always produced and verified; ad-hoc signing is the default for local development.

### ADR-006: AppDelegate Delegates Dictation Lifecycle

`AppDelegate` keeps menu-bar, permission, and hotkey entry responsibilities, but `DictationOrchestrator` owns the recording lifecycle after start. This keeps right Command behavior stable while allowing timeout, LLM fallback, history persistence, and future glossary/style processing to be tested without AppKit windows or real devices.

### ADR-007: ASR Providers Are Runtime Descriptors

ASR provider availability and labels are computed in `ASRProviderRegistry` from the current `ASRManager` state, then mirrored into SQLite for workbench summaries. This avoids duplicating Apple/Qwen selection logic while still giving the SwiftUI model page a repository-backed view of providers, health, tags, and default/fallback behavior.

### ADR-008: Independent VoiceTask Table

VoiceTask uses its own `voice_tasks` table rather than extending `dictation_history`. The two entities have different lifecycles (tasks are runtime state with stages; history is a completion record), and mixing them would cause nullable field pollution and complicate incomplete-task queries.

### ADR-009: Three-Layer Application Model

Application style routing separates facts (InstalledApplication from scan), recommendations (temporary suggestions from registry or LLM), and rules (user-confirmed AppStyleRule). This prevents rescanning from silently overwriting user choices and keeps trust levels explicit.

### ADR-010: Separate PromptBuilders for Correction and Generation

The existing PromptBuilder produces conservative correction prompts for dictation mode. A new AgentPromptBuilder produces fixed agent prompts for agent-compose mode. Combining both into one builder would create conflicting constraints ("only correct" vs. "generate from intent").

### ADR-011: Copy-Only Agent Compose Output

Agent compose output is copy-only (clipboard write). No Command-V injection, no Enter simulation, no app-specific send actions. This is a firm v1 boundary: automatic sending introduces reliability and safety risks that require per-app adapters and extensive testing.
