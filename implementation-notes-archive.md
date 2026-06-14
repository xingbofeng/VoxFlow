## 客户端样式底座与低风险视觉统一 - 2026-06-13

**目标**：在不改变主要功能和页面布局的前提下，先建立统一的 macOS 简洁风格样式底座，并修复阻塞本地验证的构建问题。

**设计决策**：选择集中扩展 `AppTheme`，而不是逐页硬编码颜色、圆角和阴影。原因是页面很多，先把视觉 token 固化后，后续逐页像素对齐可以沿同一套规则推进。

**偏差说明**：用户目标是全量像素级修复；本轮实际完成的是第一批低风险视觉统一和验证恢复。全量反馈清单中的权限弹窗、状态栏图标、App 图标透明边缘、LLM 配置回填等仍需要继续处理。

**权衡分析**：
- 方案一：一次性重排全部页面。优点是视觉变化大；缺点是功能和布局偏移风险高。
- 方案二：保留页面结构，只替换主题 token、表面、按钮 tint、选中态、输入/卡片样式。优点是风险低、容易回归；缺点是还不能达到最终像素级一致。
- 选择方案二，因为用户明确要求不要改功能和布局，避免 agent 目标偏移引入更多 bug。

**待确认**：
- [x] 首页窗口右侧在当前桌面截图中被屏幕边缘遮挡，是否需要同步调整窗口默认定位？
- [x] 是否先继续按 `docs/USER_FEEDBACK_ISSUES_2026-06-13.md` 从 P0/P1 顺序修复？→ 已执行

## 用户反馈问题批量修复 - 2026-06-13

**目标**：按 `USER_FEEDBACK_ISSUES_2026-06-13.md` 清单批量修复 P0/P1/P2 问题。

**已完成修复（本轮）**：
- #13/#14 帮助菜单和辅助功能弹窗中的"右 Command"改为动态读取快捷键配置
- #6 笔记页面全局快捷键触发录音：新增 `NotesCaptureCoordinator`，笔记页激活时热键路由到笔记录音
- #11 音频反馈设置生效：录音开始/完成/失败时根据设置播放系统音效（Morse/Glass/Basso）
- #18 LLM 添加按钮从纯图标改为带标签的 accent 色按钮，提升对比度和可识别性
- #8 全项目图标按钮点击区域统一到 ≥32×32pt（GlossaryView、HomeDashboardView、NotesView）
- #16 六个内置风格 prompt 重写为结构化 Markdown，覆盖用途、规则、与 LLM 纠错的关系、不会改写的情况

**已验证代码正确（之前已修复）**：
- #4 录音浮层已使用 hudWindow 材质 + 胶囊形状 + 文字换行 + 最大高度 220pt
- #5 语音识别错误已使用 `showTemporaryMessage` 非阻断 HUD
- #2 状态栏图标已使用 SF Symbol template image + 白色 tint
- #9 LLM 编辑回填已正确实现
- #13 设置页快捷键 icon 已通过 `keyIconName()` 动态映射

**需要额外处理（非代码或需设计决策）**：
- #1 权限弹窗：NSAlert accessory view 已使用 SwiftUI 自定义面板；按钮仍为系统默认样式，需替换为自定义窗口才能进一步定制
- #3 App 图标边缘透明：需要重新导出 PNG/icns 资产
- #17 文件转写光标：当前使用 `Text` + `.textSelection(.enabled)` 展示，非可编辑光标
- #20 源码目录分层：需要单独确认文件移动清单和迁移方案

**设计决策**：
- 笔记热键路由使用 singleton `NotesCaptureCoordinator` 而非 NotificationCenter，因为需要双向通信（isActive、isRecording）
- 音频反馈使用 macOS 系统音效（NSSound），轻量且不引入额外音频引擎依赖

**偏差说明**：
- 原计划逐个修复全部 20 个问题；实际发现约一半已在之前 session 修复，本轮聚焦于真正未修复的 6 个问题和 4 个点击区域统一

**待确认**：
- [ ] App 图标资产是否需要重新导出？
- [ ] 权限弹窗是否需要替换 NSAlert 为自定义 SwiftUI 窗口？
- [ ] 目录分层方案是否按 CONTEXT.md 模块边界执行？

## 代码风格 Review 与优化 - 2026-06-13

**目标**：对上一轮修复的代码进行风格审查，消除重复代码、统一主题 token 使用、改善 prompt 质量。

**已完成优化**：

**1. 消除 KeyCode 映射三处重复 → 提取 `KeyCodeMapping` 工具类型**
- 新增 `KeyCodeMapping.swift`，提供 `displayName(for:)` 和 `iconName(for:)` 两个静态方法
- `HelpView`、`SettingsRootView`、`AppDelegate` 三处完全相同的 switch 语句统一委托给该工具类型
- 消除约 70 行重复代码，后续新增按键只需改一处

**2. 修复 `AppTheme.accentDark` 声明方式**
- 从 `static var accentDark: Color { ... }` 改为 `static let accentDark = Color(...)`
- 与其他所有 ColorToken 保持一致（均为 `static let`）

**3. 删除 GlossaryView 死代码**
- 移除从未被引用的 `cardBorder` 计算属性

**4. 使用 AppTheme.Radius token 替代硬编码数值**
- `HelpView` HelpFeatureCard/HelpSectionCard 图标圆角：`10` → `AppTheme.Radius.icon`
- `LLMProviderView` 添加按钮圆角：`8` → `AppTheme.Radius.control`

**5. 音频反馈代码优化**
- `DecodedSettingValue` / `EncodedSettingValue` 从 `private` 改为 `internal`，供 `AppDelegate` 复用
- `isSoundFeedbackEnabled()` 移除内联 `BoolWrapper` struct，改用共享的 `DecodedSettingValue<Bool>`
- 系统音效 `NSSound` 对象提取为 `FeedbackSound` 枚举的 static let，避免每次调用时重复创建

**6. BuiltInStyleCatalog prompt 质量改善**
- 统一六个风格的输出约束句式为「输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容」，仅在编程和邮件风格追加额外约束
- 统一术语：「犹豫词」「口头停顿」→「语气填充词」
- 「不替用户作判断」→「不替用户做判断」（更口语化）
- 改善元气风格 sampleOutput：从仅加「！」改为实际展示活力改写

**设计决策**：
- `KeyCodeMapping` 放在独立文件而非附加到 `ShortcutManager`，因为它是纯映射工具，不依赖 UserDefaults 也不持有状态
- 输出约束句式统一但保留风格特有的附加约束（编程：「不要解释术语」；邮件：「不要添加主题行或 Markdown 标记」），兼顾一致性和场景差异

**偏差说明**：
- Review 发现更多可优化项（IconBadge 复用组件、FontToken 采用或废弃、shadow token 分层、NotesView 改用 `.appPanel()`），但这些属于视觉一致性长期工作，本轮不处理以避免范围蔓延

**待确认**：
- [ ] 是否将 `FontToken` 扩充并全量采用，还是删除该 enum 保持现状？
- [ ] 是否需要提取 `IconBadge` 复用组件（42×42 图标底座在 3+ 处重复）？

## 用户反馈问题收尾与原生验证 - 2026-06-13

**目标**：在不改变主要功能和页面布局的前提下，完成反馈清单中的样式统一、明确缺陷修复和真实 macOS App 验证。

**设计决策**：权限提示使用独立 SwiftUI `NSPanel`；快捷键显示集中到 `KeyCodeMapping`；音频反馈通过独立 controller 保证提示音、静音和恢复顺序；窗口在真正显示后的下一轮主线程再次检查多屏可见性。

**偏差说明**：未执行源码和测试目录重组，因为该项涉及大量文件移动，超出用户“只改样式、不改功能和布局”的当前范围，也需要按项目规范先确认移动清单。文件转写光标问题在当前实现中未复现，结果区是只读可选择文本。

**权衡分析**：
- 方案一：同步重排页面和目录。优点是变化明显；缺点是回归面大且偏离当前范围。
- 方案二：保留现有页面结构，集中修复主题、命中区域、弹窗、快捷键、HUD、设置运行路径和资产。优点是风险可控且可逐项验证。
- 选择方案二，因为它符合用户明确的低风险约束。

**验证结果**：
- `swift test`：231 个测试通过，2 个环境测试跳过，0 失败。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `make build`：通用二进制 App 构建和签名通过。
- Computer Use：权限面板、首页、模型、笔记、文件转写、风格、设置、帮助主要页面完成检查。
- 多屏窗口：实测从跨屏坐标 `755, 33` 校正到主屏坐标 `206, 101`，尺寸保持 `1100 x 752`。

**待确认**：
- [ ] #20 目录分层是否另开任务，并先评审完整文件移动清单？

## Qwen3 流式识别门禁与 HUD 样式修正 - 2026-06-13

**目标**：修复 Qwen3-ASR 读到失效/迟到音频导致识别乱码的问题，并把录音 HUD 调整为更大的浅色胶囊样式。

**设计决策**：`AudioRecorder` 在 audio tap 回调内同步深拷贝 `AVAudioPCMBuffer`，再把副本派发到主线程，避免 ASR 在主线程读取到 AVAudioEngine 复用后的 buffer。Qwen3 引擎在 `start()` 后才接受音频，`endAudio()` 立即关闭入口；流式 chunk 通过单条任务链顺序送入 `Qwen3StreamingSession`，而不是为每个 buffer 独立并发写入。原因是 FluidAudio 的 Qwen streaming manager 会维护累积音频和转写状态，外层需要保证音频样本有效、录音生命周期边界和 chunk 顺序清晰。

**偏差说明**：原以为 1.7B 清单只是缺少下载词表；实际校验 HuggingFace 远端发现 `aoiandroid/Qwen3-ASR-1.7B-CoreML` 根目录没有 `vocab.json`。因此本轮没有伪造不可下载的词表 URL，而是把缺词表的 1.7B `.mlpackage` 布局判定为不可加载，避免设置层误判可用。

**权衡分析**：
- 方案一：每次录音都重建 Qwen session。优点是生命周期最干净；缺点是可能重新引入模型加载延迟。
- 方案二：保留预加载 session，但关闭 release 后音频入口，并串行化 chunk 写入。优点是保留流式和加载性能；缺点是仍依赖 FluidAudio session reset 行为。
- 选择方案二，并在更底层复制 audio tap buffer，因为它最小化改动，同时直接覆盖失效 buffer、迟到 buffer 和流式顺序问题。

**验证结果**：
- `swift test --filter AudioRecorderTests`：通过。
- `swift test --filter Qwen3ASREngineTests`：通过。
- `swift test --filter ASRManagerTests`：通过。
- `swift test`：235 个测试通过，2 个环境测试跳过，0 失败。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。

**待确认**：
- [ ] 是否要在 UI 上暂时隐藏或标注 1.7B 模型不可用，避免用户下载后困惑？
- [ ] 是否需要用真实麦克风和本地 Qwen 0.6B 模型做一次端到端中文识别实测？

## 统一顶部反馈 Toast 与速度文案 - 2026-06-13

**目标**：修复操作反馈提示过高、位置不统一且占用页面布局的问题，并把首页中不易理解的 `CPM` 文案替换为通俗的「字/分钟」。

**设计决策**：新增 `actionFeedbackOverlay` 作为统一入口，让全页反馈通过顶部居中的 overlay 显示，而不是插入页面 `VStack` 内容流。原因是操作反馈属于短暂浮层，不应撑开页面或挤压主内容。

**偏差说明**：保留 `LLMProviderEditor` 表单内部的 `ActionFeedbackView`，因为它是编辑器局部校验/测试反馈，不属于全页 toast；首页 UI 文案已替换为「平均字/分钟」「字/分钟」「速度」，底层字段名 `averageCPM` 暂不迁移，避免扩大数据模型改名范围。

**权衡分析**：
- 方案一：逐页微调现有 `ActionFeedbackView` 位置。优点是改动少；缺点是继续分散，后续容易不一致。
- 方案二：提供统一 overlay modifier 并替换主要页面入口。优点是定位和尺寸集中；缺点是需要改多个页面调用点。
- 选择方案二，因为用户明确要求统一且不影响布局。

**验证结果**：
- `swift test --filter AppThemeTests`：通过。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。

**待确认**：
- [ ] 是否也要把代码内部 `averageCPM` 字段重命名为 `averageCharactersPerMinute`？

## 首页输入活跃度方块图 - 2026-06-13

**目标**：在首页按设计稿增加类似 GitHub contribution graph 的输入活跃度小方块统计，只改首页信息呈现，不影响其他页面和历史操作。

**设计决策**：在 `HomeDashboardViewModel` 中新增 `HomeActivitySummary` / `HomeActivityDay`，从现有历史记录按天聚合最近 52 周字符数，再由 `HomeDashboardView` 按周一到周日渲染全年小方块。点击方块会设置 `selectedActivityDate`，让顶部统计和历史列表按当天重新计算；清除筛选回到总览。原因是日期窗口、字符汇总、筛选状态和强度分级属于页面状态，不应散落在 SwiftUI 视图布局中。

**偏差说明**：设计稿是静态图；实际实现使用真实历史数据。第一版 7 周固定小尺寸在宽首页里没有铺满，后续改为 52 周窗口，并根据卡片宽度动态计算方块尺寸；再根据截图反馈把最大方块尺寸和固定 grid 高度下调，避免卡片底部空白过大。强度分级按窗口内单日最大字符数做相对映射，避免早期低数据量用户看到整块全空或全满。

**权衡分析**：
- 方案一：只在视图中临时计算方块。优点是文件少；缺点是日期和聚合逻辑不可测试。
- 方案二：把活跃度作为首页 ViewModel 的派生状态。优点是可测试、易复用、UI 更纯粹；缺点是 ViewModel 增加少量展示模型。
- 选择方案二，因为首页已有统计和历史分组都由 ViewModel 派生，符合现有模式。

**验证结果**：
- `swift test --filter HomeDashboardViewModelTests/testLoadBuildsContributionActivity`：通过，覆盖 52 周窗口、同日字符合并、本周字符和强度分级。
- `swift test --filter HomeDashboardViewModelTests/testSelectingActivityDayFiltersStatsAndHistory`：通过，覆盖点击方块后的统计和历史按当天筛选，以及清除筛选恢复总览。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `swift test`：239 个测试通过，2 个环境测试跳过，0 失败。
- `make build`：通用二进制 App 构建和签名通过。

## 帮助页微信入口与紧凑 HUD - 2026-06-13

**目标**：在帮助页增加作者微信二维码交流入口，把项目主页切到落地页并单独提供 GitHub 入口，同时把录音 HUD 从偏大的胶囊改为贴合项目浅色工具风格的底部紧凑浮层。

**设计决策**：帮助页新增 `HelpExternalLinks` 集中维护外链，项目主页使用 GitHub Pages 落地页，GitHub 仓库作为单独入口；微信二维码和官方 GitHub mark 作为 SwiftPM resource 打包。微信二维码用页面内绝对覆盖层展示，点击空白区域关闭，避免 sheet 带来的系统大弹窗视觉。HUD 使用浅鼠尾草色玻璃背景、深色文字、主题绿色波形、52px 起步高度和 12px 圆角，固定在屏幕底部上方 40px，原因是它更贴近项目现有浅色工具型设计，也不会遮挡页面上方主要内容。

**偏差说明**：GitHub 图标改为官方 mark PNG，而不是系统符号。为了让 release `.app` 也能显示二维码和 GitHub 图标，同步修改了 `Makefile`，把 SwiftPM resource bundle 复制到 `Contents/Resources` 并验证资源文件存在。

**权衡分析**：
- 方案一：直接把二维码图片放在帮助页常驻展示。优点是入口明显；缺点是占用帮助页大量空间。
- 方案二：帮助页提供「添加作者微信交流」操作行，点击后弹窗展示二维码。优点是页面保持紧凑，二维码需要时再出现。
- 选择方案二，因为帮助页现有结构以入口列表为主，弹窗更符合低频联系动作。

**验证结果**：
- `swift test --filter 'OverlayLayoutTests|HelpExternalLinksTests'`：通过。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `swift test`：246 个测试通过，2 个环境测试跳过，0 失败。
- `make build`：通用二进制 App 构建、资源检查和签名通过。
- 本地运行：已重启 `.build/VoiceInputApp.app` 并做截图检查。

## 输入设备系统自带选项 - 2026-06-13

**目标**：设置页「输入设备」下拉中增加清晰的「系统自带」选项，并隐藏 `CADefaultDeviceAggregate-*` 这类 CoreAudio 默认聚合设备内部名称。

**设计决策**：`SystemAudioInputDeviceProvider` 固定把 `system-default` /「系统自带」放在设备列表首位，再过滤 AVCapture 返回的 `CADefaultDeviceAggregate` 设备；加载设置时把已保存的 `CADefaultDeviceAggregate-*` 迁移为 `system-default`。原因是 `CADefaultDeviceAggregate` 是系统默认输入的底层聚合标识，不适合直接暴露给用户。

**偏差说明**：本轮只修复设置页设备列表显示、默认选项和旧值迁移；录音链路当前仍沿用系统默认输入路径，没有扩大到按所选设备切换真实录音设备。

**权衡分析**：
- 方案一：把 `CADefaultDeviceAggregate-*` 文案重命名成「系统自带」。优点是改动更少；缺点是保存值仍是系统内部聚合 ID，后续系统重启或设备变动时不稳定。
- 方案二：引入稳定的 `system-default` 逻辑选项，并过滤底层聚合设备。优点是 UI 文案清楚、保存值稳定；缺点是需要在加载旧配置时做一次迁移。
- 选择方案二，因为它更符合设置项语义，也避免用户继续看到 CoreAudio 内部名称。

**验证结果**：
- `swift test --filter SettingsViewModelTests/testAudioDeviceProviderAddsSystemBuiltInAndHidesCoreAudioDefaultName`：通过。
- `swift test --filter SettingsViewModelTests/testLoadMigratesSavedCoreAudioDefaultAggregateToSystemBuiltIn`：通过。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `swift test`：243 个测试通过，2 个环境测试跳过，0 失败。
- `make build`：通用二进制 App 构建、资源检查和签名通过。

**待确认**：
- [ ] 是否需要继续把「输入设备」选择真正接入录音引擎，让用户可指定某个实体麦克风录音？

## Context-Aware Voice Workflows 基线记录 - 2026-06-14

**目标**：记录 add-context-aware-voice-workflows 变更前的系统基线状态

**当前基线**：

- **快捷键**：右 Command 长按录音、释放转写，通过 KeyMonitor CGEvent tap 实现。ShortcutManager 存储快捷键配置（UserDefaults key: `hotkey.rightCommand`）。无"帮我说"快捷键概念。
- **数据库迁移**：当前最高 migration ID = 2（`dictation_history_processing_trace`）。schema_migrations 表跟踪已应用的迁移。下次迁移应为 ID 3。
- **风格规则**：AppStyleRuleStore 通过 SettingsBackedStyleSelector 运行时解析，app_settings 表存储 app→style 映射。无内置应用注册表，无 LLM 批量分类，无推荐预览流程。
- **注入行为**：TextInjector 使用剪贴板 + Command-V 粘贴。注入前切换 CJK 输入源为 ABC/US，注入后恢复。返回 void（无结构化结果）。无目标窗口校验。
- **现有表结构**：dictation_history（14 列）、glossary_terms、replacement_rules、style_profiles、asr_providers、llm_providers、transcription_jobs、notes、app_settings。无 voice_tasks 表。
- **测试基线**：253 个 XCTest 测试通过，2 个环境测试跳过，0 失败。
- **PromptBuilder**：仅 conservativeSystemPrompt，用于 dictation 模式的保守纠错。无 AgentPromptBuilder。

**待确认**：
- [ ] 右 Command 快捷键配置 key 是否需要迁移到 VoiceAction 模型？
- [ ] 现有 dictation_history 记录是否需要在 voice_tasks 表中建立对应关系？

## 首页方块筛选日期文案与历史文本切换 - 2026-06-13

**目标**：修正首页活跃度方块的筛选交互：点击空白处恢复总览，点击某一天后统计、目标和历史分组显示具体日期；历史列表增加转换前/转换后文本切换入口。

**设计决策**：日期相关标题由 `HomeDashboardViewModel` 根据 `selectedActivityDate` 派生，未筛选时保留「今日字符」「今日目标」，筛选时显示如「6月8日字符」「6月8日目标」和「6月8日」历史分组。历史行新增 `HomeHistoryTextVariant`，直接在已有 `rawText` / `finalText` 间切换，不改数据库结构。

**偏差说明**：历史切换只影响列表行的展示文本；复制按钮仍沿用原来的复制处理后文本行为，避免改变既有复制语义。

**权衡分析**：
- 方案一：只在 SwiftUI 里临时拼接标题和切换文本。优点是改动少；缺点是日期标题逻辑不可测试。
- 方案二：把日期标题和历史文本变体作为首页模型能力暴露给视图。优点是能用单测锁住筛选文案和文本切换；缺点是 ViewModel 增加少量展示属性。
- 选择方案二，因为这些行为属于首页状态的派生结果，和现有统计/历史分组逻辑一致。

**验证结果**：
- `swift test --filter HomeDashboardViewModelTests`：通过，覆盖选中日期后的标题、历史分组日期和历史文本转换前/后。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `swift test`：244 个测试通过，2 个环境测试跳过，0 失败。
- `make build`：通用二进制 App 构建、资源检查和签名通过。

**待确认**：
- [ ] 是否希望切到“转换前”时，复制按钮也复制转换前文本？

## 模型纠错可追溯与弹窗详情 - 2026-06-14

**目标**：把首页历史详情从底部内嵌区域改为弹窗，并让 LLM 纠错过程可追溯；同时修复 Markdown 预览越界、笔记输入框占位符对齐、帮助页 GitHub/微信样式、二维码弹窗 Esc 关闭、Dock 图标声明和 HUD 视觉结构。

**设计决策**：历史库新增 `processing_trace_json`，用迁移 `dictation_history_processing_trace` 为旧库补列；`RepositoryBackedLLMRefiner` 在真正纠错请求前清空旧 trace，并记录本次请求 endpoint、provider、模型、温度、请求体 JSON、响应、状态码、耗时和错误。首页详情改为 modal sheet，展示原文/处理后/元数据/请求体/响应，原因是详情属于临时检查和追溯动作，不应占用首页底部布局。Markdown 预览改为项目内轻量渲染器，显式处理标题、粗体段落和列表，避免系统 `AttributedString(markdown:)` 在窄栏中横向溢出。

**偏差说明**：转写时没有边识别边调用纠错模型；真实流程是 ASR final 出来后进入 processing/refining 状态再调用 LLM。应用风格自动选择可能会在构建 prompt 时额外调用一次 LLM，但纠错 trace 只记录最终文本纠错请求，避免把分类请求混入历史详情。重新注册并打开 release bundle 后，已确认主窗口和 Dock 图标可见；历史详情与 HUD 的最终像素效果仍需结合真实操作继续复核。

**权衡分析**：
- 方案一：只在弹窗里临时重新拼 prompt。优点是改动少；缺点是无法证明当时真实发出的请求体。
- 方案二：在 LLM refiner 发请求时记录 trace，并随历史保存。优点是真实可追溯；缺点是数据库和测试需要同步升级。
- 选择方案二，因为用户需要确认“有没有经过大模型”和“请求体是什么”，只有保存真实请求 trace 才能回答。

**验证结果**：
- `swift test --filter 'RepositoryBackedLLMRefinerTests|SQLiteHistoryRepositoryTests|HomeDashboardViewModelTests|OverlayLayoutTests|AppPresentationPolicyTests'`：23 个测试通过，覆盖 trace 捕获、历史保存/读取、详情解码、HUD 新尺寸和 regular activation。
- `swift test`：246 个测试通过，2 个环境测试跳过，0 失败。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `make build`：通用二进制 App 构建和签名通过。
- `git diff --check`：通过。

**待确认**：
- [ ] 需要结合一次真实听写继续复核历史详情与 HUD 的最终像素效果。

## 权限窗口底部操作区遮挡修复 - 2026-06-14

**目标**：修复权限提示窗口在两项权限场景下高度不足，导致底部“完成 / 打开系统设置”按钮被挤出可见区域的问题。

**设计决策**：把窗口高度计算提取为 `PermissionGuideLayout`，两项权限时至少保留 `470pt`，权限项增加时同步增高；底部按钮区提高布局优先级，并在窗口显示后使用统一窗口定位策略校正到可见屏幕。

**偏差说明**：保留现有权限页视觉和信息结构，只调整承载尺寸与定位，不重做卡片样式。

**验证结果**：
- 回归测试先因缺少布局策略失败，补实现后 `PermissionGuideLayoutTests` 2 项通过。
- `swift build -c debug -Xswiftc -warnings-as-errors` 通过。
- `make build` 通用二进制构建、资源检查和签名通过；新包已重新打开。

## Qwen 模型卡片文案修正 - 2026-06-14

**目标**：移除用户不可理解的 Provider/CoreML 技术表述，并明确模型未安装时的下一步操作。

**设计决策**：未安装时显示“尚未安装本地模型”，说明可下载或选择已有模型文件夹；安装完成后仅保留本机处理与不上传说明。

**偏差说明**：只调整展示文案，不修改模型下载、选择或识别流程。

**验证结果**：`ASRProviderRegistryTests` 覆盖未安装和已就绪两种状态，4 项通过。

## 详情可读性、HUD 白底与 GitHub 图标修复 - 2026-06-14

**目标**：让转写详情中的纠错过程和基本信息一眼可懂，修复追踪卡片未占满、灰色底、HUD 背景受桌面染色以及 GitHub 图标未变绿的问题。

**设计决策**：数据层继续保存原始 ID，新增纯展示映射转换为“Qwen3 本地识别”“OpenAI 兼容纠错服务”“编程风格”等用户文案；详情容器显式占满可用宽度并使用系统文本白底。HUD 移除 `.popover` 毛玻璃材质，改用 98% 不透明白色原生视图。GitHub PNG 设为 template image，通过主题前景色渲染。

**偏差说明**：保留 HUD 当前尺寸和信息结构，本轮只修复用户明确指出的底色，不做未经确认的尺寸调整。

**验证结果**：
- 新增详情展示映射、HUD 背景和 GitHub template 图标测试，完成红绿循环。
- `swift test`：252 项通过，2 项环境测试跳过，0 失败。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `make build`：通用二进制构建、资源检查和签名通过。
- 原生 App 实测：详情满宽白底和人话字段正常，Esc 可关闭；GitHub 图标为主题绿色；HUD 为稳定白底。

## 详情请求 JSON 默认折叠修复 - 2026-06-14

**目标**：修复历史详情中“发送给模型的内容”仍占用过多高度、完整请求 JSON 展示样式不符合默认折叠抽屉预期的问题。

**设计决策**：把请求体预览解析提到 `HomeHistoryDetailPresentation.requestBodyPreview`，视图只展示 `messages` 中 `role == "user"` 的正文；完整请求 JSON 改为内联 `DisclosureGroup`，默认折叠并限制展开后的 JSON 区域高度。原因是预览逻辑属于展示层规则，应可单测；JSON 追溯是低频检查动作，不应默认占用 sheet 高度。

**偏差说明**：本轮只修复 trace 详情区域，不改变 trace 存储格式、LLM 请求记录内容或历史详情的整体 sheet 入口。

**权衡分析**：
- 方案一：继续使用按钮弹出 popover。优点是实现简单；缺点是样式脱离当前详情面板，也没有满足默认折叠的 inline drawer 预期。
- 方案二：使用 `DisclosureGroup` 在面板内展开完整 JSON。优点是默认高度小、上下文不丢失；缺点是展开后仍需要内部滚动以承载长 JSON。
- 选择方案二，因为它直接对应“默认折叠，点击展开查看完整请求”的交互目标。

**验证结果**：
- `swift test --filter HomeHistoryDetailPresentationTests`：4 项通过，覆盖只提取用户消息和缺失用户消息时回退原始 JSON。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。

**待确认**：
- [ ] 需要结合真实历史记录手工复核 sheet 展开/折叠后的最终像素效果。

## Phase 7-10 Context-Aware Voice Workflows 实现 - 2026-06-14

**目标**：实现上下文采集、Agent 生成链、HUD/首页详情/恢复操作、集成验证四个阶段

**设计决策**：

1. **ContextPipeline 采用协议抽象**：`WindowInfoProviding`、`AccessibilityProviding`、`ScreenshotProviding` 三个协议分别抽象系统 API，使得全部 13 个测试可以纯单元测试运行，不需要真实 Accessibility 或屏幕录制权限。

2. **ContextSnapshot 不含截图数据**：`ContextSnapshot` 仅包含 `visualContentAvailable: Bool` 标志。截图生命周期限定在单次任务内，不进入 Codable 序列化路径，不写入数据库。

3. **安全输入框全阻断**：`isSecureTextField` 检测到安全输入框时，所有 Accessibility 采集（可见文本、选中文本、输入区域）均被跳过，仅保留窗口元数据。

4. **AgentPromptBuilder 与 PromptBuilder 分离**：遵循 ADR-010，dictation 模式使用 PromptBuilder（保守纠错），agent compose 使用 AgentPromptBuilder（固定 Agent prompt）。两者有不同的系统提示词约束。

5. **VoiceTaskCoordinator 扩展而非替换**：新增 `processAgentComposeAndDeliver` 方法和 `contextPipeline`/`agentRefiner` 可选依赖，保持 `processAndDeliver` 的 dictation 路径完全兼容。

6. **Copy-only 输出保证**：`DefaultOutputService.deliver` 在 `mode == .agentCompose` 时仅写入剪贴板，不执行 Command-V、不模拟 Enter、不触发应用特定发送。

7. **HomeHistoryDetail 扩展而非重建**：在现有 `HomeHistoryDetail` 添加可选字段（`taskMode`、`taskStatus`、`windowTitle`、`contextPreview`、`outputResultRaw`），保持从 `DictationHistoryEntry` 初始化的路径兼容。

8. **恢复操作按任务类型和状态计算**：`availableRecoveryActions` 根据 taskMode + taskStatus + 数据可用性决定操作列表。重试不覆盖原始口述和旧结果。

**偏差说明**：
- 原规格要求上下文采集"不阻塞录音启动"，实际通过 `Task.detached` 在后台队列运行 `ContextPipeline.collect`，由 coordinator 的 `startContextCollection` 在录音开始时并行启动。
- 原规格要求"重新转写"恢复操作，当前实现标记为可用但实际重新转写需要音频文件保留，此功能依赖 Phase 1 的音频生命周期管理。

**待确认**：
- [ ] `SystemAccessibilityProvider` 在真实 Accessibility 权限下的表现需要手工验证
- [ ] 视觉上下文的 LLM 图片发送路径尚未实现（当前仅检测权限和设置标志）

## 帮我说设置与应用路由 UI 验证修复 - 2026-06-14

**目标**：按设计稿补齐“帮我说”快捷键设置、风格页应用路由、管理应用弹窗和智能配置入口，并通过真实 `make run` 验证运行包。

**设计决策**：设置页把“语音转录”和“帮我说”拆成两个动作行，保留同一触发方式选择区；风格页在 Markdown 编辑器上方加入“适用应用”区，复用 `AppStyleRuleStore` 作为应用绑定来源，复用 `InstalledAppSelectorView` 管理已安装应用。新增 `ApplicationIconView`，优先读取 `.app` 的真实 icns，失败时退回首字母占位。

**偏差说明**：当前“元气”风格没有绑定应用时显示空态，设计稿中的应用 icon 列表只有在已有规则或命中注册表推荐时出现。智能配置弹窗首次实测出现空白 sheet，原因是可选 VM 在 `.sheet` 内容闭包中存在渲染时序问题，已改为初始化时创建稳定 VM。

**权衡分析**：
- 方案一：为风格页单独新建一套应用管理状态。优点是局部独立；缺点是会绕开已有规则存储，后续路由不会生效。
- 方案二：直接复用当前应用规则模型和已安装应用扫描。优点是 UI、路由和智能配置写入同一份数据；缺点是风格页需要处理无规则空态。
- 选择方案二，因为应用路由 UI 必须和运行时风格选择使用同一份规则。

**验证结果**：
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `make run`：release universal 构建、签名和启动通过。
- 原生 App 实测：设置页出现“语音转录 / 帮我说 / 不自动发送 / 设置快捷键 / 触发方式”；风格页出现“适用应用 / 管理应用 / 智能配置”；管理应用弹窗显示搜索、已安装应用列表、添加按钮和真实应用图标；智能配置弹窗显示“智能应用配置”和“开始扫描”，空白 sheet 已修复。
- `swift test`：406 项通过，2 项跳过，0 失败；测试阶段仍有既有 `OverlayAppearanceTests` actor-isolation warning。
- `openspec validate add-context-aware-voice-workflows --type change --strict --no-interactive`：通过。
- `git diff --check`：通过。

**待确认**：
- [ ] 聊天类注册表当前指向 `builtin.chat`，但内置风格目录尚无聊天风格；后续需要决定新增“聊天”风格还是映射到现有“日常/邮件”风格。

<!-- Migrated from implementation-notes.md on 2026-06-14 before smart configuration default-style fix. -->

## HUD 新内容优先与注入失败剪切板兜底 - 2026-06-14

**目标**：修复录音 HUD 长文本尾部被省略导致看不到最新内容的问题；当用户录音过程中切换应用导致目标变化时，不再尝试向新应用粘贴，而是把最终文本保存到剪切板。

**设计决策**：HUD 在 `OverlayLayout.visibleTranscriptionText` 阶段主动保留较短尾部文本并在前面加省略号，避免 `NSTextField` 对超长两行内容再次做尾部截断。旧右 Command 听写链路在注入前重新读取当前目标，并复用 `DictationTargetChangePolicy` 判断是否与录音开始目标不同；目标变化时直接写入剪切板，目标未变时仍走原注入路径。

**偏差说明**：本轮只处理目标应用/窗口变化前置检测和 Accessibility 权限失败兜底；无法在系统层确认某次 Command-V 是否被目标控件实际接收。`TextInjector` 的事件创建失败仍沿用原有行为：文本已放入系统剪切板并不恢复旧剪切板。

**权衡分析**：
- 方案一：继续让 HUD 控件自行截断。优点是代码少；缺点是会再次出现尾部省略，看不到最新识别内容。
- 方案二：布局层预先裁剪为尾部短文本。优点是稳定显示新内容；缺点是长文本可见上下文更少。
- 选择方案二，因为录音 HUD 的核心任务是反馈最新识别状态，不是完整阅读历史。

**验证结果**：
- `swift test --filter 'OverlayLayoutTests|DictationOrchestratorTests/testTargetApplicationChangeCopiesFinalTextWithoutInjection'`：6 项通过，覆盖 HUD 尾部保留和应用切换剪切板兜底。
- `swift test --filter OutputServiceTests`：11 项通过，确认共享目标变化策略未破坏既有输出服务行为。

**待确认**：
- [ ] 需要用真实长中文录音复核 HUD 两行视觉效果和剪切板兜底提示文案是否还需要加强。

## 详情弹层外部点击与风格请求修复 - 2026-06-14

**目标**：修复转写详情点击灰色背景不能关闭的问题，并修复元气等表达风格调用 LLM 后输出几乎不变的问题。

**设计决策**：将历史详情从系统 `.sheet` 改成首页内的自定义 overlay/backdrop；背景层独立处理点击关闭，内容层吞掉内部点击，避免误关。Prompt 构建时继续保留纠错约束，但明确风格可以在自身规则范围内调整语气、标点、措辞和结构；同时把风格配置里的 provider、model、temperature 传入 LLM 请求，并把 `max_tokens` 改为按输入长度扩容且最低 256。

**偏差说明**：本轮不改历史详情的数据存储格式，也不改变具体模型服务；外部模型仍可能按自身能力返回接近原文的结果，但应用侧不再把风格温度、模型和输出长度覆盖成全局保守配置。

**权衡分析**：
- 方案一：继续使用系统 sheet。优点是原生；缺点是 macOS sheet 背景点击不关闭，无法满足当前交互预期。
- 方案二：实现应用内 overlay。优点是背景点击行为可控；缺点是需要自己维护弹层尺寸和背景遮罩。
- 选择方案二，因为该 bug 本质是系统 sheet 交互模型和产品预期不一致。

**验证结果**：
- `swift test --filter 'HomeDashboardViewModelTests/testBackdropDismissClearsSelectedDetail|PromptBuilderTests|RepositoryBackedLLMRefinerTests/testRefineUsesEnabledDefaultProviderConfiguration'`：12 项通过，红绿循环完成。
- `swift test --filter 'HomeDashboardViewModelTests|PromptBuilderTests|TextProcessingPipelineTests|RepositoryBackedLLMRefinerTests|TranscriptionMainChainRegressionTests'`：49 项通过。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `make run`：release universal 构建、签名和启动通过。

**待确认**：
- [ ] Computer Use 可读取已启动 App 状态，但点击工具未成功绑定到该进程；真实背景点击需要你在本机窗口中再复核一次。

## 活跃度卡片空白点击复位 - 2026-06-14

**目标**：修复输入活跃度选中某一天后，点击卡片内空白区域不能回到默认首页状态的问题。

**设计决策**：保留热力图方块点击选中日期的交互，在整张活跃度卡片的透明背景层增加空白点击处理，并统一走 `restoreDefaultDashboardFocusFromActivityBlankTap()` 恢复默认统计和历史范围。原因是用户对“空白处”的理解覆盖标题区、右侧留白、网格留白和底部图例附近，而旧实现只覆盖了网格内部透明区域。

**偏差说明**：本轮不改变热力图颜色、日期选中样式或“清除”按钮，只扩大清除选中态的点击热区。

**权衡分析**：
- 方案一：继续只保留“清除”按钮。优点是行为显式；缺点是不符合卡片选中态点击空白复位的自然预期。
- 方案二：让整张卡片背景接收空白点击。优点是符合当前截图中的使用预期；缺点是需要确保不会抢走方块按钮点击。
- 选择方案二，因为透明背景位于内容之后，方块和按钮仍优先处理自己的点击。

**验证结果**：
- 先运行 `swift test --filter HomeDashboardViewModelTests/testActivityBlankTapRestoresDefaultDashboardState`，确认因缺少复位入口失败。
- 实现后同一测试通过，覆盖空白点击后恢复默认统计标题、总字数和历史列表。
- `swift test --filter HomeDashboardViewModelTests`：12 项通过。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。

## 风格页宽度、元气 Emoji 与全局活跃度复位 - 2026-06-14

**目标**：修复风格编辑页右侧预览被窗口裁切、元气风格不能自然使用 emoji，以及活跃度日期筛选只能在卡片局部复位的问题。

**设计决策**：风格菜单宽度从 300 缩到 220，Markdown 与预览面板最低宽度从 300 缩到 240；元气风格将是否使用 emoji、具体 emoji 和数量交给 AI 根据语境自行判断，只约束自然使用且不要堆叠，并将旧版无 emoji prompt 和带数字限制的 prompt 纳入升级名单；在 `MainShellView` 安装应用级左键按下监视器，任何应用内点击先清除日期筛选，热力图方块随后仍可通过按钮动作重新选中日期。

**偏差说明**：不强制元气风格每次添加 emoji，也不覆盖用户自行修改过的内置 prompt。应用级点击仅复位活跃度日期筛选，不清理搜索条件或其它页面状态。

**权衡分析**：
- 风格页继续保持双栏编辑/预览，不改成标签页；缩短风格菜单和最低面板宽度即可解决最小窗口裁切。
- 全局复位使用 AppKit 本地鼠标事件而非多层 SwiftUI 手势，原因是它能覆盖侧栏和全部内容区域，且鼠标按下清除、方块按钮鼠标释放后重新选择的顺序稳定。

**验证结果**：
- 三项新增行为均完成红绿循环：布局常量、应用级点击复位、元气 emoji 与旧 prompt 升级。
- `swift test --skip-build --filter 'HomeDashboardViewModelTests|StyleViewLayoutTests|StyleViewModelTests|PromptBuilderTests|LegacyConfigurationMigratorTests'`：35 项通过。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `git diff --check`：通过。
- 完整测试 target 被并行改动中的 `KeyMonitorTests` 阻塞：当前引用不存在的 `ShortcutActionRouting`。
- `make run` 被并行改动中的 `AppDelegate.swift` 快捷键闭包触发 Swift release 编译器诊断失败；裸 debug 可执行文件因缺少 app bundle 隐私声明上下文被 macOS TCC 终止，因此本轮未完成真实像素验收。
- emoji 自主决策调整后，`swift build -c debug -Xswiftc -warnings-as-errors` 和源码约束检查通过；正式单测仍被并行改动中的 `DictationOrchestratorTests.swift:201` 编译错误阻塞。

## 帮我说快捷键与 HUD 运行时接通 - 2026-06-14

**目标**：修复“帮我说”快捷键按下无反应、录音 HUD 不出现的问题，并确认是否由系统权限导致。

**设计决策**：让 `KeyMonitor` 同时按动作路由听写和帮我说快捷键；帮我说复用现有听写录音状态机与 HUD，转写完成后交给独立 handler 执行上下文采集、应用风格选择、LLM 生成和仅复制输出。VoiceInput 窗口在前台时仍拦截已配置快捷键，只有用户正在录制新快捷键时才临时放行给设置页。

**偏差说明**：第一期上下文采集仍以 Accessibility 为主，运行时传入 `visionSupported: false`，因此当前帮我说不要求屏幕录制权限。真实自动化使用无声录音验证入口与 HUD，未向外部 LLM 发送有效语音内容。

**权衡分析**：
- 方案一：为帮我说另建一套录音与 HUD 控制器。优点是隔离；缺点是重复录音生命周期和错误处理。
- 方案二：复用 `DictationOrchestrator`，仅在转写后按模式分流。优点是按住、松开、短按、HUD 和权限行为一致。
- 选择方案二，因为两个动作的差异从转写完成后才开始。

**验证结果**：
- 麦克风、辅助功能和屏幕录制权限均已授权，根因不是权限，而是帮我说未接入生产快捷键与录音协调器。
- `swift test`：417 项执行，2 项跳过，0 失败。
- `make debug`：warnings-as-errors 构建通过。
- `make run`：release universal 构建、签名和启动通过。
- 真实注入右 Option 后，系统日志确认麦克风录音启动和停止；全屏截图确认底部“正在聆听…” HUD 出现。
- 无声录音失败以 `agentCompose` 任务写入 `voice_tasks`，错误为 `No speech detected`，恢复数据未丢失。

**待确认**：
- [ ] 使用真实语音完成一次上下文 + LLM + 剪贴板端到端验收。

## 帮我说历史记录接入 - 2026-06-14

**目标**：修复“帮我说”任务已经执行并落盘，但首页历史不可见、无法点击查看的问题。

**设计决策**：首页历史同时读取普通听写表和 `voice_tasks` 中的 `agentCompose` 任务，统一按时间排序、搜索和日期筛选；帮我说记录保留独立标记，详情页提供复制结果，不展示普通听写的重新处理入口。

**偏差说明**：没有迁移或复制既有任务数据，避免形成双份历史；失败任务仍保留在 `voice_tasks`，本次只接入已有历史展示与删除路径。

**权衡分析**：
- 直接合并两类历史视图模型，改动较小，并保持两套持久化职责不变。
- 未将帮我说写入 `dictation_history`，因为任务状态、上下文和输出结果属于 `voice_tasks` 的恢复语义。

**验证结果**：
- 新增仓储、列表详情、复制删除和帮我说空状态文案测试，完成红绿循环。
- `swift test`：422 项执行，2 项跳过，0 失败。
- `make debug`：warnings-as-errors 构建通过。
- 真实应用首页显示“帮我说”记录；点击后打开“帮我说详情”，可复制生成结果。

## HUD 尾部、中文纠错提示词与智能配置弹层 - 2026-06-14

**目标**：保证长听写始终显示最新尾部，增强元气风格实际改写效果，并修复智能配置无法关闭。

**设计决策**：HUD 先保留最后 48 个字符，再使用字符换行且关闭末行截断；纠错基础提示词改为全中文，加入强制差异检查和中文示例，风格冲突时以所选风格优先；元气温度改为 0.6，并迁移仍使用内置旧 prompt 的数据库记录；若有风格的模型首次逐字回显，管线会用更短的 system 指令和带任务要求的 user 消息自动重试；智能配置改为应用内 overlay，提供右上角关闭和遮罩点击关闭。

**偏差说明**：保留用户自定义过的内置 prompt，不强制覆盖；真实 App 调用证明旧单次请求即使使用中文 prompt、0.6 温度和 pro 模型仍可能逐字回显，因此增加应用侧回显检测与重试。

**权衡分析**：
- 继续使用系统 sheet 无法实现背景点击关闭；自定义 overlay 需要维护尺寸，但交互可控。
- 低温度更稳定但容易原样返回；元气风格使用 0.6，让模型在事实约束内有足够调整空间。

**验证结果**：
- 聚焦测试覆盖 HUD、中文 prompt、温度迁移、模型回显重试和弹层关闭策略。
- `swift build -Xswiftc -warnings-as-errors`、`git diff --check`、`make run` 均通过。
- 原生 App 实测右上角关闭和遮罩空白点击都能关闭弹层。
- 真实 App trace 确认中文 prompt、0.6 温度和 pro 模型均正确发出；启动后数据库也已保存自主 emoji prompt。

## 反馈弹层、Agent Trace 与菜单栏图标修复 - 2026-06-14

**目标**：修复 Provider 保存 toast 位置不统一、详情弹层关闭闪烁、VoiceInput 前台吞掉双 Command 截图事件、帮我说详情缺少模型请求 trace、内部 warning code 裸露、HUD 黑块残留和菜单栏未显示 App 图标的问题。

**设计决策**：Provider 编辑 sheet 不再内嵌 `ActionFeedbackView`，保存后由页面顶层反馈层展示；历史详情 overlay 关闭不再做全局 opacity 动画，避免 modal 背景闪烁。`KeyMonitor` 在 VoiceInput 自身前台时直接放行快捷键事件，后台才作为全局语音触发器。Agent Compose 调用 LLM 前清理旧 trace，成功或失败后把 `TextProcessingTrace` 写入 `voice_tasks.trace_json`，首页详情从 VoiceTask 解码同一份 trace。菜单栏图标优先加载 `AppIcon.icns`，灰色图标设置继续通过 template 渲染。

**偏差说明**：“帮我说/帮我回微信”仍然不会自动发送微信消息；这遵循 OpenSpec 的 copy-only 边界。修复后能看到发给模型的内容，并且输出只复制到剪贴板，需要用户手动粘贴或发送。

**权衡分析**：
- 方案一：为 Provider sheet 保留局部 toast。优点是测试连接时反馈离操作近；缺点是和其它页面全局 toast 不一致，也导致截图中的位置错误。
- 方案二：统一使用页面级 toast。优点是位置一致、保存后不会卡在表单内部；缺点是 sheet 内测试反馈不再有局部提示。
- 选择方案二，因为当前主要问题是保存成功反馈位置错误，且项目已有 `ActionFeedbackView` 顶层 overlay 模式。

**验证结果**：
- `swift test --filter 'KeyMonitorTests|ContextAwareWorkflowIntegrationTests/testAgentComposePersistsLLMTraceForDetailInspection|HomeDashboardViewModelTests/testAgentComposeDetailDecodesSavedLLMTrace|HomeHistoryDetailPresentationTests|LLMProviderViewPresentationTests'`：19 项通过，覆盖前台快捷键放行、Agent trace 落库与详情解码、warning 展示文案、标准操作图标。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。

**待确认**：
- [ ] 需要用真实 `.app` 重新打开后手工复核菜单栏 AppIcon、HUD 黑块是否消失，以及 Provider sheet 内“测试连接”的反馈是否需要单独设计为 sheet 级提示。

## App 前台快捷键与 Esc 取消修复 - 2026-06-14

**目标**：修复 VoiceInput 应用窗口内按 Command 仍触发听写，以及录音时按 Esc 无法取消的问题。

**设计决策**：`KeyMonitor` 的放行判断从只看 `NSApp.isActive` 扩展为 `NSApp.isActive || frontmostApplication == VoiceInput`，避免 CGEvent tap 回调里应用活跃状态短暂不稳时仍吞掉 Command。录音期间同时安装 `NSEvent.addLocalMonitorForEvents` 和 global monitor：local monitor 负责 VoiceInput 自己窗口内的 Esc，global monitor 负责其它前台应用里的 Esc。

**偏差说明**：前台放行意味着 VoiceInput 自己窗口内不再用全局 Command 快捷键开始听写；这是为了避免设置页/工作台和系统快捷键被抢。后台和其它应用中仍保持原来的全局听写触发。

**权衡分析**：
- 方案一：只保留 global Esc monitor。优点是代码少；缺点是 macOS global monitor 不接收本应用内部事件，无法解决当前问题。
- 方案二：local + global 双 monitor。优点是覆盖本应用和外部应用；缺点是需要在停止录音时同时移除两个 monitor。
- 选择方案二，因为它对应 AppKit 的事件分发模型，且改动边界清晰。

**验证结果**：
- `swift test --filter 'KeyMonitorTests|AppDelegateEventRoutingTests'`：12 项通过，覆盖 VoiceInput frontmost 时放行 Command、后台捕获快捷键、Esc key code 识别。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。

**待确认**：
- [ ] 需要用真实 `.app` 在 VoiceInput 窗口内按 Command 和录音时按 Esc 做一次手工验证。

## Agent Compose 请求预览语义修正 - 2026-06-14

**目标**：修正“帮我回微信”被误解为微信专属或仅 copy-only 的问题，让详情页清楚展示 Agent Compose 实际发送给模型的是“当前应用上下文 + 用户语音意图”，且适用于任意前台应用。

**设计决策**：普通听写的请求预览继续只显示 user message，避免暴露纠错 system prompt；`agentCompose` 的请求预览改为展示全部非空 message，并带 role 分组，因此能看到 Target application、窗口可见文本和 User's dictation intent。详情页 Agent Compose 文案同步从“纠错/原文”调整为“生成/语音意图”。

**偏差说明**：copy-only 只约束输出动作，不约束生成能力；Agent Compose 仍会调用 LLM 理解上下文并生成回复，只是不自动粘贴、回车或发送。

**权衡分析**：
- 方案一：所有任务都展示完整 messages。优点是一致；缺点是普通听写会暴露大量内部纠错 prompt，信息噪声更高。
- 方案二：按任务模式区分预览。优点是普通听写保持简洁，Agent Compose 显示上下文证据；缺点是预览函数多一个 `taskMode` 参数。
- 选择方案二，因为这正好对应两个模式的用户心智差异。

**验证结果**：
- `swift test --filter HomeHistoryDetailPresentationTests`：7 项通过，覆盖普通听写只显示用户文本、Agent Compose 显示上下文和意图。
- `swift test --filter 'HomeHistoryDetailPresentationTests|HomeDashboardViewModelTests|ContextAwareWorkflowIntegrationTests|AgentPromptBuilderTests|AgentComposeTests|OutputServiceTests'`：57 项通过，覆盖通用 Agent Prompt、copy-only 输出和详情 trace 解码。

**待确认**：
- [ ] 需要在真实应用里打开一条带上下文的“帮我说”历史，确认“发送给模型的内容”符合预期。

## 首页目标卡片与菜单栏显示修复 - 2026-06-14

**目标**：移除首页中容易被误解为 `/goal` 的目标进度卡片，并恢复右上角菜单栏中清晰可见的 VoiceInput 状态项。

**设计决策**：首页删除 `GoalProgressCard` 及对应日目标统计字段，保留累计字符、今日字符、平均字/分钟和连续使用四个核心统计。菜单栏改用 `StatusBarIcon` 统一生成模板麦克风图标，并在状态项中显示 `VoiceInput` 文本，避免 bundle 图标加载或彩色渲染导致菜单栏不可见。

**偏差说明**：没有继续保留隐藏的日目标设置入口；当前产品没有设置页来管理该目标，保留会继续造成误解。

**权衡分析**：
- 方案一：保留目标卡片但改文案。优点是改动小；缺点是没有真实可配置目标，仍会让用户困惑。
- 方案二：直接移除目标卡片和相关统计字段。优点是首页更聚焦；缺点是未来若要做目标管理需重新设计设置入口。
- 选择方案二，因为当前问题是误导性 UI，而不是目标文案不够清楚。

**验证结果**：
- `swift test --filter StatusBarIconTests`：先红后绿，覆盖菜单栏标题、图标位置、模板图标、尺寸和可访问描述。
- `swift test --filter 'StatusBarIconTests|HomeDashboardViewModelTests'`：18 项通过。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `make run`：release universal 构建、签名和启动通过。
- Computer Use 实测：VoiceInput 首页不再显示目标进度卡片；右上角状态项存在，Accessibility 中 `menu bar 2` 的项目名和描述均为 `VoiceInput`，状态菜单包含语言、语音识别引擎、打开工作台、设置和退出入口。

**待确认**：
- [ ] 如果后续仍需要每日目标，应先补设置入口和目标语义，再恢复首页卡片。

## 请求 JSON 展开与纠错提示词修复 - 2026-06-14

**目标**：修复详情页“查看完整请求 JSON”点击右侧空白无法展开/收起，并去掉会强制改写的提示词措辞。

**设计决策**：将 SwiftUI `DisclosureGroup` 替换为自定义整行 `Button`，让标题行空白区域也成为点击热区；纠错基础提示词和 echo retry 提示词都改为“有明确问题才修正，没有可确认问题可保持原文”，避免为了制造差异而改写。

**偏差说明**：历史记录里已经保存的旧 request JSON 不会被 retroactive 修改；重新处理或新请求会使用新提示词。

**验证结果**：
- `swift test --filter 'PromptBuilderTests|TextProcessingPipelineTests/testPipelineRetriesWhenStyledModelEchoesInput|HomeHistoryDetailPresentationTests'`：21 项通过。
- `swift build -c debug -Xswiftc -warnings-as-errors`：通过。
- `make run`：release universal 构建、签名和启动通过。
- Computer Use 实测：点击“查看完整请求 JSON”标题行右侧空白可展开，再次点击空白可收起。
