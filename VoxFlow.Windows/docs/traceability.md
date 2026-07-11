# Windows V1 requirement traceability

This matrix maps every added OpenSpec requirement to its implementation tasks
and executable evidence. Test paths are contracts: later implementation tasks
must create them without weakening the mapped behavior.

## windows-cloud-asr

| ID | Requirement | OpenSpec tasks | Automated evidence |
| --- | --- | --- | --- |
| WCA-01 | Shared streaming ASR session contract | 3.5, 7.5–7.8, 12.3–14.4 | `VoxFlow.Windows.Providers.Cloud.Tests/StreamingAsrContractTests` |
| WCA-02 | Tencent Cloud realtime ASR | 12.1–12.5 | `VoxFlow.Windows.Providers.Cloud.Tests/TencentAsrSessionTests` |
| WCA-03 | Alibaba DashScope realtime ASR | 13.1–13.5 | `VoxFlow.Windows.Providers.Cloud.Tests/DashScopeAsrSessionTests` |
| WCA-04 | Volcengine realtime ASR | 14.1–14.5 | `VoxFlow.Windows.Providers.Cloud.Tests/VolcengineAsrSessionTests` |
| WCA-05 | Cloud credential UI, tests, and privacy | 4.3–4.4, 12.1–14.2, 16.1–16.4 | `VoxFlow.Windows.App.Tests/CloudProviderSettingsTests`; `CredentialVaultTests` |
| WCA-06 | Cloud language, timeout, and cancellation | 12.3, 13.3, 14.3, 16.5–16.6 | `VoxFlow.Windows.Providers.Cloud.Tests/CloudSessionLifetimeTests` |

## windows-desktop-shell

| ID | Requirement | OpenSpec tasks | Automated evidence |
| --- | --- | --- | --- |
| WDS-01 | Windows V1 shell and approved scope | 5.3–5.4, 16.1–16.2 | `VoxFlow.Windows.App.Tests/ShellScopeTests` |
| WDS-02 | Visual tokens and main-window layout | 5.1–5.4, 6.6 | `VoxFlow.Windows.App.Tests/ThemeTokenTests`; `MainWindowLayoutTests` |
| WDS-03 | Dictation-only home history and detail | 5.5–5.6 | `VoxFlow.Windows.App.Tests/HomeViewModelTests` |
| WDS-04 | In-app theme, DPI, and monitor recovery | 5.1–5.2, 5.7, 6.3 | `VoxFlow.Windows.App.Tests/DisplayPlacementTests`; `ThemeManagerTests` |
| WDS-05 | Non-intrusive HUD visuals and states | 6.1–6.3, 6.6 | `VoxFlow.Windows.App.Tests/HudPresentationTests`; `HudVisualRegressionTests` |
| WDS-06 | Tray menu and synchronized state | 6.4–6.5, 16.3–16.4 | `VoxFlow.Windows.App.Tests/TrayMenuStateTests` |

## windows-dictation-runtime

| ID | Requirement | OpenSpec tasks | Automated evidence |
| --- | --- | --- | --- |
| WDR-01 | Global right-Control dictation shortcut | 7.1–7.4 | `VoxFlow.Windows.Platform.Tests/HotkeyRouterTests` |
| WDR-02 | Voice settings and input-device management | 7.3–7.6, 16.1–16.2 | `VoxFlow.Windows.App.Tests/VoiceSettingsTests`; `AudioDeviceTests` |
| WDR-03 | Unified PCM contract and bounded stream | 7.5–7.6 | `VoxFlow.Windows.Platform.Tests/AudioPipelineTests` |
| WDR-04 | Dictation state machine and stale-callback isolation | 3.3–3.5, 7.7–7.8 | `VoxFlow.Windows.Application.Tests/DictationOrchestratorTests` |
| WDR-05 | Local dictation-history retention | 4.5, 5.5–5.6 | `VoxFlow.Windows.Infrastructure.Tests/HistoryRepositoryTests` |

## windows-local-qwen-asr

| ID | Requirement | OpenSpec tasks | Automated evidence |
| --- | --- | --- | --- |
| WQA-01 | In-process Qwen-only native scope | 9.1–9.4, 10.1–10.2 | `VoxFlow.Windows.Providers.Qwen.Tests/NativeDependencyContractTests` |
| WQA-02 | Stable native ABI and managed resource safety | 10.1–10.4 | `VoxFlow.Windows.Providers.Qwen.Tests/QwenNativeInteropTests`; native C tests |
| WQA-03 | Qwen partial and authoritative-final semantics | 10.5–10.6 | `VoxFlow.Windows.Providers.Qwen.Tests/QwenSessionEventTests` |
| WQA-04 | Qwen recovery and crash boundaries | 10.5–10.6 | `VoxFlow.Windows.Providers.Qwen.Tests/QwenSupervisorTests` |

## windows-model-lifecycle

| ID | Requirement | OpenSpec tasks | Automated evidence |
| --- | --- | --- | --- |
| WML-01 | Windows Qwen manifest and fixed storage | 9.4, 11.1–11.2 | `VoxFlow.Windows.Infrastructure.Tests/QwenManifestTests` |
| WML-02 | User-started resumable download | 11.1, 11.3–11.4 | `VoxFlow.Windows.Infrastructure.Tests/ResumableDownloaderTests` |
| WML-03 | Integrity, atomic install, and readiness gate | 11.5–11.8 | `VoxFlow.Windows.Infrastructure.Tests/ModelInstallerTests` |
| WML-04 | Download deduplication, deletion, and state consistency | 11.3–11.8, 16.3–16.4 | `VoxFlow.Windows.Application.Tests/ModelLifecycleProjectionTests` |
| WML-05 | Local-model observability and uninstall retention | 11.7–11.8, 17.1–17.2 | `VoxFlow.Windows.App.Tests/ModelCardTests`; installer contract tests |

## windows-openai-llm

| ID | Requirement | OpenSpec tasks | Automated evidence |
| --- | --- | --- | --- |
| WOL-01 | Fixed official OpenAI configuration | 15.1–15.2 | `VoxFlow.Windows.Providers.Cloud.Tests/OpenAiSettingsTests` |
| WOL-02 | Streaming conservative SSE refinement | 15.3–15.4 | `VoxFlow.Windows.Providers.Cloud.Tests/OpenAiSseClientTests` |
| WOL-03 | Conservative ASR fallback on LLM failure | 15.5–15.6 | `VoxFlow.Windows.Application.Tests/TextRefinementPipelineTests` |
| WOL-04 | TokenHub restricted to developer smoke | 15.1, 15.9, 17.7 | `VoxFlow.Windows.IntegrationTests/OpenAiCompatibilityLiveTests` (explicit only) |

## windows-quality-and-distribution

| ID | Requirement | OpenSpec tasks | Automated evidence |
| --- | --- | --- | --- |
| WQD-01 | Strict RED-GREEN-REFACTOR delivery gate | every test-first pair | TDD evidence in task log and targeted test commands |
| WQD-02 | Offline automated-test matrix | 1.4, 2.1–16.6, 17.8 | `dotnet test VoxFlow.Windows.sln` without live variables |
| WQD-03 | Real manual acceptance matrix | 12.5, 13.5, 14.5, 15.9, 17.5–17.7 | explicit live scripts and redacted acceptance report |
| WQD-04 | Windows 10 1809 and x64 distribution | 2.5, 17.1–17.5 | runtime probe, x64 publish checks, clean-VM report |
| WQD-05 | EXE uninstall, signing disclosure, and licenses | 1.2, 17.1–17.4 | installer and license contract tests |
| WQD-06 | Visual and accessibility regression | 5.1–6.6, 17.8 | WPF render baselines and automation-tree tests |
| WQD-07 | Pre-release security and privacy scan | 1.1–1.4, 4.6–4.7, 17.3–17.4 | `check-no-secrets.test.sh`; diagnostics redaction tests |

## windows-settings-and-state

| ID | Requirement | OpenSpec tasks | Automated evidence |
| --- | --- | --- | --- |
| WSS-01 | V1 settings information architecture | 5.3–5.4, 16.1–16.2 | `VoxFlow.Windows.App.Tests/SettingsRouteTests` |
| WSS-02 | Five-card Voice configuration | 7.3–7.4, 16.1–16.2 | `VoxFlow.Windows.App.Tests/VoiceSettingsTests` |
| WSS-03 | ASR and LLM settings-card state | 11.7–15.8, 16.3–16.4 | `VoxFlow.Windows.App.Tests/ProviderCardStateTests` |
| WSS-04 | Protected credentials and sensitive-field display | 4.3–4.4, 12.1–15.2 | `VoxFlow.Windows.Infrastructure.Tests/CredentialVaultTests` |
| WSS-05 | General, Text, privacy, and data behavior | 4.5–4.7, 15.7–15.8, 16.1–16.6 | `VoxFlow.Windows.App.Tests/GeneralAndTextSettingsTests` |

## windows-text-output

| ID | Requirement | OpenSpec tasks | Automated evidence |
| --- | --- | --- | --- |
| WTO-01 | Foreground-target identity and change policy | 8.1–8.2 | `VoxFlow.Windows.Platform.Tests/ForegroundTargetTests` |
| WTO-02 | Fast-paste clipboard transaction | 8.3–8.4 | `VoxFlow.Windows.Platform.Tests/FastPasteTests` |
| WTO-03 | Unicode simulated-input output | 8.5–8.6 | `VoxFlow.Windows.Platform.Tests/SimulatedInputTests` |
| WTO-04 | Administrator/UIPI boundary | 8.7–8.8, 16.5–16.6 | `VoxFlow.Windows.Application.Tests/OutputFailurePolicyTests` |

## Explicit V1 exclusions

| Excluded scope | Enforcement |
| --- | --- |
| Screenshot and OCR | No route, menu item, source filter, product capture API, or placeholder layout; shell tests assert unreachability. |
| ARM64 | Solution, CI, native bridge, publish, and installer are x64-only. |
| Automatic update | No updater service, feed, scheduled task, or UI entry. |
| MSIX | Distribution uses a per-user Inno Setup EXE only. |
| Server process | No local HTTP/WebSocket service, helper daemon, or remote VoxFlow backend. |
| Translation, TTS, Agent, notes, and tasks | No settings route, tray command, deep link, or runtime contract in Windows V1. |

Python, WSL, MLX, and CUDA are also excluded from the shipped runtime and the
qwen bridge build. Python may not be used to satisfy a product runtime path.
