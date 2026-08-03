<div align="center">
  <img src="docs/assets/voiceinput-logo.png" alt="VoxFlow logo" width="128">

  <h1>碼上寫 · VoxFlow</h1>
  <p><strong>支援 macOS、Windows 與 iOS 的語音輸入工具。</strong></p>
  <p>三個平台都能以語音輸入；桌面版提供全域聽寫，macOS 版另含完整的本機脈絡工作台。</p>

  <p>
    <img src="https://img.shields.io/badge/macOS-15%2B-000000?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="macOS 15+">
    <img src="https://img.shields.io/badge/Windows-x64-0078D4?style=flat-square&amp;logo=windows11&amp;logoColor=white" alt="Windows x64">
    <img src="https://img.shields.io/badge/iOS-17%2B-000000?style=flat-square&amp;logo=ios&amp;logoColor=white" alt="iOS 17+">
    <img src="https://img.shields.io/badge/Swift-6%2B-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Swift 6+">
    <img src="https://img.shields.io/badge/Native-macOS-147EFB?style=flat-square" alt="Native macOS">
    <img src="https://img.shields.io/badge/Local--first-1F883D?style=flat-square" alt="Local-first">
    <img src="https://img.shields.io/badge/Credentials-file-6E40C9?style=flat-square" alt="Credentials file">
    <a href="https://github.com/xingbofeng/VoxFlow/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/xingbofeng/VoxFlow/ci.yml?branch=main&amp;style=flat-square&amp;label=CI" alt="CI"></a>
    <a href="https://github.com/xingbofeng/VoxFlow/releases/latest"><img src="https://img.shields.io/github/v/release/xingbofeng/VoxFlow?style=flat-square&amp;label=Latest%20release" alt="Latest release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0--or--later-blue?style=flat-square" alt="License: GPL-3.0-or-later"></a>
  </p>
  <p>
    <a href="https://mashangxie.app/">官方網站</a>
    &nbsp;·&nbsp;
    <a href="https://github.com/xingbofeng/VoxFlow/releases/latest">下載最新版</a>
    &nbsp;·&nbsp;
    <a href="README.md">English</a>
    &nbsp;·&nbsp;
    <a href="README.zh-CN.md">简体中文</a>
    &nbsp;·&nbsp;
    <a href="README.zh-TW.md">繁體中文</a>
    &nbsp;·&nbsp;
    <a href="README.ja.md">日本語</a>
    &nbsp;·&nbsp;
    <a href="README.ko.md">한국어</a>
  </p>
  <p>
    <a href="docs/assets/voiceinput-demo-land.mp4"><img src="docs/assets/voiceinput-demo-land.gif" alt="介紹影片" width="100%"></a>
  </p>
</div>

## VoxFlow 是什麼

VoxFlow 服務於你正在使用的 App。它不是語音助理：不接管視窗，不切到另一個輸入框，不按 Enter，也不自動送出訊息。

它首先是語音鍵盤，也會把聽寫、截圖、螢幕錄影、剪貼簿、筆記和本機 coding-agent 指令整理成可搜尋的本機資產。

## 核心工作流

| Workflow | Trigger | What Happens | Safety Boundary |
| --- | --- | --- | --- |
| Speak to type | Hold the dictation shortcut, speak, release | Text is inserted at the current cursor | No focus stealing, no auto-submit |
| Open the launcher | `⌥Space` | Search recent assets, actions, quicklinks, and Ask AI | Keyboard-first, Raycast-style |
| Recover local assets | Launcher or Workbench | Search voice, screenshot, recording, clipboard, and note history | Stored locally by default |
| OCR an image | Copy an image, press `⌘⇧V` | OCR text is pasted into the current field | Image-only workflow |
| Capture the screen | Press `⌘⇧A`, select a region | Review OCR, translation, summary, and the image record | Requires Screen Recording permission |
| Work with selected text | `⌘⇧F/J/K/L/P` | Translate, summarize, send to Task Assistant, or Ask AI | Uses explicit shortcuts |
| Compose for AI tools | Speak intent with window context | A prompt is copied for ChatGPT, Claude, Codex, Cursor, or similar tools | Copy only |
| Command local agents | Speak an agent name and task | Dispatch to registered Codex, Claude, CodeBuddy, or terminal-agent sessions | Registered sessions only |

## 適合誰

- People who write, code, debug, and explain things faster by speaking than typing.
- Users who switch between ChatGPT, Claude, Codex, Cursor, terminal agents, notes, screenshots, and browser research.
- Developers who need accurate mixed Chinese-English technical dictation.
- Anyone who wants screenshots, recordings, clipboard items, and dictated text to become reusable local context.

## 功能亮點

- **Global dictation**: Hold to speak and release to insert text in any editable field.
- **Local asset workbench**: Dictation, screenshots, screen recordings, clipboard items, and notes become searchable assets.
- **Multiple ASR providers**: Apple Speech works out of the box; local and cloud providers are available when configured.
- **Personal corrections**: Local deterministic rules and optional conservative LLM correction help stabilize names, terms, and technical words.
- **Screenshot and clipboard OCR**: Extract text from screenshots, copied images, web pages, error dialogs, and design mockups.
- **Ask AI and Quicklinks**: The launcher can ask your configured LLM provider or search Google, GitHub, StackOverflow, YouTube, Bilibili, Taobao, JD, and more.
- **AI Coding Assistant workflows**: Compose prompts or dispatch spoken instructions to local coding-agent sessions.
- **Local-first privacy**: History and assets stay on your Mac by default; cloud ASR and LLM calls are opt-in.

## 快速開始

### 下載與安裝

從 [GitHub Releases](https://github.com/xingbofeng/VoxFlow/releases/latest) 下載最新版本：

| 平台 | 安裝包 | 安裝方式 |
| --- | --- | --- |
| macOS | `VoxFlow-1.15.0-macOS.dmg` | 開啟 DMG，將 VoxFlow 拖入「應用程式」。 |
| Windows x64 | `VoxFlow-1.15.0-windows-x64-setup.exe` 或 `VoxFlow-1.15.0-windows-x64-portable.zip` | 執行目前使用者安裝程式，或解壓縮可攜版。 |
| iOS 17+ | `Mashangxie-1.15.0-iOS.ipa` | 僅能安裝至已登記於 Ad Hoc profiles 的 UDID 裝置。 |

### 系統需求

- macOS 15+、Windows x64 或 iOS 17+
- 麥克風
- 安裝 iOS IPA 的裝置必須已登記於本次 Ad Hoc 發佈

### 首次授權

| Permission | Why VoxFlow Needs It |
| --- | --- |
| Accessibility | Listen for global shortcuts and insert text into the current app |
| Microphone | Record your voice |
| Speech Recognition | Use Apple Speech when selected |
| Screen Recording | Read current-window context, screenshot OCR, and screen recording content |

If a shortcut does not respond after granting permissions, quit and reopen VoxFlow.

### 預設快捷鍵

| Shortcut | Action |
| --- | --- |
| `⌥Space` | Open the VoxFlow launcher |
| Dictation shortcut | Hold to speak, release to insert; configurable in Settings |
| `⌘⇧V` | OCR clipboard image and paste recognized text |
| `⌘⇧A` | Capture a screen region and open the OCR result panel |
| `⌘⇧F` | Open selection actions |
| `⌘⇧J` | Translate selected text |
| `⌘⇧K` | Summarize selected text |
| `⌘⇧L` | Send selected text to Task Assistant |
| `⌘⇧P` | Send selected text to Ask AI |

## 怎麼使用

### 語音輸入

1. Place your cursor in any text field.
2. Hold the dictation shortcut.
3. Speak while the overlay shows live recognition.
4. Release the shortcut. VoxFlow inserts the final text at the cursor.

### 工作台

Open the Workbench to review local history, screenshots, recordings, notes, personal corrections, models, provider settings, and AI Coding Assistant sessions.

### 截圖與剪貼簿 OCR

Use `⌘⇧V` for copied images and `⌘⇧A` for a selected screen region. OCR text can be copied, spoken, translated, summarized, or reused later from the Workbench.

### Agent 工作流

Task Assistant turns visible window context plus spoken intent into a prompt. AI Coding Assistant dispatches spoken instructions to registered local coding-agent sessions.

See [Agent workflows](docs/agent-workflows.md) for setup and safety boundaries.

## 語音模型

VoxFlow supports Apple Speech out of the box, local providers such as Qwen3-ASR, Whisper, FunASR, SenseVoice, Paraformer, NVIDIA Nemotron, Parakeet, and Omnilingual, plus optional cloud providers such as Groq, Tencent Cloud, Alibaba Cloud, and future provider slots.

See [Speech models](docs/speech-models.md) for the full provider matrix.

## 隱私摘要

- Dictation history, screenshots, recordings, clipboard assets, notes, personal corrections, and non-secret settings are stored locally by default.
- LLM API keys and cloud ASR credentials are stored in the local credentials file.
- Local ASR models keep audio on-device.
- Cloud ASR sends recorded audio to the selected provider.
- LLM correction and Ask AI send text only to the provider you configure.
- Diagnostics are local by default; crash or trace upload behavior is controlled by settings.

See [Privacy and data](docs/privacy-and-data.md) and [Privacy Policy](docs/PRIVACY.md) for details.

## 文件

| Topic | Link |
| --- | --- |
| English documentation | [docs/README.md](docs/README.md) |
| Speech model matrix | [docs/speech-models.md](docs/speech-models.md) |
| Agent workflows | [docs/agent-workflows.md](docs/agent-workflows.md) |
| Privacy and data storage | [docs/privacy-and-data.md](docs/privacy-and-data.md) |
| Build from source | [docs/build-from-source.md](docs/build-from-source.md) |
| Third-party licenses | [docs/third-party-licenses.md](docs/third-party-licenses.md) |

## 從原始碼執行

```bash
git clone https://github.com/xingbofeng/VoxFlow.git
cd VoxFlow
make run-dev
```

See [Build from source](docs/build-from-source.md) for commands, source layout, and development notes.

## 聯絡

作者 X： [@Counterxing](https://x.com/Counterxing)

## 微信與使用者群

掃描下方 QR code 添加作者微信或加入 VoxFlow 使用者群。

<table>
  <tr>
    <td align="center">
      <strong>添加微信</strong><br>
      <img src="Sources/VoxFlowApp/Resources/AuthorWeChatQRCode.jpg" alt="作者微信 QR code" width="300">
    </td>
    <td align="center">
      <strong>加入使用者群</strong><br>
      <img src="Sources/VoxFlowApp/Resources/UserGroupQRCode.jpg" alt="VoxFlow 使用者群 QR code" width="300">
    </td>
  </tr>
</table>
