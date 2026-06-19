# VoxFlow 剩余任务

最近整理：2026-06-19

本文是当前唯一的未完成任务入口，只记录仍需开发、核对或验证的事项。已经完成的 Groq、腾讯云、阿里云实时 ASR 实施步骤不再保留。

## 当前决策

- 暂不做 Agent/MCP。
- `STAB-009` 升级迁移继续延后。
- 云端 Provider 用于文件转写时，暂不接各厂商独立的录音文件识别接口；继续复用当前 ASR 运行时。腾讯云 `CreateRecTask`、阿里云录音文件识别等上传/轮询方案本轮不做。
- 火山云保持“暂未支持”，是否继续实现由后续需求决定。
- Mistral、AssemblyAI、ElevenLabs 保持置灰，不开放配置或运行时选择。
- 云端 ASR 凭据按当前产品决策保存到本地 SQLite 设置表，不写入仓库、日志、测试 fixture 或 UserDefaults。

## P0 文档与隐私说明

### DOC-001：同步英文 README

Status: `todo`

- 补充 Groq（免费）、腾讯云、阿里云、火山云及暂未支持 Provider 的状态表。
- 修正 `Groq Whisper` 和“API Key 全部存储到 Keychain”等旧描述。
- 与中文 README 的本地模型、在线模型、流式能力和配置项保持一致。

### DOC-002：修正隐私文档

Status: `todo`

- 把数据库路径更新为 `~/Library/Application Support/VoxFlow/voxflow.sqlite`。
- 按实际代码说明 LLM Key 与云端 ASR 凭据的存储位置。
- 明确 Groq、腾讯云、阿里云启用后会上传音频。
- 核对上下文截图、诊断 trace、日志脱敏和数据清理入口是否与代码一致。

## P1 火山云

### ASR-VOLC-001：决定是否继续接入

Status: `blocked`

当前只有 Registry 占位，没有 runtime、配置 UI 或真实联调。继续前需要用户确认仍要支持火山云。

确认继续后再做：

- 用官方文档核对 WebSocket endpoint、鉴权 header、凭据字段、音频分片和响应结构。
- 实现独立 Provider target、client、streaming engine、设置存储与错误脱敏。
- 增加 mock 测试和默认跳过的真实联调测试。
- 使用测试凭据完成一次真实短音频调用。

## P2 文件转写

### FILE-ASR-001：记录并固定实际 Provider

Status: `todo`

当前任务入库时把 `asrProviderID` 写成 `apple_speech`，执行时却忽略该值并读取当时有效的 ASR 引擎。历史记录因此无法说明实际使用了哪个模型，重试前切换模型还会改变执行 Provider。

- 入队或开始执行时记录真实 Provider ID。
- 明确重试是沿用原 Provider，还是使用当前选中 Provider；在 UI 中展示该决策。
- 增加数据库和 ViewModel 行为测试。

### FILE-ASR-002：识别语言不要在页面创建时冻结

Status: `todo`

当前文件转写 worker 在 ViewModel 初始化时捕获语言。页面打开后切换识别语言，已有 worker 不会更新。

- 在任务开始时读取当前语言，或把语言作为任务快照保存。
- 增加切换语言后开始/重试的测试。

### FILE-ASR-003：文件专用云接口

Status: `deferred`

本轮不接腾讯云、阿里云等厂商的录音文件识别专用 API，也不增加上传、异步轮询或对象存储流程。只有用户重新明确要求时再恢复评估。

## P3 运行时与交互收口审计

以下代码已有实现和测试雏形，但不能仅凭旧任务状态认定完整。先做代码审计，确认缺口后再决定是否修改。

### REVIEW-001：Session 与迟到事件

Status: `audit-required`

- 核对 HUD、ASR、OCR、输出和 delayed hide 是否都携带同一 session/generation。
- 核对取消、切换任务和窗口延迟回调是否会串线。
- 优先补行为测试，不为统一命名做无收益重构。

### REVIEW-002：Hotkey 与 workflow 边界

Status: `audit-required`

- 核对 Option、Command、`Command+Shift+V`、Escape 的仲裁入口。
- 核对听写、帮我说、剪贴板 OCR、视觉 OCR 是否拥有独立生命周期。
- 保持 `Control+Shift+V` 交给系统或前台应用。

### REVIEW-003：输出与剪贴板

Status: `audit-required`

- 成功注入后不得额外复制 final；注入失败才 fallback copy。
- Agent Compose copy-only 不得覆盖普通听写 last result。
- OCR、粘贴上次结果、复制结果保持独立动作。

### REVIEW-004：模型 readiness 与 fallback

Status: `audit-required`

- Settings、菜单和 hotkey start 对模型可用性的判断必须一致。
- 本地模型删除、目录丢失或校验失败后，不得继续显示可用或误选其他本地模型。
- Apple Speech fallback 必须有明确可见状态。

## P4 隐私与上下文

### PRIV-001：默认 trace 元数据化

Status: `audit-required`

- 用数据库 fixture 验证默认不保存 raw prompt、窗口正文、dictation、source snippets 或 full response。
- 若诊断模式会保存原始内容，确认有显式开关、留存上限和删除入口。

### PRIV-002：Agent Compose 不可信上下文边界

Status: `in-progress`

- window text、selected text、code 和用户 dictation 只能进入 user content。
- system prompt 保持固定且只包含 policy。
- 用户 dictation 只出现一次，边界必须结构化或可靠转义。
- 增加 prompt-boundary spoofing snapshot 测试。

### PRIV-003：Context timeout 与 HUD 延迟

Status: `in-progress`

- hotkey start 不得被 Accessibility、截图或权限检查阻塞。
- HUD 先显示，context 后台收集；超时后回退 dictation-only。
- 迟到 context 必须按 session 丢弃。
- 增加可重复的 hotkey-to-HUD latency 验证。

## P5 最终门禁

### VERIFY-001：代码门禁

Status: `todo`

代码任务完成后依次运行：

1. `swift test`
2. `make debug`
3. `make build`
4. `git diff --check`

报告必须区分单元/mock 测试、真实云调用、静态检查和手工 UI 验证。

### VERIFY-002：真实调用状态

Status: `in-progress`

- Groq：已有真实短音频调用记录。
- 腾讯云：已有真实实时 WebSocket 短音频调用记录。
- 阿里云：已有真实 DashScope WebSocket 短音频调用记录。
- 火山云：未实现、未真实联调。
- 文档整理后无需重复调用云服务；只有修改对应 runtime 时才重新联调。

## 不再列为剩余任务

- Groq、腾讯云、阿里云的当前实时/缓冲云端 ASR 路线已经实现并有测试及真实调用记录。
- Mistral、AssemblyAI、ElevenLabs 已按要求排在在线列表末尾并置灰。
- `Command+Shift+V` 剪贴板图片 OCR 已实现。
- Qwen3 0.6B / 1.7B 已统一到 speech-swift 路线。
