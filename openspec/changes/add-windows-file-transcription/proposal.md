## 为什么

Windows V1 已具备听写、ASR Provider、OpenAI、SQLite 和 WPF 工作台基础，但用户仍无法把已有的录音、访谈、会议音频或视频导入并转成可复用文本。macOS 已有一套成熟的文件转写产品语义；现在需要在同一 Windows 工作树中复刻其可见体验与核心行为，而不是再设计一个简化版导入工具。

这项能力必须在 Windows V1 的既有分层上实现：长文件能可靠分段、取消、恢复和导出；Windows 页面在布局、状态、层级、文案语义和交互上以当前 macOS `FileTranscriptionView` 为唯一基线。

## 变更内容

- 在 `feat/windows-v1-dictation` 工作树的 `VoxFlow.Windows/` 中新增文件转写领域模型、SQLite 任务/分段存储、单任务串行队列和崩溃恢复机制。
- 支持导入、拖放和多选 MP3、WAV、M4A、AAC、MP4、MOV；任务保存入队时选定的 ASR Provider、源文件路径、状态、分段进度、错误和结果。
- 使用随安装包分发并记录许可证的 FFmpeg 运行时完成音频探测、音轨提取、解码、规范化和临时切片；不依赖 Python、WSL、CUDA、MLX、服务端或系统私有媒体框架。
- 复刻 macOS 的长文件策略：30 秒窗口、1.5 秒重叠、顺序转写、最近 200 字符上下文、重复片段裁剪、每段最多两次重试和部分失败结果。
- 将现有 Windows Qwen、腾讯云、阿里云 DashScope、火山引擎作为文件转写的分段 Provider；不在本变更中新增 Groq 或把任一 Provider 伪装成原生整文件接口。
- 新增与当前 macOS 文件转写页视觉和交互对齐的 WPF 页面：左侧队列、右侧结果、导入/拖放、启动、取消、继续、重试、删除、播放、复制、导出、分段诊断、状态栏和全文翻译入口。
- 新增 TXT、Markdown、SRT、译文 TXT、译文 Markdown、双语 Markdown 导出；SRT 必须始终从 SQLite 持久化的分段时间戳生成，应用重启后不能退化为单段字幕。
- 全文翻译复用 Windows 已配置的官方 OpenAI Provider；翻译独立于转写状态，失败时保留原始转写。首期不新增笔记、摘要、字幕烧录或翻译设置页。
- 修正 macOS 当前实现中的三个可靠性缺口：全局单任务串行而非可手动并发、显式“继续未完成任务”而非重试时丢弃已完成段、重启后仍以持久化段导出准确 SRT。

## 能力

### 新增能力

- `windows-file-transcription-jobs`：文件转写任务、分段、串行调度、取消、恢复、重试、Provider 固化和 SQLite 持久化。
- `windows-file-transcription-media`：基于 FFmpeg 的受控媒体探测、音轨准备、临时分段、清理、播放和格式错误处理。
- `windows-file-transcription-workbench`：与 macOS 文件转写页对齐的 WPF 路由、布局、队列、详情、诊断与用户交互。
- `windows-file-transcription-output`：复制、TXT/Markdown/SRT/翻译导出，以及复用 OpenAI 的全文翻译与失败隔离。

### 修改的能力

- 无。文件转写作为 Windows V1 之后的新页面和新任务域引入；既有听写、截图、OCR、笔记、任务助手和 Provider 配置的需求不改变。

## 影响

- 代码落点为 Windows 工作树中的 `VoxFlow.Windows/src/`、`VoxFlow.Windows/tests/`、`VoxFlow.Windows/installer/`、`VoxFlow.Windows/docs/`；本变更不修改 macOS 产品行为。
- 新增 FFmpeg 静态或受控动态运行时、版本锁定、SHA-256、许可证/归属、安装器复制和发布前依赖扫描；不得把未审计的系统 PATH 可执行文件当作产品依赖。
- 扩展现有 `VoxFlowDatabaseMigrator`、`VoxFlowStateStore`、OpenAI 客户端、云 ASR/Qwen Provider 抽象和 WPF Shell 路由；Domain 不得引用 WPF、FFmpeg、SQLite 或 Provider 具体实现。
- 需要新增离线单元/组件/WPF 测试、FFmpeg 受控 fixture、安装布局检查和明确启用的本机 Provider smoke；CI 不读取真实凭据、不上传文件或转写内容。
