## Agent Compose 上下文采集与快捷键冲突修复 - 2026-06-14

**目标**：修复真实微信、Chrome/Google 等应用中 Agent Compose 只有窗口元数据、没有可见文本上下文的问题，并处理历史配置里听写与 Agent Compose 同键导致的路由歧义。

**设计决策**：Accessibility 文本采集从 focused element 扩展到 focused window/visible windows 的 AX 树遍历，收集 title、value、description、help、placeholder，并过滤噪声、去重、限长；这样在不支持截图视觉模型时仍能从微信会话和 Google 页面获得可见文本。快捷键初始化时检测 dictation 与 agent compose 同键，保留默认听写 Command，清除冲突的 Agent Compose 绑定；事件路由也优先匹配听写，兼容历史用户默认用法。

**偏差说明**：自动化环境无法稳定合成“仅按住 modifier 键”的真实硬件事件，所以未把外部应用中的热键触发作为自动化断言；验证重点放在真实前台应用的上下文采集、任务路由和 Agent Compose prompt/trace 行为。未对真实微信可见内容发起 LLM 调用，避免把私人聊天上下文传给外部模型。

**权衡分析**：
- 方案一：继续只读 focused element。优点是实现简单、权限面小；缺点是微信和搜索页面经常拿不到正在看的上下文，Agent 只能回答“请告诉我具体内容”。
- 方案二：遍历当前窗口 AX 树并做摘要。优点是适用于通用应用上下文；缺点是需要深度、节点数和文本预算限制，避免过慢或采集过多无关 UI 文案。
- 选择方案二，因为 OpenSpec 的 Agent Compose 目标是面向任意前台应用理解上下文，而不是只处理输入框文本。

**验证结果**：
- `swift test`：442 项通过，4 项按默认环境跳过。
- `VOICEINPUT_LIVE_CONTEXT=1 swift test --filter LiveContextPipelineTests`：真实运行中的微信和 Chrome 均采集到可见文本上下文。
- 打开 `https://www.google.com/search?q=voiceinput%20context%20test` 后运行 `VOICEINPUT_LIVE_CONTEXT=1 swift test --filter LiveContextPipelineTests/testCollectsVisibleTextFromRunningChromeWhenEnabled`：Google 搜索页上下文采集通过。
- `swift test --filter 'ContextPipelineTests|AgentPromptBuilderTests|ContextAwareWorkflowIntegrationTests|AgentComposeTests|OutputServiceTests|VoiceActionBindingTests|KeyMonitorTests'`：66 项通过，覆盖 AX 摘要、Agent prompt、copy-only 输出、快捷键冲突清理与路由。
- `swift build -c debug -Xswiftc -warnings-as-errors`、`make build`、`openspec validate add-context-aware-voice-workflows --strict`、`git diff --check`：均通过。

**待确认**：
- [ ] 是否要提供一个设置页引导，为 Agent Compose 单独选择不冲突的快捷键。

## 微信上下文视觉 OCR 兜底修复 - 2026-06-14

**目标**：修复“帮我说/帮我回微信”发送给 LLM 的上下文只有“微信”和窗口按钮描述，没有当前聊天或页面可见内容的问题。

**设计决策**：保留 Accessibility 优先策略；当可读文本不足 50 字时，`ContextPipeline` 使用当前窗口截图做一次本地 Apple Vision OCR，并只把 OCR 后的裁剪文本写入 `ContextSnapshot.visibleText`。截图仍然不落库、不进入 trace、不上传给 LLM。`DefaultAgentComposeHandler` 启动上下文采集时开启视觉兜底，避免生产链路继续固定 `visionSupported: false`。

**偏差说明**：OpenSpec 第一版写的是“视觉内容作为兜底”，设计文档曾倾向多模态 Provider；这次根据真实微信行为改成本地 OCR 文本兜底，因为当前配置的文本模型不支持视觉输入，但用户仍需要把当前应用上下文带给模型。

**权衡分析**：
- 方案一：继续只读 AX 树。优点是快；缺点是微信只暴露窗口 chrome，无法获得聊天上下文。
- 方案二：把截图直接发给支持视觉的模型。优点是保留更多视觉信息；缺点是当前 Provider 不支持，而且会扩大隐私边界。
- 方案三：本地 OCR 后只发送文本。优点是适配文本模型、截图不离开本机；缺点是 OCR 可能受窗口遮挡、字号和布局影响。
- 选择方案三，因为它最小化隐私风险，同时解决微信和浏览器这类 AX 不完整应用的真实上下文缺失。

**验证结果**：
- `swift test --filter ContextPipelineTests/testUsesVisualTextFallbackWhenAccessibilityInsufficient`：先红后绿，覆盖 AX 文本不足时使用视觉 OCR 文本。
- `VOICEINPUT_LIVE_CONTEXT=1 swift test --filter LiveContextPipelineTests`：真实微信和 Chrome 均通过；微信测试已加固，不再允许只有“微信/窗口按钮描述”的假阳性。
- `swift test`：445 项通过，4 项默认跳过，0 失败。
- `swift build -c debug -Xswiftc -warnings-as-errors`、`make build`、`openspec validate add-context-aware-voice-workflows --strict`、`git diff --check`：均通过。

**待确认**：
- [ ] 若用户希望完全禁止截图/OCR，可再加一个设置项关闭视觉兜底。

## 菜单栏状态项与黑块来源修复 - 2026-06-14

**目标**：恢复 VoiceInput 右上角状态项的可见标题，并避免空白 HUD/tooltip 造成深色残留块。

**设计决策**：状态项改为固定宽度的 `VoiceInput` 文字加麦克风图标，补 `autosaveName` 和按钮 identifier，取消 tooltip；HUD 临时消息为空时直接 dismiss，并在退出动画结束时清空文案。

**偏差说明**：屏幕上的小黑块经 CGWindowList 确认为 `FlClash` 浮层，不属于 VoiceInput；VoiceInput 代码侧已恢复标题，但当前系统菜单栏环境会隐藏/压缩新建文字状态项，临时 `TESTSTATUS` 诊断项也同样不显示。

**验证结果**：`StatusBarIconTests|OverlayLayoutTests|OverlayAppearanceTests` 共 11 项通过；`swift build -c debug -Xswiftc -warnings-as-errors`、`make run` 和 `git diff --check` 均通过；Computer Use 确认运行的是 `.build/VoiceInputApp.app`。
## 请求 JSON 可见区域修复 - 2026-06-14
**目标**：修复“查看完整请求 JSON”已展开但内容被详情弹窗挤到不可见区域的问题。
**设计决策**：详情弹窗改成固定高度外壳和可滚动内容区，JSON 展开块保留 220px 内部滚动高度。
**验证结果**：新增 `HomeHistoryDetailLayoutTests` 先红后绿；相关详情测试、`swift build -c debug -Xswiftc -warnings-as-errors`、`make run`、`git diff --check` 通过；重启后系统截图/Computer Use 未能稳定读取窗口，未完成新版视觉点击复测。
**待确认**：无。

## VoxFlow 收口与帮我说详情展示 - 2026-06-15

**目标**：完成 VoiceInput 到随声写 / VoxFlow 的收口验证，修复“帮我说”详情页把完整 system prompt 展示为“发送给模型的内容”的问题，并分析 TokenHub 请求超时原因。

**设计决策**：产品显示名改为“随声写”，英文品牌与构建产物使用 VoxFlow，但 bundle ID 保持 `com.voiceinput.app`。原因是权限记录、TCC 授权和本地调试身份依赖 bundle ID，品牌重命名不应导致每次 `make run` 都重新授权。“发送给模型的内容”在 `agentCompose` 详情页改为只展示用户口述内容，完整请求 trace 仍保留在 JSON/trace 区域供调试。

**偏差说明**：菜单栏图标使用更紧凑的状态栏 item 并清理旧 autosave 位置；若系统菜单栏空间不足，macOS 仍可能把状态项放入隐藏区域，这是系统压缩行为，不是应用未创建状态栏图标。

**权衡分析**：
- 方案一：bundle ID 跟随品牌改为 `com.xingbofeng.VoxFlow`。优点是命名统一；缺点是权限、LaunchServices 和本地调试身份全部变化。
- 方案二：bundle ID 维持 `com.voiceinput.app`，只改可见品牌和产物名。优点是权限稳定且符合迁移目标；缺点是内部身份与品牌名不完全一致。
- 选择方案二，因为用户明确要求后续调试不重复请求权限。

**验证结果**：
- 超时 trace 显示 Provider 为 `legacy-openai-compatible`，endpoint 为 `https://tokenhub.tencentmaas.com/v1/chat/completions`，模型 `deepseek-v4-flash-202605`，配置 `timeout_seconds = 15`；失败请求用时约 15994ms，错误为“请求超时。”，判断为客户端 15 秒超时触发，详情页展示不是根因。
- `swift test`：473 项执行，4 项跳过，0 失败。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `VOICEINPUT_LIVE_CONTEXT=1 swift test --filter LiveContextPipelineTests`：2 项通过，覆盖 Chrome 与微信真实上下文读取。
- `make dmg && make run`：通过，生成 `dist/VoxFlow-1.1.2-macOS.dmg`；实际运行进程为 `VoxFlow`，窗口标题为“随声写”，`.build/VoxFlow.app` 的 `CFBundleIdentifier` 为 `com.voiceinput.app`。
- Computer Use/系统层面已验证：普通听写 HUD、帮我说生成、超时/失败详情、Esc 取消、微信上下文、权限页和旧 VoiceInput 清理路径。

**待确认**：无。

## 智能配置默认风格不落库 - 2026-06-14

**目标**：修复智能配置中大量未识别应用被归类为“元气”的问题。

**设计决策**：`ApplicationStyleRecommendationService.merge` 不再为未被内置注册表或 AI 明确分类覆盖的应用生成默认风格推荐；默认风格只保留在运行时 `SettingsBackedStyleSelector` 兜底使用，不写入应用风格规则。原因是智能配置确认会持久化推荐结果，把“无法判断”转换成默认风格会批量固化错误分类。

**偏差说明**：本轮不改 LLM 分类 prompt、不扩展内置应用注册表，也不自动清理用户已经确认保存过的旧规则；已有错误规则需要用户在风格页手动移除或重新配置。

**权衡分析**：
- 方案一：继续把未知应用归为当前默认风格。优点是预览覆盖率高；缺点是默认风格若是“元气”，会让未知应用全部变成元气并被确认落库。
- 方案二：未知应用保持未配置。优点是只保存有证据的系统预设和 AI 推荐；缺点是未知应用数量看起来会少一些。
- 选择方案二，因为运行时已经有默认风格兜底，智能配置不应把兜底结果伪装成分类结论。

**验证结果**：
- `swift test --filter ApplicationStyleRecommendationServiceTests`：先红后绿，复现并修复默认风格补全问题。
- `swift test --filter 'ApplicationStyleRecommendationServiceTests|BatchApplicationClassifierTests|ApplicationStyleSelectorTests'`：17 项通过，覆盖推荐合并、批量分类解析和运行时默认兜底。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。

**待确认**：
- [ ] 是否需要增加一键清理来源为旧默认风格误分类的已保存规则。

## 微信视觉兜底权限提示修复 - 2026-06-14

**目标**：解释并修复生产 app 的“帮我回微信” trace 仍只有微信窗口 chrome、没有聊天正文的问题。

**设计决策**：当 AX 文本不足且需要视觉兜底时，`SystemScreenshotProvider` 会调用 `CGRequestScreenCaptureAccess()` 触发 macOS 屏幕录制授权；若仍未授权，`ContextPipeline` 写入 `screen_recording_not_authorized`，详情页显示中文可读提示。

**偏差说明**：真实 live test 进程有权限不代表 `.build/VoiceInputApp.app` 有权限，因此先前测试能 OCR，生产 trace 却静默退化为 AX 文本。

**验证结果**：新增权限告警和详情文案测试先红后绿；`ContextPipelineTests|HomeHistoryDetailPresentationTests|LiveContextPipelineTests`、完整 `swift test` 447 项通过 4 项跳过、warnings-as-errors 构建、`make build`、OpenSpec strict、`git diff --check` 通过。

**待确认**：
- [ ] 首次触发后需要用户在 macOS 屏幕录制权限弹窗/系统设置中允许 VoiceInputApp，然后重试一次。

## 智能配置 AI 分类接线与搜索表格 - 2026-06-14

**目标**：修复风格页智能配置没有真正调用 AI 分类的问题，并让分类请求把本机应用元数据以表格交给模型，要求支持搜索的模型先搜索核验应用用途。

**设计决策**：`StyleViewModel.makeSmartConfigurationViewModel()` 默认注入 `LLMBatchApplicationClassifier`，生产路径不再停留在系统预设。`LLMBatchApplicationClassifier` 只要求 Provider 已配置，不再受普通听写“LLM 纠错启用”开关影响；用户主动点击智能配置时，应允许 AI 分类运行。分类 user prompt 改成 Markdown 表格，包含 App Name、Bundle ID、系统分类和 Search Query；system prompt 明确要求支持 web search 的模型先搜索核验，不确定则省略，不把未知应用归入默认风格。顺手修正 Chrome 内置预设，将浏览器从 `builtin.email` 改为 `builtin.casual`。

**偏差说明**：当前 OpenAI-compatible chat 客户端没有通用工具调用协议，因此本轮没有在应用侧强行接入某个搜索引擎 API；搜索能力通过模型/服务支持的 web search 能力触发，表格中为每个应用提供可直接使用的搜索 query。

**权衡分析**：
- 方案一：只保留本地注册表和默认兜底。优点是快；缺点是新应用不会进入 AI 分类，用户看到的“智能配置”不智能。
- 方案二：生产路径注入 AI 分类器，并用表格加搜索 query 提高分类依据。优点是符合智能配置语义；缺点是实际联网搜索取决于用户配置的模型服务是否支持。
- 选择方案二，因为它修复了没有调用 AI 的根因，同时避免引入不稳定的搜索网页抓取。

**验证结果**：
- `swift test --filter 'KnownApplicationRegistryTests|BatchApplicationClassifierTests|StyleViewModelTests/testSmartConfigurationCreatedFromStyleViewModelCallsAIClassifier|ApplicationStyleRecommendationServiceTests'`：26 项通过，覆盖表格 prompt、搜索指令、纠错开关关闭仍可分类、Provider 未配置时跳过、风格页生产创建点调用 AI、Chrome 浏览器预设。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `swift test`：453 项执行，4 项跳过，0 失败。
- `git diff --check`：通过。

**待确认**：
- [ ] 若后续要求“应用侧强制联网搜索”，需要设计可配置搜索 Provider，并更新隐私说明，因为应用元数据会同时发送给搜索服务。

## 应用风格注册表与旧误分类迁移 - 2026-06-14

**目标**：修复注册表覆盖不足、旧显式规则优先级过高，导致风格页仍将大量应用显示为“元气”的问题。

**设计决策**：将已核验的本机常用应用写入 `KnownApplicationRegistry` 并升级注册表版本；启动迁移只识别“至少 10 条且过半为 `builtin.energetic`”的历史批量误分类。命中注册表的旧元气规则改为注册表风格，无法可靠判断的旧元气规则删除，保留非元气手动规则。批量分类 prompt 同时要求省略没有实际文本输入场景的系统、硬件和媒体类应用。

**偏差说明**：上一轮展示的应用归类表只是分析结果，并未全部持久化到注册表；本轮补齐注册表，并修复已经写入本机数据库的旧数据。迁移不会改动少量、可能由用户主动配置的元气规则。

**权衡分析**：
- 方案一：只升级注册表。优点是没有数据迁移；缺点是旧显式规则继续覆盖注册表，用户界面不会变化。
- 方案二：无条件清空全部元气规则。优点是简单；缺点是会误删用户主动配置。
- 选择带阈值识别的迁移，因为它能修复已知批量误分类，同时保护正常的小规模手动规则。

**验证结果**：
- `swift test`：456 项执行，4 项跳过，0 失败。
- `swift build -c debug -Xswiftc -warnings-as-errors`、`openspec validate add-context-aware-voice-workflows --strict`、`git diff --check`：均通过。
- 已备份迁移前数据库到 `/Users/counter/Library/Application Support/VoiceInput/voiceinput-before-style-rule-fix-20260614-223725.sqlite`。
- 启动迁移后数据库中 `builtin.energetic` 显式规则为 0；Computer Use 实测“元气”页为空，“编程”页显示 Codex、Qoder、Kiro、Zed、Ghostty、Postman、TablePlus 等应用。

**待确认**：无。
