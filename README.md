<div align="center">
  <img src="docs/assets/voiceinput-logo.png" alt="码上写 logo" width="128">

  <img src="docs/assets/voiceinput-hero.svg" alt="码上写 - Hold. Speak. Done." width="100%">

  <h1>码上写 · VoxFlow</h1>
  <p><strong>把口述、截图文字和 coding-agent 指令送回当前工作现场。</strong></p>
  <p>原生 macOS 菜单栏语音工作流入口：按住说话即可输入，框选截图即可 OCR，喊出队员即可投递给本地 Agent。</p>
  <p><sub><a href="README_EN.md">English</a></sub></p>

  <p>
    <img src="https://img.shields.io/badge/macOS-15%2B-111827?style=flat-square&logo=apple&logoColor=white" alt="macOS 15+">
    <a href="https://github.com/xingbofeng/VoxFlow/releases/latest"><img src="https://img.shields.io/github/v/release/xingbofeng/VoxFlow?style=flat-square&label=release" alt="Latest release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-open%20source-10B981?style=flat-square" alt="License"></a>
  </p>
  <p>
    🌐 <a href="https://xingbofeng.github.io/VoxFlow/">官方网站</a>
    &nbsp;·&nbsp;
    ⬇️ <a href="https://github.com/xingbofeng/VoxFlow/releases/latest">下载最新版</a>
    &nbsp;·&nbsp;
    🎬 <a href="docs/voiceinput-demo-land.mp4">介绍视频</a>
  </p>
</div>

> **版本提示**：当前文档对应 VoxFlow 1.4.0。v1.4.0 正式发布前，下载入口可能仍指向上一版稳定包；需要验证最新能力时请从源码运行。

## 码上写是什么

码上写是一个贴在当前工作流上的“语音键盘”，不是语音助手，也不是另一个让你切过去工作的窗口。

它常驻菜单栏，只在你需要输入、识别截图或指挥本地 Agent 时出现。把光标放在想输入的位置，按下快捷键开始说话，松开后文字回到原来的应用里；复制图片或框选屏幕，它可以把画面里的文字变成可编辑内容；打开 Vibe Coding 后，它还能把语音指令派给已注册的 Codex、Claude、CodeBuddy 或其他终端会话。

它的目标很简单：

- **输入更快**：把“脑子里已经想好的话”直接说出来。
- **打扰更少**：不抢焦点，不弹大窗口，不破坏当前工作流。
- **结果更稳**：识别、易错词、LLM 纠错、词汇表、风格、历史记录和文本插入都围绕“把文字放到正确的位置”服务。
- **数据可控**：默认本机保存；本地 ASR、系统识别和可选 LLM 纠错可以按场景选择。

## 适合谁

码上写特别适合这些场景：

- 经常和 ChatGPT、Claude、Codex、Cursor 或其他 AI 工具沟通，需要快速描述需求、上下文和修改意见。
- 同时开着 Codex、Claude、CodeBuddy 或其他终端 Agent，希望用语音把指令直接派给对应队员。
- 写代码时常要解释 bug、补充注释、写提交说明、记录排查过程。
- 想快速记录灵感、会议要点、待办、长消息或文章草稿。
- 经常需要从截图、网页、报错弹窗或图片里提取文字，并进一步翻译或总结。
- 中英文混说比较多，希望技术词、产品名和专有名词更稳定。
- 喜欢 macOS 原生体验，希望工具安静、克制、常驻菜单栏。

## 四个核心工作流

| 工作流 | 做什么 | 边界 |
| --- | --- | --- |
| 语音输入 | 按住快捷键说话，松开后把最终文本插入当前光标 | 不抢焦点，不自动发送 |
| 易错词与纠错 | ASR final 和可选 LLM 后做本地确定性修正，也能从你后续编辑里学习候选 | 默认本地运行，候选是否生效可控 |
| 截图 OCR | 剪贴板图片直接粘贴 OCR；框选截图打开结果面板，可翻译、总结、朗读 | 原图不作为长期数据保存 |
| AI 工作流 | “帮我说”生成可复制提示词；Vibe Coding 把语音指令投递给本地终端 Agent | Agent Compose 只复制；Vibe Coding 只投递注册会话 |

## 语音输入与识别模型

### 按住说话，松开输入

码上写默认使用快捷键触发听写。按住说话时，屏幕上会出现一个轻量的转写浮层；松开后，最终文字会自动输入到当前光标位置。

你不需要切换应用，也不需要手动复制粘贴。它就像键盘一样，服务于当前正在使用的 App。

### 实时转写

说话过程中可以看到实时文本。短句、长段说明、中文、英文和中英混合内容都会即时显示，方便你边说边确认方向。

码上写内置系统语音识别，也支持本地和在线 ASR Provider。系统自带模型开箱可用；本地 Qwen3-ASR、Whisper、FunASR、SenseVoice、NVIDIA Nemotron、Parakeet、Omnilingual 等路线适合更重视离线能力、隐私和可控性的场景；在线 Groq、腾讯云、阿里云适合不想下载本地模型或需要云端能力的场景。模型页会明确标注“离线 / 在线”“流式 / 非流式”“中文 / 英文 / 多语言”等标签。

### 支持的语音模型

码上写不会把所有模型强行塞进同一个运行时。不同模型的上游格式、流式能力、语言覆盖和隐私边界不同，所以会按模型选择最合适的 Provider target 或云端 runtime。

#### 离线 / 本地模型

这些 Provider 的音频不上传到第三方云服务；除“系统自带”可能依赖 Apple 系统服务外，本地模型都在本机完成推理。

| 模型 | 状态 | 流式能力 | 运行路线 | 语言侧重 | 适合场景 |
| --- | --- | --- | --- | --- | --- |
| 系统自带 | 开箱可用 | 流式 | Apple Speech / SFSpeechRecognizer | 取决于 macOS 语音识别语言 | 不下载模型、先快速开始 |
| Qwen3-ASR 0.6B | 已支持 | 流式 partial + final | speech-swift `Qwen3ASR` / MLX 4bit | 中文、英文、多语言 | 默认推荐本地听写，体积和速度更均衡 |
| Qwen3-ASR 1.7B | 已支持 | 流式 partial + final | speech-swift `Qwen3ASR` / MLX 8bit | 中文、英文、多语言 | 更高准确率本地听写，需要更高内存 |
| FunASR Nano INT8 / FP32 | 已支持 | 流式片段确认 | Sherpa-ONNX | 中文、英文 | 中文本地备选，不依赖 CoreML |
| Whisper Turbo / Large V3 | 已支持 | 非流式 | WhisperKit | 多语言 | 录音结束后的高质量完整转写 |
| SenseVoice | 已支持 | 当前按非流式/短句使用 | FluidAudio / CoreML | 中文、英文、多语言 | 本地多语种短句转写 |
| Paraformer Large zh | 已支持 | 流式片段确认 | FluidAudio / CoreML int8 | 中文 | 中文本地转写 |
| NVIDIA Nemotron 0.6B | 已支持 | 原生流式 | speech-swift `NemotronStreamingASR` / CoreML | 多语言 | 本地流式转写候选 |
| Parakeet Streaming | 已支持 | 原生流式 | speech-swift `ParakeetStreamingASR` / CoreML | 英文和欧洲语种 | 英文低延迟听写 |
| Omnilingual ASR | 已支持 | 非流式 | speech-swift `OmnilingualASR` / CoreML | 超多语言 | 广语言覆盖、文件/实验场景 |

#### 在线 / 云端模型

在线 Provider 会把录音发送到对应服务商。API Key、SecretId、SecretKey 等凭据保存在本地 SQLite 设置表中，设置页支持用“眼睛”按钮临时显示或隐藏。

| Provider | 状态 | 流式能力 | 默认模型 / 接口 | 配置项 | 适合场景 |
| --- | --- | --- | --- | --- | --- |
| Groq（免费） | 已支持 | 非流式 | OpenAI-compatible audio transcription，默认 `whisper-large-v3-turbo` | API Key、模型名 | 不下载本地模型，松开后快速返回最终文本 |
| 腾讯云 | 已支持 | 实时流式 | 腾讯云实时语音识别 WebSocket，默认 `16k_zh` | AppID、SecretId、SecretKey | 中文普通话实时云端听写 |
| 阿里云 | 已支持 | 实时流式 | DashScope WebSocket，默认 `fun-asr-realtime` | 百炼 API Key | 中文和多语言实时云端听写 |
| 火山云 | 待实现 | 计划流式 | 豆包语音大模型流式 ASR WebSocket | 待定 | 后续接入火山云实时 ASR |
| Mistral Voxtral | 待实现 | 待定 | 官方 Voxtral 语音能力 | 待定 | 预留在线 Provider |
| AssemblyAI | 待实现 | 待定 | AssemblyAI Transcription | 待定 | 预留在线 Provider |
| ElevenLabs Scribe | 待实现 | 待定 | ElevenLabs Scribe | 待定 | 预留在线 Provider |

## 纠错、OCR 和 Agent 工作流

### 易错词与可选 LLM 纠错

语音识别在技术词上容易出错，例如把 Python、JSON、TypeScript 识别成谐音或拆开的词。码上写可以在听写完成后，用你配置的 OpenAI 兼容模型做一次保守纠错。

新版“易错词”是独立一级页面，会在 ASR final 和可选 LLM 之后做本地确定性修正；也可以从你后续手动修改的内容中学习候选规则。LLM 纠错不会替你润色或改写，只修明显听错的词，你仍然掌控原文语气和表达。

### 截图 OCR、翻译和总结

复制截图后按 `Command + Shift + V`，码上写会识别剪贴板图片里的文字并粘贴到当前光标。按 `Command + Shift + A` 框选屏幕区域时，会打开结果面板，支持原图、OCR、翻译和总结视图。

这个能力适合处理网页、报错弹窗、截图、设计稿和聊天记录。OCR 结果可以继续复制、朗读、翻译或总结，但不会进入易错词的永久学习链路。

### 帮我说与 Vibe Coding 指挥中心

“帮我说”适合把当前窗口的可见上下文、OCR 文本和你的口述意图整理成一段可复制的提示词；它只复制结果，不自动发送。

Vibe Coding 指挥中心面向本地 coding-agent 终端。开启后，你可以按住语音快捷键说出队员名和指令，码上写会解析目标 Agent、展示确认状态，并把指令投递到对应的 Codex、Claude、CodeBuddy 或任意已注册终端会话。

### 工作台

除了菜单栏快速输入，码上写也提供完整工作台：

| 页面 | 可以做什么 |
| --- | --- |
| 首页 | 查看使用统计、今日目标、历史记录，快速复制或删除转写 |
| 易错词 | 管理本地确定性纠错规则、候选学习、启用状态和最近事件 |
| 词汇表 | 管理常用词、专有名词和 prompt 词表，让识别更贴合你的语境 |
| 风格 | 为不同应用或场景设置输出风格，比如原文、正式、邮件、编程说明 |
| 文件转写 | 导入音频或视频，排队转写，导出 txt、md、srt，或保存为笔记 |
| 笔记 | 直接录音记笔记，也可以编辑、搜索和回看记录 |
| Vibe Coding | 查看已注册 Agent 队员、别名、工作目录、分支和调度记录 |
| 设置 | 管理输入设备、快捷键、模型、翻译模型、权限、隐私和数据 |
| 帮助 | 查看权限提示、版本信息、项目链接和常见入口 |

## 功能亮点

- **全局听写**：在任意可编辑输入框里使用，不局限于码上写自己的窗口。
- **不抢焦点的浮层**：听写时只显示轻量浮层，不打断当前应用。
- **多 Provider ASR**：系统语音识别开箱可用，本地 Qwen3-ASR、Whisper、FunASR、SenseVoice、NVIDIA Nemotron、Parakeet、Omnilingual 等 Provider 逐步接入统一运行时；暂不支持实时流式的 Provider 会在模型页标注“非流式”。
- **稳定文本插入**：粘贴前临时切换输入源，完成后恢复输入源和剪贴板，减少 CJK 输入法干扰。
- **输入设备选择**：支持选择麦克风，长设备名会自动收纳，不挤爆界面。
- **快捷键录制**：在设置里直接录制想用的触发键，并配置短按行为。
- **剪贴板图片 OCR**：复制截图或图片后按 `Command + Shift + V`，自动识别图片文字并粘贴到当前输入框。
- **框选截图 OCR**：按 `Command + Shift + A` 框选屏幕区域，结果面板支持查看原图、OCR、翻译和总结。
- **Vibe Coding 指挥中心**：用语音把指令投递给本地终端里的 Codex、Claude、CodeBuddy 或其他已注册 Agent。
- **帮我说**：结合当前窗口 OCR 上下文和口述意图生成提示词，只复制结果，不自动发送。
- **OpenAI 兼容模型**：可添加、测试、编辑和删除 Provider，LLM API Key 保存到 macOS Keychain。
- **易错词和词汇表**：把常用词、易错词、缩写和专有名词交给码上写记住。
- **历史和笔记**：转写不只是一闪而过，后续可以搜索、复制、整理和复用。
- **文件转写**：把录音、视频、会议音频转成文字，适合复盘和归档。
- **数据可控**：历史、词汇、设置和笔记保存在本机；是否启用 LLM 由你决定。

## 快速开始

### 下载安装

从 [GitHub Releases](https://github.com/xingbofeng/VoxFlow/releases/latest) 下载最新版本：

1. 打开 `VoxFlow-1.4.0-macOS.dmg`
2. 将 `VoxFlow` 拖入 `Applications` 文件夹
3. 首次启动时，如果 macOS 提示无法验证，请按住 Control 点击应用，选择“打开”

> 如果你想体验当前 `main` 分支上的易错词、Vibe Coding 或截图 OCR 最新实现，请从源码运行；这些能力可能晚于最新稳定版 Release。

### 系统要求

- macOS 15 Sequoia 或更高版本（Apple Silicon）
- 一台带麦克风的 Mac

### 首次授权

码上写需要几个系统权限才能正常工作：

| 权限 | 用途 | 位置 |
| --- | --- | --- |
| 辅助功能 | 监听全局快捷键，并把文字输入到当前应用 | 系统设置 -> 隐私与安全性 -> 辅助功能 |
| 麦克风 | 录制你的声音 | 系统设置 -> 隐私与安全性 -> 麦克风 |
| 语音识别 | 使用系统自带语音识别模型 | 系统设置 -> 隐私与安全性 -> 语音识别 |
| 屏幕录制 | 为“帮我说”和截图 OCR 读取屏幕文字，上下文截图不落盘 | 系统设置 -> 隐私与安全性 -> 屏幕录制 |

如果你选择本地 Qwen3-ASR 模型，语音识别权限不是必须的；麦克风权限仍然需要。

授权后如果快捷键没有响应，退出码上写后重新打开即可。

## 怎么使用

### 语音输入

1. 把光标放到任意输入框。
2. 按住听写快捷键。
3. 开始说话，浮层会实时显示识别结果。
4. 松开快捷键，文字会自动输入到光标所在位置。

### 录音记笔记

打开工作台里的“笔记”，点击录音按钮即可开始记录。说话过程中会实时转写，完成后可以继续编辑，也可以在最近记录中回看。

### 文件转写

打开“文件转写”，选择音频或视频文件。码上写会显示任务进度，完成后可以复制、导出，或保存为笔记。

### 剪贴板图片 OCR

复制一张截图或图片后，按 `Command + Shift + V`。码上写会读取剪贴板中的图片，自动 OCR 识别其中的文字，并粘贴到当前光标所在位置。

如果剪贴板里没有图片，这个快捷键不会启动普通语音听写；它只用于剪贴板图片 OCR 工作流。

### 框选截图 OCR、翻译和总结

按 `Command + Shift + A` 后框选屏幕区域。码上写会用系统截图读取画面、运行 OCR，并打开结果面板。你可以在“原图 / OCR / 翻译 / 总结”之间切换，也可以复制或朗读对应内容。

翻译模型可以使用 Apple 系统翻译、已配置的 LLM，或本地翻译模型；总结可以走已配置 LLM 或本地总结模型。没有可用模型时，OCR 原文仍然可用。

### 帮我说

“帮我说”会读取当前窗口的可见文字和可选 OCR 上下文，再结合你的语音意图生成一段可复制提示词。它遵守只复制、不注入、不自动发送的边界，适合在 ChatGPT、Claude、Codex、Cursor 等工具里整理复杂请求。

### Vibe Coding 指挥中心

在设置里启用 Vibe Coding 指挥中心后，现有语音输入快捷键可以进入指挥 HUD。说出队员名和任务，例如“前端检查按钮状态”，码上写会解析目标 Agent，必要时让你确认候选，并把指令投递到对应终端会话。

### 让专有名词更准

在“易错词”里添加确定性纠错规则，或在“词汇表”里添加项目名、人名、产品名和技术词。它们会参与后续转写和纠错流程，减少重复修改。

### 配置 LLM 纠错

打开“设置 -> 模型”，添加 OpenAI 兼容 Provider，填写 Base URL、Model 和 API Key。测试通过后，打开“启用 LLM 纠错”即可。

LLM API Key 会保存在 macOS Keychain，不会写入普通配置文件。Groq、腾讯云和阿里云等云端 ASR 凭据按当前产品设计保存在本地 SQLite 设置表中，可在模型设置里显示、隐藏或删除。

## 隐私说明

码上写的默认原则是：能留在本机的，就留在本机。

- 历史记录、词汇表、笔记、任务和非敏感设置保存在本机。
- LLM API Key 保存到 macOS Keychain；云端 ASR 凭据保存在本地 SQLite 设置表中。
- 系统自带语音识别可能由 Apple 处理音频，取决于系统能力和语言。
- 本地 Qwen3-ASR 模型下载后在本机运行。
- LLM 纠错默认关闭；开启后，只会把识别出的文本发到你配置的 API 服务。
- 选择云端 ASR 时，录音会发送给对应服务商；选择本地模型时，音频留在本机。码上写不会主动上传笔记、历史记录或剪贴板内容。

更完整的说明见 [隐私说明](docs/PRIVACY.md)。

## 常见问题

| 问题 | 处理方式 |
| --- | --- |
| 按快捷键没反应 | 检查辅助功能权限，退出后重新打开码上写 |
| 浮层出现但没有文字 | 检查麦克风权限、语音识别权限或当前模型状态 |
| LLM 纠错没有生效 | 确认已在设置中启用，并且默认 Provider 测试成功 |
| API Key 看不到明文 | 这是正常的，编辑时可点击显示按钮临时查看 |
| 想离线使用 | 下载并选择 Qwen3-ASR 本地模型 |
| 误删了历史或笔记 | 当前删除是本地操作，请谨慎确认后再删除 |

## 从源码运行

如果你想自己构建：

```bash
git clone https://github.com/xingbofeng/VoxFlow.git
cd VoxFlow
make run-dev
```

常用命令：

```bash
make run-dev      # 日常开发：Debug + 本机架构，打包并启动 .app
make run-native   # 本机架构 Release，用于接近发布表现的本地验证
make build        # arm64 Release，发布/DMG 使用
make install      # 安装到 /Applications
swift test        # 运行测试
```

### 源码目录分层

```
Sources/                         # Swift 应用源码、领域模块、ASR Provider、文本插入等 SwiftPM targets
Packages/VoxFlowVoiceCorrectionKit/ # 易错词纠错引擎、benchmark fixtures 和独立测试
agent-cli/                       # Vibe Coding 的 Rust helper/router 源码，产物为 bundled `voxflow` 和 `vox` shim
Tests/                           # Swift 单元测试，以及 ASR benchmark Python 测试
Resources/                       # App 图标等资源
Vendor/                          # 打包所需的本地 runtime/vendor 资源
docs/                            # GitHub Pages 落地页、隐私说明、设计文档和方案资料
scripts/                         # 构建、ASR benchmark、架构检查等开发脚本
tools/                           # 辅助验证工具；当前只保留易错词 JiWER 交叉检查脚本，不包含 agent CLI
.github/                         # CI、Pages、Release workflow 和发布日志
```

Vibe Coding 的 CLI 源码只维护 Rust 版本：根目录 `agent-cli/`。旧 Python 版 `vf-agent` / `agent-cli` 参考 helper 已删除；仓库里剩余的 Python 文件用于 benchmark、架构检查或易错词指标交叉验证，不参与 App 运行时，也不作为用户 CLI 分发。

## 灵感来源

本项目灵感来源于 [yetone/voice-input-src](https://github.com/yetone/voice-input-src)，感谢他们的开创性工作。
