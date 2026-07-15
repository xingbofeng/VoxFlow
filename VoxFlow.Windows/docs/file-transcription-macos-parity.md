# 文件转写：macOS 到 Windows 对照基线

本文固定 Windows P3 文件转写的产品基线。实现和验收以当前 macOS
`FileTranscriptionView`、`FileTranscriptionViewModel`、
`VoxFlowFileTranscriptionPipeline` 及其本地化文案为准；Windows 只在平台能力不同或
OpenSpec 已明确排除时替换实现。

## 页面结构与尺寸

| macOS 基线 | Windows 要求 | 分类 |
|---|---|---|
| 页面最大内容宽度 1320，水平 36、垂直 34 内边距 | WPF 内容区保持同一最大宽度和内边距；窗口变窄时只出现必要的纵向滚动 | 复刻 |
| 顶部 22pt 半粗标题、13pt 副标题、右侧主按钮 | 使用 Segoe UI 对应层级；按钮位置、视觉主次和禁用态一致 | 复刻 |
| 上传区最小高度 118，圆角卡片，强调色 22% 虚线边框 | 支持点击、拖放、多选；不能只显示静态占位 | 复刻 |
| 主面板高度 480–540，内边距 14，圆角 16 | 1260×720 基准窗口保持相同密度；内容超出时内部滚动 | 复刻 |
| 左侧队列固定宽度 380，右侧结果自适应 | WPF 使用 380 / 分隔线 / 自适应三列结构 | 复刻 |
| 底部状态栏显示空闲、任务数或当前段进度 | 状态必须来自持久化任务投影，不能使用静态字符串 | 复刻 |

## 状态与操作矩阵

| 状态 | 队列卡主操作 | 详情可用操作 | Windows 差异 |
|---|---|---|---|
| `queued` | 开始 | 删除 | 无 |
| `running` | 取消 | 查看实时进度、删除前确认 | 全局只允许一个运行任务 |
| `interrupted` | 继续、从头重试 | 已完成文本仍可复制和导出 | Windows 的继续必须保留完成段 |
| `completed` | 无需再次开始 | 播放、复制、翻译、六种导出、诊断 | 不显示“保存为笔记” |
| `partiallyFailed` | 继续、从头重试 | 显示成功文本和失败段，允许复制、翻译、导出 | SRT 只使用成功段 |
| `failed` | 从头重试 | 错误、诊断、删除 | 保留任务和可用的既有段 |
| `cancelled` | 继续或从头重试 | 保留已完成段 | 迟到回调必须被 run ID gate 丢弃 |

## 代码能力对照

| macOS 能力 | Windows 落点 | 分类 |
|---|---|---|
| `fileImporter` 与 `onDrop` 多文件导入 | WPF `OpenFileDialog`、`AllowDrop` 和统一文件校验服务 | 平台替换 |
| AVFoundation 探测、解码和窗口 WAV | 安装包内固定 x64 LGPL FFmpeg/ffprobe | 平台替换 |
| AVPlayer 播放源文件 | FFmpeg 准备音频后交给现有 NAudio/WASAPI 播放 | 平台替换 |
| 30 秒窗口、1.5 秒 overlap、200 字上下文、两次重试 | `FileTranscriptionPipeline` 保持相同常量和顺序语义 | 复刻 |
| macOS 每个任务可各自持有运行 Task | Windows `FileTranscriptionQueueService` 全局串行 | 可靠性修正 |
| macOS retry 会删除旧段 | Windows 分为“继续”和“从头重试” | 可靠性修正 |
| macOS 内存段丢失后 SRT 可能退化 | Windows 每次从 SQLite completed Segment 生成 | 可靠性修正 |
| Apple 系统全文翻译 | 复用 Windows 已配置的官方 OpenAI | 平台替换 |
| TXT、Markdown、SRT、译文 TXT、译文 Markdown、双语 Markdown | 格式和操作层级一致 | 复刻 |
| 保存为笔记 | 不实现、不显示 | 明确排除 |
| Groq 原生整文件转写 | 本期不实现、不显示 | 明确排除 |

## 数据与隐私对照

- Job 固化入队时的源路径、显示名、Provider 和识别语言；设置变化不得改写排队任务。
- Segment 按稳定索引保存起止毫秒、状态、文本、重试数、Provider 模式、fallback 和脱敏错误。
- 源文件只保存引用，不复制到应用数据目录；临时 PCM 和窗口文件属于任务专属目录。
- 日志不得包含源文件完整路径、音频内容、转写正文、翻译正文、API Key 或 Authorization。
- 云 ASR 只接收用户选中 Provider 所需的当前音频片段；OpenAI 只在用户点击全文翻译后接收文本。

## 本地化对照

Windows 资源必须同时覆盖 `en`、`zh-Hans`、`zh-Hant`、`ja`、`ko`，并保留 macOS
文案的含义和参数语义。macOS 的 Notes 文案、native-file/Groq 文案不迁移；Windows
新增“继续”“从头重试”“源文件不可用”“FFmpeg 运行时损坏”等可靠性文案。

## 视觉验收状态

以下状态必须分别在浅色和深色主题、100%、125%、150%、200% DPI 下留存基线和
Windows 对照：空态、queued、running、completed、failed、partiallyFailed、interrupted、
翻译中、翻译完成、翻译失败。

Windows 端已用 `RenderTargetBitmap` 在 1260×720、浅/深主题和
100/125/150/200% DPI 组合下生成 80 张脱敏图，并将 16×9 归一化感知签名固化到
`tests/TestResources/VisualBaselines/file-transcription-signatures.json`。CI 每次重绘并以
容差比较，同时上传 `file-transcription-visual-evidence` artifact；布局合同另外验证
380px 队列、520px 主面板、结果区、状态栏、自动化名称和禁用原因。

本次对齐依据当前 macOS `FileTranscriptionView.swift` 的结构、尺寸、状态矩阵和主题
token。当前 Windows 主机不能运行 SwiftUI，因此 macOS 原生截图采集仍必须在 macOS
主机补做；在该证据补齐前，跨平台截图验收项保持未完成，不能用 Windows 自对照冒充
macOS 实机对照。
