## Context

VoxFlow 当前由 `DictationOrchestrator` 串联录音、ASR、`TextProcessingPipeline`、`TextInjector` 和历史保存。目标应用在录音开始时通过 `WorkspaceDictationTargetProvider` 锁定；应用风格由 `SettingsBackedStyleSelector` 解析；LLM 请求 trace 已可随历史记录保存。

当前结构适合单条成功路径，但缺少跨阶段持久化、输出结果反馈和上下文生成模式：

- `DictationHistoryEntry` 只在最终注入后保存，不能表达运行中的任务。
- `TextInjector.inject` 不返回成功或失败结果，orchestrator 无法可靠记录降级。
- `ApplicationStyleClassifier` 每次只能分类一个应用，且没有扫描、预览和确认层。
- `TextProcessingPipeline` 默认遵循保守纠错约束，不适合“根据上下文生成一段新文本”。
- 当前快捷键隐含绑定单一转录动作，无法清晰承载第二种语音任务。

本 change 涉及数据迁移、录音主链、权限、剪贴板、设置和首页，必须保持以下约束：

- 现有右 Command 转录体验不可被破坏。
- 网络能力保持可选；未配置 LLM 时普通转录仍可用。
- API key 继续只保存在 Keychain。
- 不引入自动发送行为。
- 不新增不必要的三方依赖。

## Goals / Non-Goals

**Goals:**

- 用统一 VoiceTask 生命周期承载普通转录与“帮我说”。
- 让每个关键阶段可持久化、可恢复、可诊断。
- 用注册表和 LLM 推荐降低应用风格配置成本，同时保留用户最终控制权。
- 在任意前台应用中采集有界上下文，支持 Agent 式文本生成。
- 明确区分普通转录的安全注入与“帮我说”的只复制输出。

**Non-Goals:**

- 不实现微信、Slack、邮件等应用的专用解析器。
- 不自动发送消息或模拟 Enter。
- 不把“帮我说”结果自动粘贴到当前窗口。
- 不读取不可见历史或主动滚动 UI。
- 不长期保存截图。
- 不为浏览器实现域名级路由。
- 不在第一期构建完整应用知识库。

## Decisions

### Decision 1: 使用独立 VoiceTask 表，历史详情作为呈现层

新增独立 `voice_tasks` 表保存运行状态，而不是继续扩展 `dictation_history` 来模拟中间态。VoiceTask 至少包含：

- `id`、`mode`、`stage`、`status`
- 目标应用 Bundle ID、名称、PID、窗口标识和标题
- 临时音频相对路径
- 原始转写、上下文 JSON、最终文本
- 输出结果、结构化失败 JSON、处理警告和 trace
- 创建、更新时间和完成时间

完成任务可以继续生成或关联 `DictationHistoryEntry`，首页 ViewModel 将二者统一投影为详情模型。旧历史记录不反向创建完整任务，只按 `dictation/completed` 兼容展示。

**为什么：** 运行状态和历史统计的生命周期不同。独立表可避免大量 nullable 字段污染现有历史统计，并支持未完成任务查询。

**备选：扩展 `dictation_history`。** 文件更少，但会把 recording、failed、completed 等瞬时状态混入当前字符统计、活跃度和搜索语义，放弃。

### Decision 2: 在现有 orchestrator 外围引入任务协调职责

优先提取 `VoiceTaskCoordinator` 作为两种模式的统一入口，复用现有 ASR、录音和文本处理对象；`DictationOrchestrator` 可以逐步收敛为普通转录兼容层，避免一次性重写稳定主链。

协调流程：

```text
start(action)
├─ snapshot target
├─ create VoiceTask
├─ start recorder + ASR
└─ agentCompose 时并行 start ContextPipeline

release()
→ settle ASR
→ persist raw transcript
→ select processing strategy
→ persist final text
→ OutputService
→ persist terminal status
```

每个阶段更新必须幂等，以便异常恢复和重复回调不会造成非法倒退。

**为什么：** 两种模式共享录音与 ASR，但 Prompt 和输出副作用不同。协调层可以共享生命周期，又不把上下文逻辑塞进 `AudioRecorder` 或 `TextProcessingPipeline`。

**备选：在 `DictationOrchestrator` 中增加大量 mode 分支。** 初期改动较小，但会快速形成状态组合爆炸，放弃。

### Decision 3: 状态转换由纯状态机校验

VoiceTask 使用显式阶段和状态：

```text
recording
→ transcribing
→ collectingContext (可与 recording/transcribing 并行记录)
→ processing
→ outputting
→ completed | partiallyCompleted | failed | cancelled
```

数据库保存当前归一化阶段；并发上下文状态保存在 ContextSnapshot 或阶段事件中，而不是允许两个主 stage 并存。状态机负责拒绝已完成任务回退到处理中。

**为什么：** 现有 `DictationStateMachine` 已证明纯状态转换便于测试。VoiceTask 延续同一模式。

### Decision 4: 应用推荐与运行时规则分离

应用相关模型分为三层：

- `InstalledApplication`：本机扫描事实。
- `ApplicationStyleRecommendation`：注册表或 LLM 产生的临时建议，包含来源和置信度。
- `AppStyleRule`：用户确认后的运行时规则。

`ApplicationStyleRecommendationService` 先匹配 `KnownApplicationRegistry`，再将未知应用批量交给 LLM。它不直接写 `AppStyleRuleStore`。

内置注册表使用随 App 打包的静态 Swift/JSON 数据，第一期覆盖高频应用及常见 Bundle ID 变体。注册表带 schema version，便于后续更新和重置建议。

**为什么：** 事实、建议和用户决定必须可区分，避免重新扫描覆盖用户选择。

**备选：扫描后直接保存。** 交互更短，但错误分类会静默改变行为，放弃。

### Decision 5: 使用系统应用元数据扫描，不依赖 LLM 发现应用

`InstalledApplicationProvider` 从标准应用目录和用户手动选择的 `.app` 读取 `Bundle` 元数据。扫描在后台执行，结果按 Bundle ID 和规范化路径去重。图标仅用于 UI 展示，不发送给 LLM。

LLM 分类请求为严格 JSON，输入只有：

```json
{
  "name": "Obsidian",
  "bundleID": "md.obsidian",
  "systemCategory": "public.app-category.productivity"
}
```

返回值只能引用请求提供的 Bundle ID 和启用 style ID。

**为什么：** 系统扫描是确定性本地事实，LLM 只适合补全类别建议。

### Decision 6: 快捷键采用动作绑定，不强制固定手势

新增 `VoiceAction`：

- `dictation`
- `agentCompose`

现有快捷键配置迁移为 `dictation` 绑定。设置层校验触发组合是否可区分。若长按触发未占用，UI 推荐给 `agentCompose`；否则要求设置独立快捷键。

底层 `KeyMonitor` 只输出动作事件，不直接决定业务模式。

**为什么：** 用户已经可能将长按用于转录，产品不能假设某个手势永远空闲。

### Decision 7: 上下文采用结构化文本优先、视觉兜底

`ContextPipeline` 依次收集并合并：

1. 当前应用和窗口元数据。
2. 选中文本。
3. 当前输入区域的非安全文本。
4. Accessibility 树中当前窗口可见文本。
5. 当文本不足且 Provider 支持视觉时，临时当前窗口截图。

文本采集执行去重、区域约束、最大长度和来源标记。第一期不主动滚动，也不实现传统 OCR 服务；视觉内容直接作为支持多模态 Provider 的请求输入。Provider 不支持视觉时，跳过该步骤。

ContextSnapshot 持久化文本和元数据，不持久化图像。截图在单次请求结束、取消或超时后立即释放。

**为什么：** Accessibility 文本成本低且可搜索；视觉模型覆盖自绘 UI，但隐私和延迟更高，适合作为兜底。

**备选：所有应用统一截图。** 覆盖广，但每次都触发屏幕权限、成本和隐私负担，放弃。

### Decision 8: 上下文与录音并行，但使用独立超时

触发 `agentCompose` 时先同步创建任务并启动录音，然后异步采集上下文。录音启动不等待权限检查、Accessibility 遍历或截图。

上下文使用独立的短超时，目标 500ms。超时后 generation 使用当前已完成快照或无上下文继续；迟到结果不得覆盖已开始的生成请求。

**为什么：** 录音响应是核心体验，不能被不稳定的外部 UI 树阻塞。

### Decision 9: 普通纠错与 Agent 生成使用不同 Prompt Builder

保留现有 `PromptBuilder` 负责普通转录的保守纠错、术语表和应用风格。

新增 `AgentPromptBuilder`，输入：

- 当前应用和窗口信息
- 当前应用风格指导
- ContextSnapshot
- 用户完整口述

Agent Prompt 允许生成新文本，但要求：

- 忠实执行口述意图。
- 不虚构事实、人物、数字或承诺。
- 上下文不足时保守表达。
- 仅输出最终可用正文。
- coding 风格保留命令、代码、变量、路径和术语。

**为什么：** 将“只纠错”和“生成回复”混在一个 Prompt 中会产生相互冲突的约束。

### Decision 10: 输出策略按任务模式硬隔离

`OutputService` 返回结构化 `OutputResult`：

- 普通转录：目标校验成功后调用 TextInjector；失败或目标变化时写剪贴板。
- “帮我说”：直接把最终文本写剪贴板并保留，不调用 TextInjector。

TextInjector 改为返回结果，至少区分成功、权限不足、事件创建失败和取消。第一版无法从所有 App 获得“目标确实消费了粘贴”的可靠回执，因此成功语义定义为注入动作已按预期发出。

**为什么：** 模式级隔离比在 UI 层隐藏按钮更可靠，可用测试证明 Agent 路径没有键盘副作用。

### Decision 11: 首页统一展示，不增加恢复中心顶级页面

扩展现有首页历史详情模型以聚合 VoiceTask 和 DictationHistoryEntry。列表增加模式和状态标记；详情根据数据能力显示操作：

- 有最终文本：复制。
- 普通转录且目标可用：再次注入。
- 有口述且 LLM 可用：重新生成。
- 有未过期音频：重新转写。
- 任意记录：删除。

重新生成和重新转写创建新的 attempt 或更新明确的重试字段，不覆盖原始口述、旧结果和 trace。

**为什么：** 首页已有历史、搜索和详情弹窗，新增顶级页面会分裂同一批记录。

### Decision 12: 权限和安全门禁集中在 ContextPipeline

`ContextPipeline` 在采集前检查 Accessibility、屏幕录制和安全输入区域。屏幕录制权限只在用户首次真正需要视觉兜底时请求。

日志只记录阶段、耗时、来源类型、字符数和错误码，不记录上下文正文、截图或 API key。

第一期不提供复杂的逐应用上传开关；用户通过是否配置/触发“帮我说”控制上下文使用。后续若隐私反馈需要，再增加单一全局上下文开关。

**为什么：** 用户已选择简化控制，第一期避免在每个应用规则上增加多个难以理解的开关。

## Risks / Trade-offs

- [Accessibility 文本在自绘应用中为空或混乱] → 结构化文本优先但允许无上下文降级；视觉能力作为兜底，记录来源和警告。
- [视觉 Provider 能力描述不完整] → 在 Provider descriptor 增加明确 capability；没有 capability 时绝不发送图片。
- [500ms 目标不足以完成视觉请求] → 500ms 约束针对本地采集，不包含 LLM 生成；截图完成后随生成请求发送。
- [PID 和窗口标题不足以稳定识别窗口] → 尽量记录 AXWindow 标识和 bounds；无法可靠判断时采取保守策略，停止注入并复制。
- [剪贴板可能被用户快速覆盖] → 最终文本持久化到任务，首页提供再次复制。
- [独立任务表和历史表产生一致性成本] → repository 在完成事务中写任务终态和历史关联；首页允许只有任务、没有历史的失败记录。
- [批量分类 Prompt 过大] → 分批发送未知应用，设置固定批次和超时；注册表命中项不进入请求。
- [注册表随时间过期] → 注册表只作为可重置建议，用户规则优先；用版本字段支持未来更新。
- [快捷键迁移造成冲突] → 只迁移现有配置到 dictation，不自动为 Agent 分配按键。
- [保留上下文文本带来隐私风险] → 只保存裁剪后的文本，不保存截图；历史删除同步删除任务上下文。

## Migration Plan

1. 新增 SQLite migration，创建 `voice_tasks` 和必要索引，不修改现有历史数据。
2. 扩展首页查询层，使旧历史继续按 `dictation/completed` 展示。
3. 将现有快捷键配置迁移到 `dictation` action；`agentCompose` 初始为未绑定。
4. 引入 VoiceTask 持久化，但先让现有普通转录通过新协调层并完成回归。
5. 上线应用扫描、注册表和推荐预览；不自动生成规则。
6. 上线通用 ContextPipeline 和 `agentCompose`，默认无快捷键，用户主动配置后启用。
7. 最后开放视觉兜底权限请求，确保纯 Accessibility 和无上下文降级先可用。

回滚时：

- 旧版本忽略新增 `voice_tasks` 表，不影响现有历史表。
- 新快捷键设置保留旧兼容键，旧版本仍可读取原转录配置。
- 已确认 `AppStyleRule` 继续使用当前格式，避免回滚丢失规则。

## Open Questions

- Accessibility 当前窗口标识在微信、Electron、浏览器和原生应用中的稳定性，需要在实现 Phase 7 前用 Debug 工具做真实样本验证。
- 现有 LLM Provider descriptor 是否已经能够表达视觉输入能力，需要实现时确认；若没有，先增加 capability，不根据模型名称猜测。
- VoiceTask 与 DictationHistoryEntry 的最终关联采用共享 ID 还是显式 `history_entry_id`，在数据库 migration 设计时以最少改动和查询清晰度决定。
