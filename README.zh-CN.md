<div align="center">
  <img src="docs/assets/voiceinput-logo.png" alt="VoxFlow logo" width="128">

  <h1>码上写 · VoxFlow</h1>
  <p><strong>贴在当前工作流里的 macOS 语音键盘和本地上下文工作台。</strong></p>
  <p>按住快捷键说话，松开后文字回到当前光标；语音、截图、录屏和剪切板内容会沉淀为可搜索、可复用的本地资产。</p>

  <p>
    <img src="https://img.shields.io/badge/macOS-15%2B-000000?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="macOS 15+">
    <img src="https://img.shields.io/badge/Swift-6%2B-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Swift 6+">
    <img src="https://img.shields.io/badge/Native-macOS-147EFB?style=flat-square" alt="Native macOS">
    <img src="https://img.shields.io/badge/Local--first-1F883D?style=flat-square" alt="Local-first">
    <img src="https://img.shields.io/badge/Credentials-file-6E40C9?style=flat-square" alt="Credentials file">
    <a href="https://github.com/xingbofeng/VoxFlow/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/xingbofeng/VoxFlow/ci.yml?branch=main&amp;style=flat-square&amp;label=CI" alt="CI"></a>
    <a href="https://github.com/xingbofeng/VoxFlow/releases/latest"><img src="https://img.shields.io/github/v/release/xingbofeng/VoxFlow?style=flat-square&amp;label=Latest%20release" alt="Latest release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0--or--later-blue?style=flat-square" alt="License: GPL-3.0-or-later"></a>
  </p>
  <p>
    <a href="https://mashangxie.app/">官方网站</a>
    &nbsp;·&nbsp;
    <a href="https://github.com/xingbofeng/VoxFlow/releases/latest">下载最新版</a>
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
    <a href="docs/assets/voiceinput-demo-land.mp4"><img src="docs/assets/voiceinput-demo-land.gif" alt="介绍视频" width="100%"></a>
  </p>
</div>

## 码上写是什么

码上写服务于你正在使用的 App。它不是语音助手：不接管窗口，不把你带到另一个输入框，不按回车，也不自动发送消息。

它首先是一个语音键盘，同时围绕工作过程中产生的内容提供本地工作台：听写、截图、录屏、剪切板、笔记，以及本地 coding-agent 指令。

## 核心工作流

| 工作流 | 触发方式 | 会发生什么 | 安全边界 |
| --- | --- | --- | --- |
| 说话输入 | 按住听写快捷键，说话，松开 | 文字输入到当前光标 | 不抢焦点，不自动发送 |
| 打开启动台 | `⌥Space` | 搜索最近资产、动作、Quicklinks 和问 AI | 类 Raycast，键盘优先 |
| 找回本地资产 | 启动台或工作台 | 搜索语音、截图、录屏、剪切板和笔记历史 | 默认本地保存 |
| 图片 OCR | 复制图片后按 `⌘⇧V` | OCR 文本粘贴到当前输入框 | 只处理图片，不启动普通听写 |
| 截图处理 | 按 `⌘⇧A` 后框选区域 | 查看 OCR、翻译、总结和图片记录 | 需要屏幕录制权限 |
| 处理选中文本 | `⌘⇧F/J/K/L/P` | 翻译、总结、发给任务助手或问 AI | 显式快捷键触发 |
| 给 AI 工具写提示词 | 结合窗口上下文说出意图 | 复制一段可贴给 ChatGPT、Claude、Codex、Cursor 的提示词 | 只复制 |
| 指挥本地 Agent | 说出 Agent 名称和任务 | 投递给已注册 Codex、Claude、CodeBuddy 或终端 Agent 会话 | 只投递已注册会话 |

## 适合谁

- 写作、写代码、排查问题和解释需求时，说话比打字更快的人。
- 经常在 ChatGPT、Claude、Codex、Cursor、终端 Agent、笔记、截图和浏览器资料之间切换的人。
- 需要稳定处理中英文混合技术词的开发者。
- 希望截图、录屏、剪切板和听写内容能变成可复用本地上下文的人。

## 功能亮点

- **全局听写**：按住说话，松开后输入到任意可编辑输入框。
- **本地资产工作台**：听写、截图、录屏、剪切板和笔记都可以被搜索和复用。
- **多 ASR Provider**：Apple Speech 开箱可用；本地和云端 Provider 可按需配置。
- **易错词纠错**：本地确定性规则和可选保守 LLM 纠错，让人名、项目名和技术词更稳定。
- **截图与剪切板 OCR**：从截图、复制图片、网页、报错弹窗和设计稿里提取文字。
- **问 AI 和 Quicklinks**：启动台可以调用你配置的 LLM，也可以快速搜索 Google、GitHub、StackOverflow、YouTube、Bilibili、淘宝、京东等。
- **AI Coding 助手工作流**：生成提示词，或把语音指令投递给本地 coding-agent 会话。
- **本地优先隐私**：历史和资产默认留在 Mac；云端 ASR 和 LLM 调用都需要你显式配置。

## 快速开始

### 下载安装

从 [GitHub Releases](https://github.com/xingbofeng/VoxFlow/releases/latest) 下载最新版本：

1. 打开 `VoxFlow-1.15.0-macOS.dmg`。
2. 将 `VoxFlow` 拖入 `Applications` 文件夹。
3. 首次启动时，如果 macOS 提示无法验证，请按住 Control 点击应用，选择“打开”。

### 系统要求

- macOS 15 Sequoia 或更高版本
- 一台带麦克风的 Mac

### 首次授权

| 权限 | 为什么需要 |
| --- | --- |
| 辅助功能 | 监听全局快捷键，并把文字输入到当前应用 |
| 麦克风 | 录制你的声音 |
| 语音识别 | 使用 Apple Speech 时需要 |
| 屏幕录制 | 读取当前窗口上下文、截图 OCR 和录屏内容 |

授权后如果快捷键没有响应，退出码上写后重新打开即可。

### 默认快捷键

| 快捷键 | 作用 |
| --- | --- |
| `⌥Space` | 打开 VoxFlow 启动台 |
| 听写快捷键 | 按住说话，松开输入；可在设置里修改 |
| `⌘⇧V` | 识别剪切板图片并粘贴 OCR 文本 |
| `⌘⇧A` | 框选截图并打开 OCR 结果面板 |
| `⌘⇧F` | 打开划词动作 |
| `⌘⇧J` | 翻译选中文本 |
| `⌘⇧K` | 总结选中文本 |
| `⌘⇧L` | 发送选中文本到任务助手 |
| `⌘⇧P` | 发送选中文本到问 AI |

## 怎么使用

### 语音输入

1. 把光标放到任意输入框。
2. 按住听写快捷键。
3. 开始说话，浮层会显示实时识别结果。
4. 松开快捷键，码上写会把最终文字输入到光标位置。

### 工作台

打开工作台可以查看本地历史、截图、录屏、笔记、易错词、模型、Provider 设置和 AI Coding 助手会话。

### 截图与剪切板 OCR

`⌘⇧V` 用于复制图片，`⌘⇧A` 用于框选屏幕区域。OCR 文本可以复制、朗读、翻译、总结，也可以后续在工作台中复用。

### Agent 工作流

任务助手会把当前窗口上下文和你的口述意图整理成提示词。AI Coding 助手会把语音指令投递给已注册的本地 coding-agent 会话。

详见 [Agent 工作流](docs/zh-CN/agent-workflows.md)。

## 语音模型

码上写支持开箱可用的 Apple Speech，也支持 Qwen3-ASR、Whisper、FunASR、SenseVoice、Paraformer、NVIDIA Nemotron、Parakeet、Omnilingual 等本地 Provider，以及 Groq、腾讯云、阿里云和未来 Provider 预留位。

完整矩阵见 [语音模型](docs/zh-CN/speech-models.md)。

## 隐私摘要

- 听写历史、截图、录屏、剪切板资产、笔记、易错词和普通设置默认保存在本机。
- LLM API Key 和云端 ASR 凭据保存在本地凭据文件中。
- 本地 ASR 模型会在本机处理音频。
- 选择云端 ASR 时，录音会发送给对应服务商。
- LLM 纠错和问 AI 只会把文本发送给你配置的 Provider。
- 诊断默认保存在本地；崩溃日志或 trace 上传行为由设置控制。

详见 [隐私与数据](docs/zh-CN/privacy-and-data.md) 和 [隐私政策](docs/PRIVACY.md)。

## 文档

| 主题 | 链接 |
| --- | --- |
| 中文文档索引 | [docs/zh-CN/README.md](docs/zh-CN/README.md) |
| 语音模型矩阵 | [docs/zh-CN/speech-models.md](docs/zh-CN/speech-models.md) |
| Agent 工作流 | [docs/zh-CN/agent-workflows.md](docs/zh-CN/agent-workflows.md) |
| 隐私与数据存储 | [docs/zh-CN/privacy-and-data.md](docs/zh-CN/privacy-and-data.md) |
| 从源码构建 | [docs/zh-CN/build-from-source.md](docs/zh-CN/build-from-source.md) |
| 第三方许可证 | [docs/third-party-licenses.md](docs/third-party-licenses.md) |

## 从源码运行

```bash
git clone https://github.com/xingbofeng/VoxFlow.git
cd VoxFlow
make run-dev
```

更多命令和源码结构见 [从源码构建](docs/zh-CN/build-from-source.md)。

## 联系

作者 X：[ @Counterxing](https://x.com/Counterxing)

## 微信与用户群

扫描二维码添加作者微信或加入 VoxFlow 用户群。

<table>
  <tr>
    <td align="center">
      <strong>添加微信</strong><br>
      <img src="Sources/VoxFlowApp/Resources/AuthorWeChatQRCode.jpg" alt="作者微信二维码" width="300">
    </td>
    <td align="center">
      <strong>加入用户群</strong><br>
      <img src="Sources/VoxFlowApp/Resources/UserGroupQRCode.jpg" alt="VoxFlow 用户群二维码" width="300">
    </td>
  </tr>
</table>
