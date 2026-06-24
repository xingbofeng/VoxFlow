# Selection Actions Third-Party Maintenance

本文件维护“划词动作 / 文本结果面板 / 文本转换链路”相关开源代码搬运与参考来源。原则：许可证兼容时能原样搬运就原样搬运；不能原样搬运时，必须写明原因、替代方案和本地测试覆盖。搬运后保留上游版权、许可证、commit 和本地修改说明。

## 维护规则

- 每次搬运代码必须记录上游仓库、许可证、上游文件、上游 commit、本地文件、修改点。
- GPL-3.0 兼容代码可以纳入 VoxFlow，但必须保留上游版权声明。
- MIT 代码可以纳入 VoxFlow，但必须保留许可证声明。
- GPL-2.0-only 代码不直接搬运进 GPL-3.0 项目；只参考行为与测试思路。
- 修改搬运代码时，在“本地修改点”写明原因，避免未来同步困难。
- “参考”不是默认选项。只有满足以下任一条件，才允许不直接搬运：
  - 许可证不兼容或上游授权不明确。
  - 上游技术栈/运行时无法进入 Swift/AppKit 进程，且桥接成本明显高于重写。
  - 上游代码强绑定插件、Tauri、Qt、Electron、私有 API 或外部宿主能力。
  - v1 明确不做该能力，例如 PDF 清洗、外部 HTTP API、插件市场。
  - VoxFlow 已有同职责模块，直接搬运会破坏现有架构边界。
- 每个“部分搬运 / 只参考”的条目都必须在表格里写明“不直接搬运原因”；实现时不能只写“参考某项目”。

## 搬运决策口径

| 决策 | 什么时候使用 | 本地要求 |
| --- | --- | --- |
| 直接搬运 | 上游代码许可证兼容、平台一致、职责单一，复制后只需要改命名或轻量 adapter | 保留上游文件头、commit、许可证；本地文件顶部写 `Adapted from ...`；补 VoxFlow 行为测试 |
| 结构性搬运 | 上游状态机/分支顺序成熟，但依赖上游单例、插件宿主、配置系统或 UI 框架 | 保留流程顺序和失败语义；把依赖替换成 VoxFlow 协议；在同步记录说明未搬的类型和原因 |
| 部分搬运 | 上游技术栈不同，源码不能直接进入 Swift/AppKit，但 action schema、路由表、测试场景可复用 | 搬接口形状、命名、状态分支或测试场景；不得只写“参考”；必须列出不直接搬源码的原因 |
| 只参考 | 非开源、许可证不兼容、v1 明确不做，或直接搬会新增外部服务/攻击面 | 不复制源码；只记录产品模式、后续方向或测试启发 |

当前判断不是“懒得搬”。只要满足直接搬运条件，就优先搬；不满足时才降级为结构性搬运、部分搬运或只参考。

## 当前搬运决策总表

| 来源项目 | 决策 | 当前状态 | 为什么不是更高等级搬运 | 必须保留的上游行为 |
| --- | --- | --- | --- | --- |
| Easydict `SelectionWorkflow.swift` | 结构性搬运 | 已落地到 `SelectionTextProvider.swift` | 上游依赖 `SelectedTextKit`、`Defaults`、`PasteboardManager` 和应用单例；VoxFlow 需要接现有剪贴板事务、设置和测试 adapter | AX 优先、复制 fallback、前台自身跳过 fallback、失败后恢复剪贴板 |
| Easydict `SystemUtility.swift` | 结构性搬运 | 已拆入 `SystemSelectionAcquisitionAdapter` 相关类型 | 上游系统工具是大杂烩，原样搬会把不相关能力带进 `SelectionActions` | focused element、快捷键 Copy、Menu Copy、Copy action 可用性判断 |
| Easydict `ActionManager.swift` | 部分搬运 | 已映射到 `SelectionActionDispatcher` 方向 | 上游 ActionManager 绑定 Easydict 翻译/润色 UI；VoxFlow 要复用 `TextTransformService` 和 `VoxFlowTextInsertion` | 选中文本进入动作后，结果可复制、替换、插入，失败可降级 |
| PopClip OpenAIChat / SmartTranslate | 部分搬运 | 已用于 action/output mode 设计 | 上游是 PopClip Extension TypeScript 配置，不能直接运行在 VoxFlow Swift/AppKit 进程 | selected text -> action -> copy/replace/append 的单一职责动作模型 |
| Pot `hotkey.rs` | 部分搬运 | 已用于快捷键分发设计 | 上游是 Rust/Tauri 全局热键体系；VoxFlow 已有 Swift 快捷键注册和冲突检测 | hotkey -> action 的路由表、动作命名和启用/禁用策略 |
| Pot `server.rs` | 只参考 | v1 不落地 | v1 明确不做外部 HTTP/API；直接搬会新增服务生命周期和攻击面 | endpoint/action 命名，留给后续 URL scheme 或本地 API |
| CopyTranslator | 只参考 | v1 不落地 | v1 不做 PDF 清洗；GPL-2.0-only 兼容性需要单独审计 | PDF 断行、多段共译、增量复制作为后续需求来源 |
| Crow Translate | 只参考 | v1 不落地 | v1 不做 CLI/API；跨技术栈直接搬收益低；不纳入源码，后续搬运前必须重新确认仓库 LICENSE | UI、快捷键、外部接口触发同一 action router 的边界 |
| Raycast | 只参考 | v1 不落地 | 商业产品/API 文档，无可搬源码 | selected text -> command -> paste/clipboard 的产品模式 |

## 搬运优先级

### P0：优先原样搬运或最小改名适配

这些代码解决的是 macOS 兼容性或动作模型的“坑位问题”。除非和 VoxFlow 架构明显冲突，否则不要重新发明。

P0 来源已在 2026-06-23 逐项确认：Easydict 当前 HEAD 为 `1376005e8455783d2db162cb7029f14cde932a9f`，PopClip Extensions 当前 HEAD 为 `9be40b0c21052e5d491fbcd1e2432c9f50be60d8`；下表 5 个上游文件在对应 commit 下均可通过 GitHub raw URL 打开（HTTP 200）。PopClip Extensions 仓库的许可证文件为 `LICENSE.txt`，README 声明源码使用 MIT License。

| 来源项目 | 许可证 | 上游文件/目录 | 要搬什么 | 本地计划落点 | 搬运策略 | 验证要求 |
| --- | --- | --- | --- | --- | --- | --- |
| Easydict | GPL-3.0 | `Easydict/Swift/Utility/EventMonitor/Workflow/SelectionWorkflow.swift` | 选中文本获取主流程、AX 优先、强制复制 fallback、失败恢复路径 | `Sources/VoxFlowApp/SelectionActions/SelectionTextProvider.swift` | 尽量保留状态机和 fallback 顺序；只改命名、日志、依赖注入 | TextEdit、Safari、Cursor/VSCode、微信、终端中至少覆盖成功和失败 fallback |
| Easydict | GPL-3.0 | `Easydict/Swift/Utility/SystemUtility/SystemUtility.swift` | focused element、菜单 Copy、快捷键模拟、App 特定策略判断 | `Sources/VoxFlowApp/SelectionActions/SelectionAcquisitionSystemAdapter.swift` | 抽成 VoxFlow adapter；避免绕过现有 pasteboard/insertion contract | 剪贴板备份/恢复测试；不污染用户剪贴板 |
| Easydict | GPL-3.0 | `Easydict/Swift/Feature/ActionManager/ActionManager.swift` | 选中文本进入动作、替换/插入/复制结果的编排思路 | `Sources/VoxFlowApp/SelectionActions/SelectionActionDispatcher.swift` | 可结构性搬运，不搬 UI；结果输出改接 VoxFlow `OutputService` / `VoxFlowTextInsertion` | 替换原文、插入下一行失败时降级复制 |
| PopClip Extensions | MIT | `source/OpenAIChat.popclipext/Config.ts` | selected text -> LLM -> copy/replace/append 的 action/output mode 模型 | `Sources/VoxFlowApp/SelectionActions/SelectionAction.swift` | 直接借鉴 action schema；Swift 化为 enum/struct | 动作卡只暴露翻译、总结、任务助手；output mode 只在结果面板出现 |
| PopClip Extensions | MIT | `contrib/SmartTranslate.popclipext/Config.ts` | “目标语言相同则润色，否则翻译”的 prompt 思路 | `Sources/VoxFlowApp/TextTransform/TextTransformPromptBuilder.swift` | 可搬 prompt 结构，但文案按 VoxFlow 翻译策略改写 | 中英混合、代码、URL、专名不被破坏 |

### P1：部分搬运，保留可复用结构并记录不直接搬运原因

这些项目技术栈或产品形态不同，直接贴代码可能引入不必要复杂度。优先搬结构、接口、测试场景；不能搬源码的原因必须写清楚。

| 来源项目 | 许可证 | 上游文件/目录 | 要搬什么 | 本地计划落点 | 不直接搬运原因 | 搬运策略 | 验证要求 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Pot Desktop | GPL-3.0 | `src-tauri/src/hotkey.rs` | hotkey -> action 分发表、动作命名方式、禁用/启用策略 | `Sources/VoxFlowApp/HotKey/HotKeyRoutingPolicy.swift` | 上游是 Rust/Tauri 全局热键体系，不能直接进入现有 Swift/AppKit HotKey 管理器 | 搬命名、分发表和测试场景；Swift 侧接现有快捷键注册 | `⌘⇧D` 与现有 `⌘⇧A`/`⌘⇧V`/语音快捷键冲突检测 |
| Pot Desktop | GPL-3.0 | `src-tauri/src/server.rs` | `/selection_translate` 等动作入口的路由思想 | v1 不落地；后续外部 API/URL scheme 再用 | v1 明确不做外部 HTTP/API；直接搬会新增攻击面和后台服务生命周期 | 只记录 endpoint 命名，后续做外部 API 时再评估源码搬运 | 确认 v1 无外部接口暴露 |
| Pot Desktop | GPL-3.0 | `src-tauri/src/config.rs` / action 配置相关文件 | action enable/disable、默认行为设置 | `Sources/VoxFlowApp/ViewModels/SettingsViewModel.swift` | 上游配置模型绑定 Tauri store；VoxFlow 已有 SettingsRepository / UserDefaults 边界 | 搬配置字段分组和默认值思路；实现按 VoxFlow 设置体系 | 应用设置新增“划词动作”页，不影响 AI 编程/通用 |
| Easydict | GPL-3.0 | Wiki / FAQ force selection 说明 | 强制获取选中文本的风险提示 | `Sources/VoxFlowApp/Views/SettingsRootView.swift` | 文档内容不应整段复制到 UI；需要压缩成 VoxFlow 设置页短提示 | 搬风险提示信息点，不照搬长文 | 设置页说明“可能短暂使用复制 fallback，会恢复剪贴板” |

### P2：只参考，不搬代码，原因必须可审计

| 来源项目 | 许可证/性质 | 参考点 | 不搬原因 | v1 处理 |
| --- | --- | --- | --- | --- |
| CopyTranslator | GPL-2.0 | PDF 断行清洗、多段共译、增量复制 | v1 不做 PDF；GPL-2.0-only 与 GPL-3.0 兼容性需谨慎 | 不搬代码，不进 v1 |
| Crow Translate | 不纳入源码，后续搬运前确认仓库 LICENSE | CLI/API 化动作边界、快捷键矩阵 | v1 不做外部接口；跨技术栈收益有限 | 只记录后续参考 |
| Raycast | 商业产品/API 文档 | selected text -> command -> paste 交互模式 | 非开源可搬代码；只参考产品模式 | 不搬代码 |

## 具体实现前检查清单

实现每个“搬运”任务前，先完成以下检查：

1. 记录上游仓库 URL、许可证 URL、具体 commit hash。
2. 下载或复制上游文件时保留原始 copyright/license header。
3. 在本地文件顶部增加 `Adapted from ...` 注释，写明上游路径和 commit。
4. 若删除上游代码中的功能分支，在本文件“同步记录”说明删减原因。
5. 为搬运代码补 VoxFlow 行为测试，不能只依赖“上游应该是对的”。
6. 若上游代码依赖私有 extension/helper，优先一并搬必要 helper；不要用临时字符串/硬编码替代。
7. 搬运后更新 `docs/third-party-licenses.md`。

## 功能到开源来源映射

| VoxFlow 能力 | 首选来源 | 次选来源 | 自研范围 |
| --- | --- | --- | --- |
| 获取选中文本 | Easydict `SelectionWorkflow.swift` | SelectedTextKit | 只做 VoxFlow adapter 和测试 |
| Cmd+C fallback | Easydict `SelectionWorkflow.swift` / `SystemUtility.swift` | Easydict FAQ 场景 | 只接入现有剪贴板事务 |
| Menu Copy fallback | Easydict `SystemUtility.swift` | 无 | AppKit adapter |
| 剪贴板保护 | Easydict + VoxFlow `PasteboardTransaction` | 无 | 以 VoxFlow 现有实现为准 |
| 动作模型 | PopClip OpenAIChat/SmartTranslate | Pot action router | Swift enum/struct |
| 结果输出模式 | PopClip copy/replace/append | Raycast paste 模式 | 接 VoxFlow `OutputService` |
| 快捷键分发 | Pot `hotkey.rs` | VoxFlow 现有 HotKeyRoutingPolicy | 保持现有 Swift 路由 |
| 外部 action API | Pot `server.rs` | Crow Translate CLI/API | v1 不做 |
| PDF 清洗 | CopyTranslator | 无 | v1 不做 |

## 同步记录

| 日期 | 来源项目 | 上游 commit | 上游文件 | 本地文件 | 修改摘要 | 验证 |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-06-23 | Easydict | `1376005e8455783d2db162cb7029f14cde932a9f` | `Easydict/Swift/Utility/EventMonitor/Workflow/SelectionWorkflow.swift` | `Sources/VoxFlowApp/SelectionActions/SelectionTextProvider.swift` | 结构性搬运 AX 优先、强制复制 fallback、前台为自身时跳过 fallback 的策略顺序；未搬 Easydict 单例/Defaults/SelectedTextKit 类型，改为 VoxFlow 协议适配；剪贴板恢复使用 VoxFlow `PasteboardSnapshot`，因为 `PasteboardTransaction` 面向写入粘贴，不适合复制 fallback 后恢复 | `swift test --filter SelectionTextProviderTests` |
| 2026-06-23 | Easydict | `1376005e8455783d2db162cb7029f14cde932a9f` | `Easydict/Swift/Utility/SystemUtility/SystemUtility.swift` | `Sources/VoxFlowApp/SelectionActions/SelectionTextProvider.swift` | 结构性搬运 focused element、快捷键 Copy、Menu Copy、前台 App 判断和 Copy action 可用性判断；未搬 SystemUtility 的无关系统工具方法，改为 `SelectionAcquisitionSystemAdapter`、`SelectionCopyPerforming`、`SelectionMenuActionSending`、`SelectionAppContextProviding` 等协议 | `swift test --filter SelectionTextProviderTests` |
| 2026-06-24 | Easydict | `1376005e8455783d2db162cb7029f14cde932a9f` | `Easydict/Swift/Utility/EventMonitor/Workflow/SelectionWorkflow.swift`; `Easydict/Swift/Utility/SystemUtility/SystemUtility.swift` | `Sources/VoxFlowApp/SelectionActions/SelectionTextProvider.swift`; `Sources/VoxFlowApp/App/AppDelegate.swift`; `Sources/VoxFlowApp/FeatureBridges/ContextPipeline.swift` | 补齐 v1 方案遗漏：用户触发的划词入口启用强制复制 fallback；VSCode/Xcode/Cursor 等编辑器明确走快捷键优先；Safari/Chromium 浏览器先尝试 AppleScript `window.getSelection()`，失败再退回复制；AX `selectedText` 为空时使用 `selectedRange + value` 切片 | `swift test --filter SelectionTextProviderTests`; `swift test --filter ContextPipelineTests`; `swift test --filter AppDelegateEventRoutingTests` |
| 2026-06-23 | Easydict | `1376005e8455783d2db162cb7029f14cde932a9f` | `Easydict/Swift/Feature/ActionManager/ActionManager.swift` | `Sources/VoxFlowApp/SelectionActions/SelectionActionDispatcher.swift`; `Sources/VoxFlowApp/SelectionActions/SelectionResultViewModel.swift` | 部分搬运“选中文本进入动作后再输出到复制/替换/插入”的编排语义；未搬 Easydict 翻译/润色 UI、服务选择和单例状态，改接 VoxFlow `TextTransformService`、`TextInserting` 与结果面板 | `swift test --filter SelectionResultViewModelTests` |
| 2026-06-23 | PopClip Extensions | `9be40b0c21052e5d491fbcd1e2432c9f50be60d8` | `source/OpenAIChat.popclipext/Config.ts` | `Sources/VoxFlowApp/SelectionActions/SelectionAction.swift`; `Sources/VoxFlowApp/SelectionActions/SelectionResultViewModel.swift` | 部分搬运 selected text -> action -> copy/replace/append 的 output mode 模型；未复制 TypeScript 源码，因为 PopClip extension runtime、options schema 和 pasteboard API 不能直接进入 VoxFlow Swift/AppKit 进程 | `swift test --filter SelectionResultViewModelTests` |
| 2026-06-23 | PopClip Extensions | `9be40b0c21052e5d491fbcd1e2432c9f50be60d8` | `contrib/SmartTranslate.popclipext/Config.ts` | `Sources/VoxFlowApp/TextTransform/TextTransformService.swift` | 部分搬运“同语言则润色，否则翻译”的 prompt 策略；未复制 prompt 文案，改写为 VoxFlow 的简体中文、代码/URL/Markdown 保留策略 | `swift test --filter TextTransformServiceTests` |
