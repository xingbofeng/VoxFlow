## 背景

Windows V1 的实际实现位于工作树
`/mnt/c/Users/Administrator/.config/superpowers/worktrees/VoxFlow/feat-windows-v1-dictation`
及分支 `feat/windows-v1-dictation`。它已具备 WPF Shell、主题 token、SQLite/DPAPI、`VoxFlowStateStore`、Qwen、腾讯云、阿里云、火山引擎、OpenAI 和 NAudio/WASAPI；尚无文件转写页面、任务表、媒体准备或文件 Provider 适配。

macOS 的 `FileTranscriptionView`、`FileTranscriptionViewModel`、`VoxFlowFileTranscriptionPipeline` 与 `TranscriptionJobRepository` 是本变更唯一的产品和算法基线。Windows 不复制 SwiftUI 或 AVFoundation 代码；必须重建同等可观察行为，并以 macOS 当前页面的布局、状态、交互、文案语义、主题 token、间距、圆角、空态与错误态作为视觉验收基线。

macOS 现有产品行为包括：

- 导入/拖放多份 MP3、WAV、M4A、AAC、MP4、MOV，创建持久化任务；
- 以入队时的 ASR Provider 和识别语言处理任务；
- 30 秒窗口、1.5 秒重叠、最近 200 字符上下文、空结果/重复/Provider 错误最多重试两次；
- 队列、进度、取消、删除、重试、分段诊断、播放、复制、导出和全文翻译；
- TXT、Markdown、SRT、译文 TXT/Markdown、双语 Markdown 导出；
- 转写与翻译状态独立，翻译失败不破坏原始结果。

本设计保留上述能力，并明确修复 macOS 目前的三项可靠性缺口：文件任务全局串行、继续未完成任务保留完成段、SRT 永远从数据库段记录导出。

## 目标与非目标

**目标：**

1. 在 Windows 工作树的 `VoxFlow.Windows/` 中交付可恢复的本地文件转写闭环，而不改 macOS 行为。
2. 让 Windows 文件转写页面与当前 macOS `FileTranscriptionView` 视觉和交互对齐，而不是使用默认 WPF 控件拼装一个功能近似页。
3. 使用受控 FFmpeg x64 运行时覆盖 macOS 当前支持的音视频容器，并对每个转换、临时文件与子进程建立取消、清理、日志脱敏和安装器契约。
4. 复用现有 Qwen/云 ASR/OpenAI/SQLite/主题/Shell 分层，Provider 不感知页面和数据库，Domain 不感知 WPF、FFmpeg 或具体 Provider。
5. 保证崩溃、取消、源文件缺失、单段失败、Provider 错误、OpenAI 翻译失败后有确定且可恢复的用户可见结果。

**非目标：**

- 不新增 Groq、Whisper、FunASR、系统语音识别或任何新 ASR Provider；首期所有可用 Windows Provider 统一走分段输入。
- 不新增 Notes、保存为笔记、摘要、Agent、OCR、截图、字幕烧录、视频渲染、逐字级对齐或逐句人工编辑器。
- 不上传文件、音频、转写或诊断到 VoxFlow 自有服务；选中云 ASR 或用户显式点击全文翻译时，只有处理所需音频片段或文本发送给该用户选定的第三方服务。
- 不支持 ARM64、GPU/CUDA、Python、WSL、系统 PATH 中未审计的 ffmpeg、自动 Provider fallback 或后台常驻转码服务。

## 决策

### 1. 以 macOS 页面为视觉与行为唯一基线

Windows 新增 `FileTranscription` Shell route、导航项、ViewModel、View 与 presentation model。页面结构必须复刻 macOS：顶部标题/副标题和导入按钮、带格式提示的拖放区、左侧任务队列、右侧结果/详情、任务操作区、可折叠高级诊断、底部状态栏。任务卡、状态颜色/图标、进度、空态、确认删除、翻译前后对比、导出操作及禁用规则均以 `FileTranscriptionView.swift` 当前行为为准。

WPF 实现继续使用 Windows V1 的 `Theme.xaml`、自定义控件模板、主题切换与 DPI 策略；不得引入视觉框架覆盖现有 token。视觉验收固定在 1260×720 的基准窗口以及 100/125/150/200% DPI，逐项对照 macOS 页面：左右栏比例、标题、卡片层级、边距、圆角、字体层级、浅/深主题、空态、运行态、失败态和部分失败态。Windows 字体仍使用 Segoe UI；字体差异不构成允许改变布局密度的理由。

替代方案：使用“功能相同即可”的新 WPF 页面。拒绝，因为上一期已将 macOS 视觉与交互定义为 Windows 产品基线，会造成路由和工作台体验断裂。

### 2. 文件任务与分段成为独立的可持久化领域

新增 `FileTranscriptionJob`、`FileTranscriptionSegment`、`FileTranscriptionJobStatus`、`FileTranscriptionSegmentStatus`、`FileTranscriptionProviderMode`、`SegmentFallbackReason` 和导出格式值对象。Job 保存原始文件绝对路径、显示文件名、入队时 Provider ID、识别语言、进度、原文、最终文本、时长、错误、翻译字段和时间戳；Segment 保存稳定索引、起止毫秒、状态、文本、重试数、Provider/模式、fallback 与错误。

SQLite 新增 `file_transcription_jobs`、`file_transcription_segments` 及按创建时间、任务状态、任务/段索引、任务/段状态查询的索引。迁移在既有 `VoxFlowDatabaseMigrator` 中以幂等方式追加；删除 Job 必须级联删除 Segment。源文件仅保存引用，不复制进应用数据目录；源文件被移动、删除或无权限时，继续/重试必须变为可读的“源文件不可用”失败，不得清空既有成功段和文本。

替代方案：把文件转写塞进 dictation history。拒绝，因为听写历史是已完成文本记录，文件任务需要中断、段、恢复、Provider 固化和长时运行生命周期。

### 3. 单一串行调度器与真正恢复

`FileTranscriptionQueueService` 位于 Application，只允许一个 Job 进入运行态；多选导入按用户选择顺序入队，当前 Job 完成、取消、失败或部分失败后才开始下一个 queued Job。每次运行生成 run ID，所有进度、段回调和终态更新都必须经 run ID gate，防止取消或重试后的迟到回调覆写新状态。

启动时，所有 `running` Job 与其 `running` Segment 标为 `interrupted`，保留 completed Segment。页面为 interrupted/partiallyFailed Job 显示“继续”操作；继续时读取已完成 Segment，跳过对应窗口，只转写未完成或失败段。显式“从头重试”才删除旧 Segment、清空全文与翻译结果。取消保留已完成段但不自动继续；删除立即取消并级联删除记录。

这有意不同于 macOS 当前的 `retry` 行为：macOS pipeline 本身能复用完成段，但 UI retry 会清理它们。本变更以可靠恢复为产品要求，不把该缺口移植到 Windows。

### 4. FFmpeg 作为受控媒体准备运行时

新增 `IFileMediaPreparer` 与 `FfmpegFileMediaPreparer`。后者只从安装器部署的 `VoxFlow.Windows/runtime/ffmpeg/` 读取固定版本 x64 `ffmpeg`/`ffprobe`，启动前核对清单版本、文件大小和 SHA-256；不得调用用户 PATH、下载临时二进制或启动常驻服务。

媒体流程如下：

```text
源文件
  -> ffprobe 验证格式、首条音轨和总时长
  -> ffmpeg 提取/解码为临时 16 kHz 单声道 PCM WAV
  -> 计算 30s / 1.5s 重叠窗口
  -> ffmpeg 生成当前窗口临时 WAV
  -> Provider 分段会话
  -> 删除当前窗口；任务结束删除准备文件
```

FFmpeg 进程必须使用参数数组、无 shell 拼接、隐藏窗口、标准输出/错误受限读取、取消时终止整个进程树。诊断只记录格式、时长、退出码和脱敏类别，不能写入原始命令行中的用户路径、音频内容、转写或凭据。播放操作复用同一媒体准备路径，使用现有 NAudio/WASAPI 输出已解码临时音频；重新打开已完成任务时可按需重新准备，不能依赖易失内存缓存。

首期锁定 FFmpeg LGPL 构建；变更必须记录来源 revision、构建配置、许可证、notice、SHA-256、安装器复制清单和发布检查。若唯一可获得构建包含 GPL-only 组件，必须在实施前更新许可证决策和 notices，不能静默替换。

替代方案：Windows Media Foundation。拒绝，因为 MOV 和跨编码组合的行为不能与 macOS AVFoundation 的现有格式承诺稳定对齐。替代方案：调用用户机器上的 ffmpeg。拒绝，因为不可复现、存在 PATH 劫持和发布不可验证问题。

### 5. 复刻 Swift 分段算法，Provider 统一走文件帧适配

`FileTranscriptionPipeline` 在 Application 中保持纯协调：每个窗口为 30,000 ms，下一窗口起点按 28,500 ms 推进；按索引顺序串行处理；最近 200 字符作为 Provider prompt context；相邻上下文最多移除 30 字符重叠；空结果、完全重复、Provider 错误各最多额外尝试两次。所有成功段合并为全文，失败段不伪造文本；Job 在至少一个成功段和至少一个失败段时为 `partiallyFailed`。

新增 `IFileTranscriptionWorker`，将准备好的 WAV 以现有统一 PCM16 帧契约输入当前选中 Provider。Qwen、腾讯、阿里、火山各自实现/复用 Session adapter；它们只产生统一 partial/final/error，不能自动切换到其他 Provider。任务入队时固定 Provider/语言，之后修改设置不得影响已排队任务。当前 Windows 没有 Groq，故没有 native whole-file 快捷路径；将来新增 Groq 时才可在不改任务/UI 契约的前提下加入 `NativeFile` strategy。

### 6. 翻译与导出独立于转写终态

`IFileTranscriptionTranslator` 复用现有官方 OpenAI 设置、DPAPI 凭据和 `OpenAiChatCompletionsClient`，但使用专用翻译 prompt。用户点击“全文翻译”后，Job translation 状态经历 pending/running/completed/failed；页面保持 macOS 的按钮、spinner、原文/译文对比和错误反馈。未配置、禁用、取消、HTTP/SSE/空结果/模型错误时，必须保留原文与转写状态，不自动选择其他模型或 Provider。

导出由 `FileTranscriptionExportService` 负责：TXT、Markdown、SRT、译文 TXT、译文 Markdown、双语 Markdown。SRT 必须每次从 `file_transcription_segments` 中按 `segment_index` 读取 completed Segment，使用持久化 `start_ms/end_ms`；部分失败 Job 只导出完成段并保留页面的失败摘要。禁止从 ViewModel 内存列表或平均分配时长生成字幕。

不实现“保存为笔记”，因为 Windows V1 明确没有 Notes 域；页面不显示占位按钮。

### 7. 组合根、状态投影与本地化

Composition Root 为队列、SQLite repository、FFmpeg media preparer、Provider worker factory、OpenAI translator、播放服务和 WPF ViewModel 注入接口。`VoxFlowStateStore` 增加只读的文件任务摘要，供 Home、路由、状态栏和托盘在不直接持有 Job repository 的前提下反映运行任务；托盘不新增转写开始入口。

所有用户可见文字使用 Windows 本地化资源，并同步 en、zh-Hans、zh-Hant、ja、ko 五种语言。术语、格式提示、状态、错误、按钮和诊断摘要以 macOS 对应 `transcribe.*` key 的语义为准，不允许直接显示资源 key 或拼接式半翻译。

## 风险与权衡

- [FFmpeg DLL/可执行文件增大安装包并带来许可证义务] → 固定 x64 LGPL 构建、生成清单与 SHA-256、安装器 notices、发布前依赖和许可证检查。
- [长文件临时 PCM 占用大量磁盘] → 导入前估算可用空间；准备/窗口文件使用任务专属临时目录；取消、失败、完成、启动清理和卸载均覆盖陈旧临时文件。
- [云端按时长/请求收费且长文件易超时] → 串行 30 秒片段、清晰 Provider/网络错误、可继续未完成段、显式 live smoke；禁止自动 fallback 或重复整文件重试。
- [Provider 对高速文件帧喂入与实时麦克风不同] → 以固定 WAV 为每个 Provider 建立协议/节流/finish/取消测试；不通过的 Provider 显示文件转写不可用，不伪造成功。
- [源文件移动导致恢复失败] → 保存路径但每次运行前验证；已有文本可复制/导出，未完成段提示重新定位或从头导入，不删除已有记录。
- [macOS 与 Windows 字体/控件渲染不同] → 使用共同 token、固定窗口/DPI 图像基线和人工逐项对照；不以系统默认控件替代定制模板。
- [OpenAI 翻译可泄露用户文本] → 仅显式点击触发、沿用配置页的第三方发送说明和 DPAPI、日志脱敏、失败回退原文。

## 迁移与回滚

1. 在 Windows 数据库 migrator 中新增幂等表、索引和版本；旧 V1 数据库升级不删除现有 settings/history/models/credentials。
2. 首次启动只创建空表，不扫描用户磁盘、不自动导入媒体、不自动调用 Provider 或 OpenAI。
3. 安装器新增 FFmpeg runtime 和 notices；升级时原子替换 runtime，失败时保留上一完整安装，不能留下半套 DLL。
4. 回滚应用版本时，旧版本忽略新增表；删除 P3 功能不删除用户的源文件或导出文件。应用数据删除由现有安装器的显式选项控制。
5. P3 只能在 `feat/windows-v1-dictation` 合并/继续后的 Windows 工作树实施；不得在 macOS 目标中引入 FFmpeg 或 WPF 依赖。

## 未决问题

- 无产品范围未决项。FFmpeg 的具体上游发行 revision、SHA-256 和 LGPL 构建产物在实施的供应链锁定任务中确定，未锁定前不得开始打包或发布。
