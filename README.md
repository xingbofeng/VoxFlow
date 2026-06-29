<div align="center">
  <img src="docs/assets/voiceinput-logo.png" alt="VoxFlow logo" width="128">

  <h1>VoxFlow</h1>
  <p><strong>A macOS asset workbench for voice, screenshots, screen recordings, clipboard history, and coding-agent instructions.</strong></p>
  <p>Press <code>⌥Space</code> to open the launcher and recover recent voice, screenshot, screen recording, and clipboard assets. Dictation, captures, recordings, and copied content become searchable, copyable, reusable local history.</p>

  <p>
    <img src="https://img.shields.io/badge/macOS-15%2B-111827?style=flat-square&logo=apple&logoColor=white" alt="macOS 15+">
    <a href="https://github.com/xingbofeng/VoxFlow/releases/latest"><img src="https://img.shields.io/github/v/release/xingbofeng/VoxFlow?style=flat-square&label=release" alt="Latest release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-10B981?style=flat-square" alt="License: GPL-3.0-or-later"></a>
  </p>
  <p>
    🌐 <a href="https://xingbofeng.github.io/VoxFlow/">Website</a>
    &nbsp;·&nbsp;
    ⬇️ <a href="https://github.com/xingbofeng/VoxFlow/releases/latest">Download</a>
    &nbsp;·&nbsp;
    <a href="README.md">English</a>
    &nbsp;·&nbsp;
    <a href="README.zh-CN.md">中文</a>
    &nbsp;·&nbsp;
    <a href="README.zh-TW.md">繁體中文</a>
    &nbsp;·&nbsp;
    <a href="README.ja.md">日本語</a>
    &nbsp;·&nbsp;
    <a href="README.ko.md">한국어</a>
  </p>
  <p>
    <a href="docs/assets/voiceinput-demo-land.mp4"><img src="docs/assets/voiceinput-demo-land.gif" alt="Intro Video" width="100%"></a>
  </p>
</div>

## At A Glance

VoxFlow is an asset workbench and fast launcher for the app you are already using. It is not a voice assistant: it does not take over the window, submit messages, or move you into another input box. It turns voice, screenshots, screen recordings, clipboard items, and agent commands into searchable, previewable, reusable local assets that return to your current workspace.

| What You Want To Do | Trigger | Output | Boundary |
| --- | --- | --- | --- |
| Open the launcher | `⌥Space` | Raycast-style launcher | Recent Assets is selected by default; keyboard navigation first |
| Recover recent assets | Launcher -> Recent Assets | Second-level asset browser | Voice, screenshots, and clipboard share search and filters |
| Dictate text | Hold the shortcut, speak, release | Current cursor position | No focus stealing, no auto-submit |
| Manage clipboard assets | Copy text, images, files, links, or colors | Asset history | Noise filters still skip content that should not be saved |
| Fix misrecognized terms | Runs after ASR final output and optional LLM correction | Text before insertion | Local deterministic rules; learned candidates stay user-controlled |
| OCR a clipboard image | Copy an image, press `⌘⇧V` | Current cursor position | Image-only workflow; does not start normal dictation |
| Capture and process a screenshot or screen recording | Press `⌘⇧A`, select a region | OCR result panel | Translation, summary, and speech playback are optional |
| Run selection actions | Select text, press `⌘⇧F/J/K/L/P` | Action HUD or result panel | F opens the action card; J translates, K summarizes, L sends to Task Assistant, P sends to Ask AI |
| Ask AI from the launcher | Type a question in the launcher, choose "Ask AI" | Ask AI chat HUD | Reuses your configured LLM provider; multi-turn, streaming, Markdown |
| Search the web from the launcher | Type a keyword, choose a Quicklink | Default browser | Built-in Google, Bing, Perplexity, GitHub, StackOverflow, YouTube, Bilibili, X, Xiaohongshu, Taobao, JD |
| Open a URL from the launcher | Type a URL or bare domain | Default browser | Auto-detects http/https/bare domain/localhost/IP+port; first result is "Open URL" |
| Review screenshot and recording records | Open Workbench → Screenshot | Local screenshot and recording history and OCR text | Stored locally; records can be searched, favorited, copied, and deleted |
| Compose an AI prompt | Combine current-window context with spoken intent | Copyable prompt | Copy only, no injection, no auto-submit |
| Command local coding agents | Speak a task assistant name and task | Codex / Claude / CodeBuddy / terminal agent session | Dispatches only to registered sessions |

## Who It Is For

- You often talk to ChatGPT, Claude, Codex, Cursor, or other AI tools and need to describe intent, context, or revision requests quickly.
- You run Codex, Claude, CodeBuddy, or other terminal agents and want to dispatch spoken instructions to the right local session.
- You write code and frequently explain bugs, add notes, draft commit messages, or document investigation steps.
- You extract text from screenshots, web pages, error dialogs, or images, then translate or summarize it.
- You speak mixed Chinese and English, where technical terms and product names are easy to misrecognize.

## Reading Map

| If You Want To... | Start Here |
| --- | --- |
| Install and try it | [Quick Start](#quick-start) |
| Understand the launcher and assets | [Corrections, OCR, And Agent Workflows](#corrections-ocr-and-agent-workflows) |
| Understand speech models | [Dictation And Speech Models](#dictation-and-speech-models) |
| Understand OCR, translation, summary, and agents | [Corrections, OCR, And Agent Workflows](#corrections-ocr-and-agent-workflows) |
| Check where data goes | [Privacy](#privacy) |
| Understand the stack and open-source dependencies | [Tech Stack And Open-Source Dependencies](#tech-stack-and-open-source-dependencies) |
| Build from source | [Run From Source](#run-from-source) |

## Dictation And Speech Models

### Hold To Speak, Release To Insert

VoxFlow works like a keyboard layer. Hold your dictation shortcut, speak, and release. A small transcription overlay appears while you are speaking, then the final text is inserted into the current cursor position.

There is no need to switch apps or manually copy text back.

### Live Transcription

While you speak, VoxFlow shows recognized text in real time so you can stay oriented. It works for short commands, long explanations, Chinese, English, and mixed Chinese-English speech.

VoxFlow includes the system speech recognizer plus local and cloud ASR providers. Apple Speech works out of the box; Qwen3-ASR, Whisper, FunASR, SenseVoice, NVIDIA Nemotron, Parakeet, and Omnilingual cover local workflows, while Groq, Tencent Cloud, and Alibaba Cloud provide online recognition. The Models page labels local versus online, streaming capability, and language coverage explicitly.

### Supported Speech Models

VoxFlow does not force every local model into the same runtime. Each provider follows the route that best matches its upstream model format and latency target:

| Provider / Model | Current Runtime Route | Recommended Use |
| --- | --- | --- |
| Apple Speech | Apple Speech / SFSpeechRecognizer | Out-of-the-box dictation without downloading a model |
| Qwen3-ASR 0.6B | speech-swift Qwen3ASR MLX 4bit | Default local route using the unified speech-swift runtime |
| Qwen3-ASR 1.7B | speech-swift Qwen3ASR MLX 8bit | Higher-accuracy local route sharing the same speech-swift loading and session path as 0.6B |
| Whisper Turbo / Large V3 | WhisperKit `.mlmodelc` | High-quality full-recording transcription after capture ends |
| FunASR | Sherpa-ONNX | Local Chinese fallback path; not CoreML |
| SenseVoice | FluidAudio / CoreML | Local multilingual and short-utterance transcription |
| Paraformer | FluidAudio / CoreML int8 | Local Chinese transcription |
| NVIDIA Nemotron 0.6B | speech-swift NemotronStreamingASR / CoreML | Local multilingual streaming transcription |
| Parakeet Streaming | speech-swift ParakeetStreamingASR / CoreML | Low-latency local streaming dictation for English and European languages |
| Omnilingual ASR | speech-swift OmnilingualASR / CoreML | Broad-language offline transcription and experimental workflows |

Cloud providers send recorded audio to the selected service. Groq returns a final transcript after recording; Tencent Cloud and Alibaba Cloud support real-time WebSocket transcription.

| Cloud Provider | Status | Streaming | Default Model / API | Configuration |
| --- | --- | --- | --- | --- |
| Groq (Free) | Supported | No | `whisper-large-v3-turbo` audio transcription | API Key, model |
| Tencent Cloud | Supported | Yes | Realtime Speech Recognition WebSocket, `16k_zh` | AppID, SecretId, SecretKey |
| Alibaba Cloud | Supported | Yes | DashScope WebSocket, `fun-asr-realtime` | Bailian API Key |
| Volcengine Cloud | Planned | Planned | Doubao streaming ASR | To be determined |
| Mistral Voxtral, AssemblyAI, ElevenLabs Scribe | Not yet supported | To be determined | Reserved providers | None |

## Corrections, OCR, And Agent Workflows

### Personal Corrections And Optional LLM Correction

Speech recognition can struggle with technical terms such as Python, JSON, TypeScript, framework names, or product names. VoxFlow can run a conservative correction pass through your own OpenAI-compatible provider after dictation finishes.

The new **Personal Corrections** page runs deterministic local fixes after ASR final output and optional LLM correction. It can also learn candidate rules from edits you make after insertion. The LLM pass remains intentionally restrained: it fixes obvious recognition mistakes instead of rewriting your tone or polishing your content.

### Clipboard OCR, Screenshot Capture, Translation, And Summary

Copy a screenshot and press `⌘⇧V` to OCR the clipboard image and paste the recognized text into the current cursor position. Press `⌘⇧A` to select a screen region and open a result panel with **Original Image**, **OCR**, **Translation**, and **Summary** tabs.

This is useful for web pages, error dialogs, screenshots, design mockups, and chat history. OCR text can be copied, spoken, translated, or summarized, but it does not feed the permanent Personal Corrections learning loop.

### Agent Compose And AI Coding 助手 Command Center

**Agent Compose** combines visible window context, OCR text, and your spoken intent into a prompt you can paste into an AI tool. It only copies the result; it does not inject, submit, or press Enter for you.

**AI Coding 助手 Command Center** is for local coding-agent terminals. After you enable it, speak a task assistant name and instruction, and VoxFlow resolves the target agent, shows confirmation state, and dispatches the instruction to the matching Codex, Claude, CodeBuddy, or other registered terminal session.

### Workbench

VoxFlow also includes a full asset workbench:

| Page | What You Can Do |
| --- | --- |
| Home | Review asset history, today's additions, source breakdown, and reusable content; search, copy, or delete voice, screenshot, and clipboard assets |
| Personal Corrections | Manage deterministic correction rules, learned candidates, enablement, and recent events |
| Styles | Choose output styles such as original, formal, email, or coding notes |
| File Transcription | Import audio or video files, transcribe them, export txt/md/srt, or save as notes |
| Notes | Record voice notes, edit Markdown, search, and review recent notes |
| Screenshot | Browse captured screenshots and screen recordings with OCR text, favorites, search, and paging |
| AI Coding 助手 | Review registered agents, aliases, working directories, branches, and dispatch logs |
| Settings | Manage input devices, shortcuts, models, translation models, permissions, privacy, and data |
| Help | Find permission guidance, version information, and project links |

## Highlights

- **VoxFlow Palette launcher**: Press `⌥Space` for a Raycast-style launcher with Recent Assets selected by default, arrow-key navigation, Enter, and `⌘K` actions.
- **Asset history workbench**: Successful ASR text, screenshots, and clipboard text/images/files/links/colors share one asset system; Home shows asset counts, source breakdown, and reusable content.
- **Global dictation**: Works in any editable text field, not only inside VoxFlow.
- **Non-intrusive overlay**: Shows live text and voice activity without taking focus.
- **Multiple ASR providers**: Start with the built-in system recognizer; local Qwen3-ASR, Whisper, FunASR, SenseVoice, NVIDIA Nemotron, Parakeet, and Omnilingual providers are being unified under the same runtime model; providers without real-time streaming are marked as **Non-streaming** in Models.
- **Stable text insertion**: Temporarily switches input source before paste, then restores both input source and clipboard to reduce CJK input-method interference.
- **Input device selection**: Choose your microphone; long device names are handled gracefully.
- **Shortcut recording**: Record the key you want to use and configure short-press behavior.
- **Clipboard image OCR**: Copy a screenshot or image, press `⌘⇧V`, and VoxFlow recognizes the image text and pastes it into the current field.
- **Screenshot OCR**: Press `⌘⇧A`, select a screen region, then review the original image, OCR text, translation, and summary in a result panel.
- **Screenshot and recording library**: Captured screenshots and screen recordings are kept in the Screenshot page with OCR text, favorites, search, and one-click copy/delete actions.
- **Inline screenshot annotation**: Region capture supports pen/shape/text/mosaic/scroll tools, undo/redo, and quick translate/summary flow before final insert/output.
- **AI Coding 助手 Command Center**: Dispatch spoken instructions to Codex, Claude, CodeBuddy, or other registered local terminal agents.
- **Agent Compose**: Turn current-window OCR context plus spoken intent into a prompt; it only copies the result and never auto-submits.
- **OpenAI-compatible providers**: Add, test, edit, and delete providers; LLM API keys are stored in macOS Keychain.
- **Personal corrections and context hotwords**: Fix repeated misrecognitions with local rules, and use current-window OCR to extract temporary context terms.
- **History and notes**: Search, copy, edit, and reuse previous input, screenshots, and copied content.
- **File transcription**: Turn recordings, videos, or meeting audio into text.
- **Local-first data**: History, personal corrections, settings, notes, and jobs live locally; LLM correction is opt-in.

## Quick Start

### Download & Install

Download the latest version from [GitHub Releases](https://github.com/xingbofeng/VoxFlow/releases/latest):

1. Open `VoxFlow-1.10.1-macOS.dmg`
2. Drag `VoxFlow` into the `Applications` folder
3. On first launch, if macOS cannot verify the app, Control-click the app and choose **Open**

After installation, open Workbench -> Screenshot to verify your screenshot and recording records and OCR history at first use.

> To try the latest main-branch implementations of Personal Corrections, AI Coding 助手, or Screenshot OCR, run from source; these capabilities may be newer than the latest stable Release.

### Requirements

- macOS 15 Sequoia or later
- A Mac with a microphone

### First Permissions

VoxFlow needs a few macOS permissions:

| Permission | Why It Is Needed | Where |
| --- | --- | --- |
| Accessibility | Listen for the global shortcut and insert text into the current app | System Settings -> Privacy & Security -> Accessibility |
| Microphone | Record your voice | System Settings -> Privacy & Security -> Microphone |
| Speech Recognition | Use the system speech recognizer | System Settings -> Privacy & Security -> Speech Recognition |
| Screen Recording | OCR the current window for Agent Compose, screenshot OCR, and screen recording | System Settings -> Privacy & Security -> Screen Recording |

If you use a local Qwen3-ASR model, Speech Recognition permission is not required. Microphone permission is still required.

If the shortcut does not respond after granting permissions, quit and reopen VoxFlow.

### Default Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌥Space` | Open the VoxFlow Palette launcher |
| Dictation shortcut | Hold to speak, release to insert at the current cursor; configurable in Settings |
| `⌘⇧V` | OCR the clipboard image and paste recognized text |
| `⌘⇧A` | Capture a screen region and open the OCR result panel |
| `⌘⇧F` | Open the selection action HUD for the selected text (Translate / Summarize / Task Assistant / Ask AI) |
| `⌘⇧J` | Translate the selected text directly |
| `⌘⇧K` | Summarize the selected text directly |
| `⌘⇧L` | Send the selected text directly to Task Assistant |
| `⌘⇧P` | Send the selected text directly to the Ask AI chat HUD |

Selection-action shortcuts can be changed or cleared individually in **Settings → Selection Actions → Activation**.

## How To Use

### Dictation

1. Place your cursor in any text field.
2. Hold the dictation shortcut.
3. Speak. The overlay shows live recognition.
4. Release the shortcut. The final text is inserted at the cursor.

### Voice Notes

Open the workbench and go to **Notes**. Click the record button to start a quick note. VoxFlow transcribes as you speak, then lets you edit and review the note afterward.

### File Transcription

Open **File Transcription**, select an audio or video file, and let VoxFlow process it. Completed jobs can be copied, exported, or saved as notes.

### Clipboard Image OCR

Copy a screenshot or image, then press `⌘⇧V`. VoxFlow reads the image from your clipboard, runs OCR, and pastes the recognized text into the current cursor position.

If the clipboard does not contain an image, this shortcut does not start normal dictation; it is reserved for the clipboard image OCR workflow.

### Screenshot OCR, Translation, And Summary

Press `⌘⇧A`, then select a region of the screen. VoxFlow captures that region, runs OCR, and opens a result panel with **Original Image**, **OCR**, **Translation**, and **Summary** tabs. You can copy or speak the available text from the panel.

Translation can use Apple system translation, a configured LLM, or a local translation model. Summary can use a configured LLM or a local summarizer. If no translation or summary model is available, the OCR text still remains usable.

### Screenshot Record Library

Every screenshot captured with `⌘⇧A` is saved as a local screenshot record so you can review it later in **Workbench → Screenshot**.
You can search, filter by favorites, switch page size, copy recognized text, and delete entries.
Image previews are loaded from local files and are not synced or uploaded.

### Agent Compose

Agent Compose reads visible text and optional OCR context from the current window, combines it with your spoken intent, and produces a prompt for AI tools such as ChatGPT, Claude, Codex, or Cursor. It preserves the safety boundary: copy only, no injection, no auto-submit.

### AI Coding 助手 Command Center

Enable AI Coding 助手 Command Center in Settings, then use the existing voice shortcut to enter the command HUD. Say an agent name and task, such as “frontend, check the button state,” and VoxFlow resolves the target, asks for confirmation when needed, and dispatches the instruction to that terminal agent session.

### Launcher: Ask AI, Quicklinks, and Open URL

Press `⌥Space` to open the launcher. In addition to searching apps, commands, and assets, you can also:

- **Ask AI**: Type any question, select "Ask AI", and press Enter. The launcher closes and the right-side HUD enters Ask AI chat mode. It reuses your configured LLM provider and supports multi-turn conversation, streaming replies, and Markdown rendering. The session stays in memory, so reopening Ask AI lets you continue asking follow-ups. When no provider is configured, the HUD shows a configuration hint instead of sending a request.
- **Quicklinks**: Built-in sites include Google, Bing, Perplexity, GitHub, StackOverflow, YouTube, Bilibili, X, Xiaohongshu, Taobao, and JD. Typing a site name, Chinese name, or alias (such as `gh`, `tb`, or `b站`) prioritizes that site; pressing Enter opens the search results in your default browser.
- **Open URL**: When you type a full URL, a bare domain (such as `github.com/openai/codex`), `localhost:3000`, or `127.0.0.1:8080`, the first result is automatically selected as "Open URL" and Enter opens it in the default browser. Bare domains are normalized to `https://`.

The selection action panel (`⌘⇧F`) and the direct selection Ask AI shortcut (`⌘⇧P`) both send the selected text into the same Ask AI chat HUD, so you don't need to open the launcher first.

### Improve Names And Terms

Use **Personal Corrections** for deterministic fixes, or enable current-window OCR context boost so project names, people names, product names, and technical terms can become temporary hotwords for the current task.

### Enable LLM Correction

Open **Settings -> Models**, add an OpenAI-compatible provider, fill in Base URL, Model, and API Key, then test the connection. Once it works, enable **LLM Correction** in the same settings page.

LLM API keys are stored in macOS Keychain. Cloud ASR credentials for Groq, Tencent Cloud, and Alibaba Cloud are stored in the local SQLite settings database and can be revealed, hidden, or removed from Models.

## Privacy

VoxFlow is local-first by default.

- Asset history, personal correction rules, notes, transcription jobs, and non-secret settings are stored locally.
- LLM API keys are stored in macOS Keychain; cloud ASR credentials are stored in the local SQLite settings database.
- Apple Speech may process audio according to macOS system behavior.
- Local Qwen3-ASR runs on-device after the model is downloaded.
- LLM correction is disabled by default. When enabled, only recognized text is sent to your configured API provider.
- When you select a cloud ASR provider, recorded audio is sent to that provider. Local models keep audio on-device. VoxFlow does not proactively upload notes, asset history, or clipboard content.
- Clipboard assets are saved locally for launcher and Home review; noise filters skip meaningless high-frequency changes.
- Clipboard image OCR can still be used as a one-off OCR entry.
- Screenshot and recording records (OCR text + screenshot files captured via `⌘⇧A`) are stored locally and are never uploaded.

See [Privacy](docs/PRIVACY.md) for more details.

## FAQ

| Question | Answer |
| --- | --- |
| The shortcut does nothing | Check Accessibility permission, then quit and reopen VoxFlow |
| The overlay appears but no text shows up | Check Microphone, Speech Recognition, or the selected model state |
| Screenshot and recording records are missing | Go to Settings → Data & Privacy → Data Management, then check storage health and open the data folder to confirm `Application Support/VoxFlow/Screenshots/` has image records. Also verify Screen Recording permission. |
| How do I disable a default screenshot annotation tool? | The current version does not expose a persistent "default annotation tool" setting; switch to the Select/Cursor tool in each capture panel to avoid entering annotation mode by default. |
| LLM correction does not run | Make sure it is enabled in Settings and the default provider passes the connection test |
| Why is my API key hidden? | That is expected. Use the reveal button while editing if you need to inspect it |
| Can I use it offline? | Download and select a local Qwen3-ASR model |
| Can deleted history or notes be restored? | Deletion is local and immediate, so please confirm before deleting |

## Run From Source

If you want to build the app yourself:

```bash
git clone https://github.com/xingbofeng/VoxFlow.git
cd VoxFlow
make run-dev
```

Common commands:

```bash
make run-dev      # Daily development: Debug + native arch, package and launch .app
make run-native   # Native Release for local checks close to shipped behavior
make build        # arm64 Release, used for release/DMG
make install      # Install into /Applications
swift test        # Run tests
```

## Tech Stack And Open-Source Dependencies

VoxFlow is a native macOS app, not an Electron wrapper. The codebase is split into SwiftPM targets, keeps local-first paths local by default, and only uses cloud providers that the user explicitly configures.

| Area | Stack / Open-Source Dependency | Used For |
| --- | --- | --- |
| App shell | Swift 6, SwiftUI, AppKit, SwiftPM | Menu-bar app, Workbench, Settings, HUD, and macOS window lifecycle |
| System APIs | AVFoundation, Speech, Vision, Accessibility, Pasteboard | Recording, Apple Speech, screenshot/clipboard OCR, text insertion, and current-window context |
| Screenshot capture & annotation | VoxFlowScreenshotKit, ScreenCaptureKit, CoreGraphics, Vision | Region capture, annotation tools, scroll capture, and screenshot rendering |
| Local ASR | speech-swift Qwen3ASR / Nemotron, WhisperKit, FluidAudio, Sherpa-ONNX vendor runtime | Qwen3-ASR, NVIDIA Nemotron, Whisper, SenseVoice, Paraformer, and FunASR routes |
| Cloud ASR / LLM | OpenAI-compatible HTTP, Groq, Tencent Cloud realtime ASR, Alibaba DashScope | Online transcription, LLM correction, translation fallback, summary, and Agent Compose |
| Personal Corrections | `Packages/VoxFlowVoiceCorrectionKit`, inspired by TypeWhisper deterministic post-processing and focused text observation | Local rule matching, conflict resolution, learned candidates, and benchmark fixtures |
| Context hotwords | `Packages/VoxFlowContextBoostKit`, Vision OCR, NaturalLanguage | Extract temporary Top-K hotwords from current-window OCR text for the current prompt only |
| AI Coding 助手 | Rust `agent-cli/` helper/router, JSON IPC, MCP self-reporting | Dispatch spoken instructions to local Codex, Claude, CodeBuddy, or terminal agents |
| Verification | XCTest, Makefile, GitHub Actions, JiWER cross-check scripts | Unit tests, release builds, ASR/correction benchmarks, and metric validation |

Attribution and licensing notes live next to the relevant modules: `Packages/VoxFlowVoiceCorrectionKit/NOTICE.md`, `SOURCE_ATTRIBUTION.md`, and `MODIFICATIONS.md` document TypeWhisper references and adaptation boundaries; `Vendor/` contains packaged local runtime/vendor assets; AI Coding 助手 keeps only the Rust helper and no longer ships the old Python CLI.

### Source Layout

```
Sources/                         # Swift app code, domain modules, ASR providers, text insertion, and other SwiftPM targets
Packages/VoxFlowVoiceCorrectionKit/ # Personal Corrections engine, benchmark fixtures, and package tests
agent-cli/                       # Rust helper/router source for AI Coding 助手; builds the bundled `voxflow` binary and `vox` shim
Tests/                           # Swift unit tests plus Python tests for ASR benchmark tooling
Resources/                       # App icon and bundled resources
Vendor/                          # Local runtime/vendor assets required by packaged builds
docs/                            # GitHub Pages site, privacy docs, design notes, and implementation plans
scripts/                         # Build, ASR benchmark, and architecture-check helper scripts
tools/                           # Auxiliary verification tools; currently JiWER cross-check only, not an agent CLI
.github/                         # CI, Pages, Release workflows, and release notes
```

AI Coding 助手 has a single maintained CLI implementation: the Rust source in root-level `agent-cli/`. The old Python `vf-agent` / `agent-cli` reference helper has been removed. Remaining Python files are for benchmarks, architecture checks, or Personal Corrections metric cross-checks; they are not part of the app runtime and are not distributed as the user-facing CLI.

## Third-Party Modules And Open-Source Licenses

### License

VoxFlow is distributed under GPL-3.0-or-later. Third-party components keep their
original license notices and attribution. See `docs/third-party-licenses.md`.

### Third-Party Modules

### Unified Modules and References

| Type | Module / Source | Link | What It Is Used For |
| --- | --- | --- | --- |
| Third-party dependency | `speech-swift` (`Qwen3ASR`, `NemotronStreamingASR`, `ParakeetStreamingASR`, `OmnilingualASR`, `Qwen3TTS`, `Qwen3Chat`, `KokoroTTS`, `MADLADTranslation`) | [GitHub](https://github.com/soniqo/speech-swift.git) | Local ASR/TTS/translation/chat runtime |
| Third-party dependency | `WhisperKit` | [GitHub](https://github.com/argmaxinc/WhisperKit.git) | Local Whisper transcription |
| Third-party dependency | `FluidAudio` | [GitHub](https://github.com/FluidInference/FluidAudio.git) | Local ASR pipeline for Paraformer/SenseVoice |
| Third-party dependency | `Sherpa-ONNX` | [GitHub](https://github.com/k2-fsa/sherpa-onnx.git) | FunASR local inference runtime |
| Third-party dependency | `onnxruntime` (`Vendor/CSherpaOnnx`) | [GitHub](https://github.com/microsoft/onnxruntime) | Inference runtime bundled with Sherpa-ONNX |
| In-repo module | `VoxFlowContextBoostKit` | [Repo path](Packages/VoxFlowContextBoostKit) | OCR context hotword extraction |
| In-repo module | `VoxFlowVoiceCorrectionKit` | [Repo path](Packages/VoxFlowVoiceCorrectionKit) | Deterministic correction engine and benchmarks |
| In-repo module | `agent-cli` (Rust) | [Repo path](agent-cli) | Local terminal AI agent dispatching helper |
| Reference source | TypeWhisper | [GitHub](https://github.com/TypeWhisper/typewhisper-mac) | Deterministic correction flow + focused observation learning (conceptual only; no source copy) |
| Reference source | FlashText | [GitHub](https://github.com/vi3k6i5/flashtext) | Matching/replacement approach inspiration (no runtime reuse) |
| Reference source | JiWER | [GitHub](https://github.com/jitsi/jiwer) | Evaluation and benchmark cross-check reference |
| Reference source | OpenAI Evals | [GitHub](https://github.com/openai/evals) | Benchmark/test-case organization style reference |
| Reference source | LanguageTool | [GitHub](https://github.com/languagetool-org/languagetool) | Error-correction fixture and testing style reference |

### License and Attribution References

| Path | What It Covers |
| --- | --- |
| `LICENSE` | Project-level license |
| `SOURCE_ATTRIBUTION.md` | Third-party source references and adaptation scope |
| `MODIFICATIONS.md` | Upstream adaptation notes |
| `Packages/VoxFlowVoiceCorrectionKit/NOTICE.md` | TypeWhisper-derived source licensing |
| `Vendor/` | Vendored runtime license declarations |
| `Package.swift` + `NOTICE/LICENSE` in `Sources/` and `Packages/` | Component dependency and license declarations |

## Connect

Follow me on X: [@Counterxing](https://x.com/Counterxing)

## WeChat

Scan the QR code below to add the author on WeChat and share feedback or usage notes.

<p align="center">
  <img src="Sources/VoxFlowApp/Resources/AuthorWeChatQRCode.jpg" alt="Author WeChat QR code" width="320">
</p>
