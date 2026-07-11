## 1. 工作树接入与 macOS 基线固定

- [x] 1.1 在 `feat/windows-v1-dictation` 工作树确认 Windows V1 当前提交、未提交改动和可运行测试基线；不得覆盖正在进行的 V1 文件
- [x] 1.2 为当前 macOS `FileTranscriptionView`、`FileTranscriptionViewModel`、`VoxFlowFileTranscriptionPipeline` 和本地化 key 建立 Windows P3 对照表，逐项标记复刻、平台替换或明确排除
- [ ] 1.3 从 macOS 100/125/150/200% 浅色与深色状态采集经批准的文件转写视觉基线，覆盖空态、queued、running、completed、partiallyFailed、interrupted 和翻译对比
- [x] 1.4 为 Windows P3 新增的 FFmpeg、NAudio 扩展和测试依赖更新许可证清单规则、第三方 notices 模板和发布前检查输入
- [x] 1.5 编写 P3 架构依赖失败测试，验证 Domain 不引用 WPF、SQLite、FFmpeg、NAudio 或 Provider 实现，Application 不引用 WPF 和具体进程 API

## 2. 领域模型、SQLite 迁移与 Repository

- [x] 2.1 先为文件任务状态、分段状态、Provider 模式、fallback 原因、翻译状态和导出格式写 Domain 序列化/非法状态失败测试
- [x] 2.2 实现不可变 `FileTranscriptionJob`、`FileTranscriptionSegment` 与值对象，使 Domain 测试通过
- [x] 2.3 先为 `file_transcription_jobs` 和 `file_transcription_segments` 的列、索引、外键级联和幂等迁移写 SQLite schema 失败测试
- [x] 2.4 在 `VoxFlowDatabaseMigrator` 中增加幂等迁移、表、索引和升级路径，使全新数据库与 V1 已存在数据库测试通过
- [x] 2.5 先为 Job repository 的创建、按顺序列出、Provider/语言快照、状态更新、翻译字段和源路径保留写失败测试
- [x] 2.6 实现 `SqliteFileTranscriptionJobRepository`，使 Job CRUD 与翻译持久化测试通过
- [x] 2.7 先为 Segment repository 的稳定索引 upsert、按索引读取、状态更新、级联删除和 running→interrupted 写失败测试
- [x] 2.8 实现 `SqliteFileTranscriptionSegmentRepository`，使 Segment CRUD、恢复和级联测试通过
- [x] 2.9 为任务已存在但源文件移动/删除/拒绝访问的可读错误和既有结果保留写失败测试，再实现源文件可用性探测契约

## 3. FFmpeg 运行时、媒体探测与临时文件安全

- [x] 3.1 选择并锁定 x64 LGPL FFmpeg/ffprobe 上游 revision、构建来源、许可证、notice、文件大小和 SHA-256，写入 `VoxFlow.Windows/THIRD-PARTY-NOTICES.md` 与受控 manifest
- [x] 3.2 先为 FFmpeg runtime 路径固定、版本/大小/哈希校验、拒绝 PATH 查找、拒绝非 x64 二进制写失败测试
- [x] 3.3 实现 `FfmpegRuntimeVerifier` 与受控 runtime locator，使供应链测试通过
- [x] 3.4 先为参数数组执行、隐藏窗口、受限 stdout/stderr、退出码映射和不记录敏感路径/文本的进程执行器写失败测试
- [x] 3.5 实现可取消的 `FfmpegProcessRunner`，取消时终止整个进程树，使进程契约测试通过
- [x] 3.6 先为 MP3、WAV、M4A、AAC、MP4、MOV 的 ffprobe 时长/首音轨探测和无音轨视频失败写 fixture 测试
- [x] 3.7 实现 `FfmpegFileMediaPreparer` 的探测和 16 kHz 单声道 PCM WAV 准备，使格式测试通过
- [x] 3.8 先为 30,000 ms 窗口、28,500 ms 步长、1,500 ms overlap、末段截断和毫秒边界写失败测试
- [x] 3.9 实现 FFmpeg 窗口 WAV 切片服务，使时间窗测试通过
- [x] 3.10 先为磁盘空间预检、任务专属临时目录、完成/失败/取消/删除/重启清理和源文件绝不删除写失败测试
- [x] 3.11 实现临时文件生命周期与陈旧目录清理，使清理测试通过
- [x] 3.12 先为播放/暂停源音频、视频音轨播放失败不影响任务状态写失败测试，并以受控解码结果接入现有 NAudio/WASAPI 输出

## 4. 分段流水线、Provider Worker 与串行调度

- [x] 4.1 先为完成段复用、最近 200 字符上下文、最多 30 字符 overlap 去重、空结果/重复/Provider 错误各重试两次写 pipeline 失败测试
- [x] 4.2 实现纯 Application `FileTranscriptionPipeline`、窗口合并和段级事件，使算法测试通过
- [x] 4.3 先为 Qwen、腾讯、阿里、火山任务入队时 Provider/语言固化、统一 PCM16 帧、finish、取消和不自动 fallback 写失败测试
- [x] 4.4 实现 `IFileTranscriptionWorker` 及四个 Provider 的文件分段适配，使现有 Session contracts 复用并通过
- [x] 4.5 为 Provider 不可用、云端鉴权/配额/格式错误、Qwen 未就绪和段超时的可读映射写失败测试
- [x] 4.6 实现 Provider 可用性策略和错误映射；当前 Windows 不得暴露 Groq/native-file 模式
- [x] 4.7 先为全局一次仅一个 running Job、多选按入队顺序自动启动和重复点击不创建第二会话写失败测试
- [x] 4.8 实现 `FileTranscriptionQueueService`、Job run ID gate 和串行调度，使并发测试通过
- [x] 4.9 先为取消、删除、从头重试和迟到 segment/progress/final 不能覆写当前状态写失败测试
- [x] 4.10 实现取消、删除、从头重试、run ID gate 和已完成任务推进，使生命周期测试通过
- [x] 4.11 先为启动时 running→interrupted、completed Segment 保留、继续只处理未完成段和从头重试才删除旧段写失败测试
- [x] 4.12 实现恢复/继续路径和部分失败聚合，使崩溃恢复测试通过
- [x] 4.13 先为 `VoxFlowStateStore` 文件任务摘要投影与 Home/状态栏一致性写失败测试，再实现只读投影

## 5. 翻译、复制与导出

- [x] 5.1 先为复制 completed/partiallyFailed 最终文本、无结果禁用和剪贴板失败反馈写失败测试
- [x] 5.2 实现文件任务复制操作，使现有 Windows 剪贴板契约测试通过
- [x] 5.3 先为 TXT、Markdown、译文 TXT、译文 Markdown、双语 Markdown 的内容、文件名净化和译文缺失错误写失败测试
- [x] 5.4 实现 `FileTranscriptionExportService` 和保存对话框适配，使文本导出测试通过
- [x] 5.5 先为 SRT 从持久化 completed Segment 按索引读取、毫秒格式、部分失败跳过失败段和应用重启后保持时间戳写失败测试
- [x] 5.6 实现持久化 Segment 驱动的 SRT 导出，使重启回归测试通过
- [x] 5.7 先为显式 OpenAI 翻译、pending/running/completed/failed、取消、空结果、HTTP/SSE 错误保留原文写失败测试
- [x] 5.8 实现 `IFileTranscriptionTranslator`，复用固定官方 OpenAI 设置、DPAPI 和 Chat Completions client，使翻译测试通过
- [x] 5.9 先为未配置 OpenAI、翻译失败不改变转写状态、译文成功后的双语导出写失败测试并验证通过

## 6. WPF 页面与 macOS 一比一视觉对齐

- [x] 6.1 先为新增文件转写 Shell route、导航顺序、无截图/OCR/Notes/Agent 占位入口写失败测试
- [x] 6.2 实现 `FileTranscriptionView`、ViewModel 和路由组合，使 Shell 测试通过
- [x] 6.3 先为顶部标题/副标题/浏览按钮、支持格式拖放区、多选导入、空态和 macOS 同语义反馈写 ViewModel 与 UI 合同测试
- [x] 6.4 实现导入、拖放、格式拒绝和队列创建 UI，使合同测试通过
- [x] 6.5 先为左侧队列、右侧详情、任务卡状态图标/颜色/进度、状态栏、启动/取消/继续/从头重试/删除确认写失败测试
- [x] 6.6 实现队列与详情操作面板，使用户操作和任务状态测试通过
- [x] 6.7 先为结果选择、播放/暂停、复制、导出、翻译 spinner、原文/译文对比和高级诊断折叠写失败测试
- [x] 6.8 实现结果详情、导出菜单、翻译对比和段级脱敏诊断，使合同测试通过
- [x] 6.9 先为浅/深主题、1260×720、100/125/150/200% DPI 下的布局 token、导航、空态、运行态、失败态、部分失败态和翻译态写 RenderTargetBitmap/感知差异失败测试
- [x] 6.10 按 macOS 视觉基线实现/调整 XAML 模板、资源、间距、圆角、字体层级和控件禁用态，使视觉回归通过
- [x] 6.11 为 en、zh-Hans、zh-Hant、ja、ko 新增完整本地化资源及占位符一致性检查；不得提交 key 回显或拼接式文案
- [x] 6.12 为键盘焦点、可访问名称、操作禁用原因和错误反馈写自动化树测试并实现

## 7. 安装、质量门禁与验收证据

- [x] 7.1 将锁定的 FFmpeg runtime、manifest、许可证和 notices 加入 x64 publish/安装器布局，先写缺失/多余/错误架构失败测试
- [x] 7.2 实现安装器与发布检查，验证不从 PATH 取 FFmpeg、无 Python/WSL/CUDA/MLX 依赖且卸载策略符合 V1
- [x] 7.3 扩展 secret/隐私扫描，验证音频、转写、源路径、OpenAI/云凭据和 FFmpeg 命令敏感参数不进入日志、fixture 或发布产物
- [x] 7.4 为每个 Provider 建立离线固定 WAV 文件转写测试，覆盖 Qwen/腾讯/阿里/火山的成功、finish、取消、超时和无自动 fallback
- [x] 7.5 编写显式本机 live smoke，使用私有环境变量和无个人信息短音频验证云 Provider 文件转写；CI 默认跳过
- [ ] 7.6 在 Windows 10 1809 x64 与当前支持主机执行 MP3、WAV、M4A、AAC、MP4、MOV 的导入/取消/继续/从头重试/翻译/六种导出手工验收并保存脱敏证据
- [ ] 7.7 执行 macOS 与 Windows 文件转写页的浅/深主题、四档 DPI 视觉对照，逐项记录差异及修复证据
- [x] 7.8 运行所有 Windows 离线测试、x64 Debug/Release 构建、安装布局检查、许可证检查、secret 扫描和 `openspec validate --strict`
