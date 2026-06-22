# 易错词目标词 UI 与维护策略方案

> **给 agentic workers：** 本文是新版 `易错词` 的执行方案。实现时必须按本文任务清单推进，优先写单元测试和 targeted tests；不要每做一个小步骤就提交，最终提交前再做完整验收。

## 目标

把当前偏工程化的 `原文 -> 替换为` 规则表，升级为用户能理解的 `目标词 + 误听写法` 管理体验，同时继续沿用 TypeWhisper 的 GPLv3 `terms + corrections + focused observation` 思路。

完成后用户看到的是：

```text
目标词：Qwen
误听写法：q 问、Q问、去问、queue win
```

底层仍然使用确定性 correction rules：

```text
q 问 -> Qwen
Q问 -> Qwen
去问 -> Qwen
queue win -> Qwen
```

OCR Context Boost 继续只作为本次 LLM 纠错的临时热词，不写入易错词，不进入 correction engine，不参与永久学习。

## 背景与问题

当前 `易错词` 页展示的是规则表：

```text
原文 | 替换为 | 作用范围 | 状态 | 应用次数
```

这个模型符合第一期技术实现，但产品心智有明显问题：

- 用户需要先知道 ASR 错成什么，才能维护规则；
- 页面看起来像旧 `文本替换` 的升级版，不像 `易错词`；
- `原文 / 替换为 / 匹配方式` 暴露了 engine 细节；
- `待确认候选` 卡片会打扰用户，也容易让用户感觉系统在监视输入；
- OCR 临时上下文和长期易错词容易被混淆。

新版改造要解决这些问题，但不推翻现有 correction engine。

## 关键决策

### 1. 继续沿用 TypeWhisper 的双层模型

TypeWhisper 的 Dictionary 分为：

- `term`：目标词 / 热词，用于帮助识别或 provider prompt；
- `correction`：后处理规则，形如 `original -> replacement`；
- 自动学习：通过 focused text observation 观察用户修改，抽取新的 correction。

VoxFlow 对应为：

- `CorrectionTargetTerm`：用户看到的目标词；
- `CorrectionRule`：误听写法到目标词的确定性替换规则；
- `CorrectionObservationCoordinator`：继续用 2 / 5 / 10 秒 focused observation 学习用户真实修改。

### 2. UI 是目标词库，engine 仍是 correction rules

UI 主列表展示目标词，不展示散落的规则：

```text
目标词 | 误听写法 | 作用范围 | 修正次数 | 最近使用 | 状态
```

选中目标词后，详情抽屉展示该目标词下的误听写法：

```text
Qwen

常见误听写法
- q 问       活跃   5 次
- Q问        活跃   3 次
- 去问       活跃   1 次
- queue win  活跃   4 次
```

### 3. 不在主页面展示待确认候选

自动学习默认直接生效。用户只看到轻提示：

```text
已学习：Q问 -> Qwen    撤销
```

如果用户在设置中关闭 `自动学习直接生效`，候选能力仍保留，但只进入目标词详情里的 `学习记录 / 未生效` 区域或历史详情，不放主页面统计卡片。

### 4. OCR 只做临时热词

OCR Context Boost 只参与这条链路：

```text
当前窗口 OCR
-> Top-K 临时热词
-> LLM prompt
```

OCR 不做：

- 不写 `CorrectionTargetTerm`；
- 不写 `CorrectionRule`；
- 不触发自动学习；
- 不保存完整 OCR 文本；
- 不进入 `VoiceCorrectionEngine`。

## 最终运行链路

```text
Start dictation
-> ASR final
-> 并行获得当前窗口 OCR Top-K 临时热词
-> LLM 纠错，prompt 中包含 OCR 临时热词
-> 易错词 deterministic correction
-> 插入文本
-> 2 / 5 / 10 秒 focused observation
-> 如果用户修改刚插入文本，抽取 correction
-> 归入目标词 aliases
-> 轻提示：已学习，可撤销
```

## 开源借鉴与 GPLv3 边界

### TypeWhisper

仓库：

```text
https://github.com/TypeWhisper/typewhisper-mac
```

许可证：

```text
GPLv3
```

当前方案允许在 GPLv3 履约前提下直接复制或改写必要源码，集中放在 VoxFlow 的易错词模块或独立 package 内，并维护来源说明、许可证和修改说明。

参考文件：

| TypeWhisper 文件 | VoxFlow 落点 | 用途 |
| --- | --- | --- |
| `TypeWhisper/Models/DictionaryEntry.swift` | `CorrectionTargetTerm.swift`、`CorrectionRule.swift` | term / correction 双模型、original / replacement、enabled、caseSensitive、counters |
| `TypeWhisper/Services/DictionaryService.swift` | repository + view model service + matcher 调用 | terms CRUD、corrections CRUD、apply corrections、learn corrections |
| `TypeWhisper/Services/TextDiffService.swift` | `HighConfidenceCorrectionExtractor.swift` 或后续 copy/adapt 文件 | 从用户修改里抽取 high-confidence `original -> replacement` |
| `TypeWhisper/Services/TargetAppCorrectionLearningService.swift` | `CorrectionObservationCoordinator.swift` | focused element baseline / recapture、2 / 5 / 10 秒轮询 |
| `TypeWhisper/Services/PostProcessingPipeline.swift` | `TextProcessingPipeline.swift` | LLM 后运行 dictionary corrections 的顺序 |
| `TypeWhisperTests/DictionaryServiceTests.swift` | VoxFlow voice correction tests | terms/corrections CRUD、apply、learn、empty replacement |
| `TypeWhisperTests/TextDiffServiceTests.swift` | VoxFlow learning extractor tests | high-confidence diff、rewrite 拒绝、歧义拒绝 |
| `TypeWhisperTests/TargetAppCorrectionLearningServiceTests.swift` | VoxFlow observation tests | fake observer / fake clock，不依赖真实 Accessibility 权限 |

需要更新：

- `Packages/VoxFlowVoiceCorrectionKit/SOURCE_ATTRIBUTION.md`
- `Packages/VoxFlowVoiceCorrectionKit/MODIFICATIONS.md`
- `docs/voice-correction/opensource-import-plan.md`

### FlashText

只借鉴 `clean target -> multiple aliases` 的产品数据组织思路，不复制运行时代码。

### OCR Context Boost

沿用 `Packages/VoxFlowContextBoostKit`：

- `TemporaryHotword`
- `HotwordExtractor`
- `HotwordRanker`
- `ContextBoostPromptSectionBuilder`

本方案不改变 OCR 的临时性边界。

## 数据模型

### CorrectionTargetTerm

新增目标词模型，代表用户想说对的长期词条。

```swift
public struct CorrectionTargetTerm: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var text: String
    public var normalizedText: String
    public var scope: RuleScope
    public var lifecycle: RuleLifecycle
    public var source: RuleSource
    public var observedCount: Int
    public var appliedCount: Int
    public var revertedCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var lastAppliedAt: Date?
}
```

约束：

- `text` 不能为空；
- `text` 最大长度沿用 `CorrectionRule.maximumTextLength`；
- `normalizedText` 用于去重，默认大小写不敏感；
- 手动创建目标词默认 `active`；
- 自动学习创建目标词默认跟随 `autoLearningAppliesImmediately`。

### CorrectionRule

在现有 rule 上增加可选关联：

```swift
public var targetID: UUID?
```

兼容策略：

- 旧数据没有 `targetID` 时仍可正常匹配；
- migration 按 `replacement` 自动生成目标词并回填；
- 如果同一 `replacement` 有不同 scope，优先生成 scope 更具体的 target，或者生成多个 scoped target。

### Projection

新增只读投影，供 UI 使用：

```swift
public struct CorrectionTargetProjection: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var target: CorrectionTargetTerm
    public var aliases: [CorrectionRule]
    public var aliasPreview: String
    public var appliedCount: Int
    public var lastAppliedAt: Date?
    public var lifecycle: RuleLifecycle
}
```

UI 不直接遍历原始 rules，而是使用 projection。

## 持久化设计

新增表：

```sql
CREATE TABLE IF NOT EXISTS voice_correction_targets (
  id TEXT PRIMARY KEY NOT NULL,
  text TEXT NOT NULL,
  normalized_text TEXT NOT NULL,
  scope_kind TEXT NOT NULL,
  scope_value TEXT,
  lifecycle TEXT NOT NULL,
  source TEXT NOT NULL,
  observed_count INTEGER NOT NULL DEFAULT 0,
  applied_count INTEGER NOT NULL DEFAULT 0,
  reverted_count INTEGER NOT NULL DEFAULT 0,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL,
  last_applied_at REAL
);
```

修改 `voice_correction_rules`：

```sql
ALTER TABLE voice_correction_rules ADD COLUMN target_id TEXT;
```

Migration：

1. 创建 `voice_correction_targets`；
2. 给 rules 增加 `target_id`；
3. 读取所有已有 rules；
4. 按 `replacement + scope` 分组；
5. 每组生成一个 target；
6. 回填该组 rules 的 `target_id`；
7. migration 幂等，重复运行不重复创建 target。

## UI 方案

### 主页面

标题：

```text
易错词
维护常被听错的专名、术语和写法；OCR 只作为本次临时上下文，不写入这里。
```

右上按钮：

```text
+ 新增目标词
```

顶部统计：

```text
目标词      72    长期个人词库
误听写法    128   手动添加与自动学习
本周修正    46    可在历史中撤销
```

不展示：

- Benchmark；
- Shadow Mode；
- 启用开关；
- 自动学习开关；
- 待确认候选卡片。

### 目标词库表格

标题：

```text
目标词库
先维护正确写法，再为它添加常见误听写法
```

搜索：

```text
搜索目标词或误听写法
```

过滤：

```text
全部 / 活跃 / 已暂停
```

列：

```text
目标词 | 误听写法 | 作用范围 | 修正次数 | 最近使用 | 状态 | 操作
```

示例：

```text
Qwen      | q 问、Q问、去问、queue win       | 全局     | 12 次 | 刚刚 | 活跃
VoxFlow   | vox flow、voice flow、沃克斯 flow | 全局     | 8 次  | 今天 | 活跃
AGENTS.md | agents dot md、agent md           | 当前项目 | 3 次  | 昨天 | 活跃
SwiftUI   | swift ui、swift u i               | 全局     | 5 次  | 本周 | 活跃
macOS     | mac os、麦克 os                   | 全局     | 4 次  | 本周 | 活跃
```

### 详情抽屉

选中目标词后展示右侧详情：

```text
Qwen
目标词

常见误听写法
q 问        活跃   5 次   ...
Q问         活跃   3 次   ...
去问        活跃   1 次   ...
queue win   活跃   4 次   ...

+ 添加误听写法

最近学习
Q问 -> Qwen    刚刚自动学习    撤销

高级设置 >
```

`高级设置` 默认折叠，里面才出现：

- 作用范围；
- 大小写敏感；
- 匹配方式；
- 暂停；
- 删除。

### 新增目标词 popover

点击 `+ 新增目标词` 后，不打开大 modal，而是轻量 popover：

```text
新增目标词

目标词
[ Qwen ]

常见误听写法（可选，每行一个）
[ q 问       ]
[ Q问        ]
[ queue win  ]

[取消] [保存]
```

保存行为：

- 创建 `CorrectionTargetTerm(text: "Qwen")`；
- 每个误听写法创建一个 `CorrectionRule(original: alias, replacement: "Qwen", targetID: target.id)`；
- 手动添加的 aliases 直接 active。

### 自动学习轻提示

自动学习成功后右下角展示轻提示：

```text
已学习：Q问 -> Qwen    撤销
```

规则：

- 3 秒自动消失；
- 不阻塞输入；
- 点击 `撤销` 删除刚学习的 alias；
- 如果 target 是本次自动创建且没有其他 alias，可以一起删除 target；
- 如果 toast 消失，仍可在详情抽屉 `最近学习` 中撤销。

## 自动学习策略

沿用 TypeWhisper focused observation：

```text
插入前：记录 focused element baseline
插入后：记录 insertedText
2 / 5 / 10 秒：recapture 同一个 focused element
如果用户修改了刚插入内容：抽取 high-confidence correction
```

示例：

```text
系统插入：我觉得 Q问 这个模型不错
用户改成：我觉得 Qwen 这个模型不错
```

生成：

```text
Q问 -> Qwen
```

归组：

1. 如果已有 target `Qwen`，将 `Q问` 加入该 target；
2. 如果没有 target `Qwen`，自动创建 target；
3. 如果 `autoLearningAppliesImmediately = true`，alias 直接 active；
4. 如果 `autoLearningAppliesImmediately = false`，alias 保存为 candidate，但只在详情 / 历史里显示，不进主页面卡片。

拒绝学习：

- secure field；
- focused element 变化；
- 大规模 rewrite；
- insertion-only / deletion-only；
- 只有大小写或标点变化；
- 单字高歧义 CJK；
- 和已应用 correction 的范围重叠导致 feedback loop；
- OCR raw text 或 OCR hotwords 本身。

## 冲突策略

同一个 alias 不能静默指向多个 target。

示例：

```text
q 问 -> Qwen
q 问 -> 去问
```

处理：

1. 手动操作优先；
2. App scope 优先于 global；
3. 最近用户确认优先；
4. 高 confidence 优先；
5. 无法确定时不自动替换，保留旧 active rule，把新 rule 记录为未生效学习记录。

UI 提示：

```text
"q 问" 已属于 Qwen，要移动到 去问 吗？
```

该提示只出现在用户手动编辑时；自动学习不弹强提示。

## OCR 边界

OCR Context Boost 继续保持：

```text
OCR -> TemporaryHotword -> PromptBuilder -> LLM
```

禁止：

- OCR 直接创建 target；
- OCR 直接创建 alias；
- OCR 写入 correction repository；
- OCR text 写入 production log；
- OCR 触发自动学习。

允许：

- 历史详情展示本次 `ContextBoostTrace.hotwords`；
- LLM prompt 包含 Top-K 临时热词；
- 用户最终修改插入文本后，focused observation 可以学习用户修改。学习来源是用户修改，不是 OCR。

## 需要改的文件

### Core package

- 修改：`Packages/VoxFlowVoiceCorrectionKit/Sources/VoxFlowVoiceCorrection/Core/CorrectionRule.swift`
- 新增：`Packages/VoxFlowVoiceCorrectionKit/Sources/VoxFlowVoiceCorrection/Core/CorrectionTargetTerm.swift`
- 新增：`Packages/VoxFlowVoiceCorrectionKit/Sources/VoxFlowVoiceCorrection/Core/CorrectionTargetProjection.swift`
- 修改：`Packages/VoxFlowVoiceCorrectionKit/Sources/VoxFlowVoiceCorrection/Learning/LearningPolicy.swift`
- 修改：`Packages/VoxFlowVoiceCorrectionKit/SOURCE_ATTRIBUTION.md`
- 修改：`Packages/VoxFlowVoiceCorrectionKit/MODIFICATIONS.md`

### Persistence

- 修改：`Sources/VoxFlowApp/Persistence/AppDatabase.swift`
- 修改：`Sources/VoxFlowApp/VoiceCorrection/Persistence/CorrectionRuleRecord.swift`
- 修改：`Sources/VoxFlowApp/VoiceCorrection/Persistence/SQLiteCorrectionRuleRepository.swift`
- 新增：`Sources/VoxFlowApp/VoiceCorrection/Persistence/CorrectionTargetRecord.swift`
- 新增：`Sources/VoxFlowApp/VoiceCorrection/Persistence/SQLiteCorrectionTargetRepository.swift`

### Observation / learning

- 修改：`Sources/VoxFlowApp/VoiceCorrection/Observation/CorrectionObservationCoordinator.swift`
- 可新增：`Sources/VoxFlowApp/VoiceCorrection/Observation/LearnedCorrectionUndoService.swift`

### UI

- 修改：`Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionViewModel.swift`
- 修改：`Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionView.swift`
- 可新增：`Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionToastView.swift`
- 可新增：`Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionTargetEditor.swift`
- 可新增：`Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionTargetDetailView.swift`

### OCR / LLM boundary

- 修改测试为主：`Sources/VoxFlowApp/TextProcessingBridges/TextProcessingPipeline.swift`
- 修改测试为主：`Sources/VoxFlowApp/TextProcessingBridges/PromptBuilder.swift`
- 不改或仅文案：`Sources/VoxFlowApp/TextProcessingBridges/ContextBoostSettings.swift`

### Settings

- 检查：`Sources/VoxFlowApp/Views/SettingsRootView.swift`
- 检查：`Sources/VoxFlowApp/ViewModels/SettingsViewModel.swift`

设置页继续承载：

- 启用易错词修正；
- 自动学习候选词；
- 自动学习直接生效；
- 影子模式；
- OCR 当前窗口临时上下文。

主页面不放这些开关。

### Tests

- 新增：`Packages/VoxFlowVoiceCorrectionKit/Tests/VoxFlowVoiceCorrectionTests/CorrectionTargetTermTests.swift`
- 新增：`Packages/VoxFlowVoiceCorrectionKit/Tests/VoxFlowVoiceCorrectionTests/CorrectionTargetProjectionTests.swift`
- 修改：`Packages/VoxFlowVoiceCorrectionKit/Tests/VoxFlowVoiceCorrectionTests/CorrectionRuleValidationTests.swift`
- 修改：`Packages/VoxFlowVoiceCorrectionKit/Tests/VoxFlowVoiceCorrectionTests/LinearRuleMatcherTests.swift`
- 新增：`Tests/VoxFlowAppTests/VoiceCorrection/SQLiteCorrectionTargetRepositoryTests.swift`
- 修改：`Tests/VoxFlowAppTests/VoiceCorrection/SQLiteCorrectionRuleRepositoryTests.swift`
- 修改：`Tests/VoxFlowAppTests/VoiceCorrection/VoiceCorrectionViewModelTests.swift`
- 修改：`Tests/VoxFlowAppTests/VoiceCorrection/VoiceCorrectionViewPresentationTests.swift`
- 修改：`Tests/VoxFlowAppTests/VoiceCorrection/TextProcessingPipelineVoiceCorrectionTests.swift`
- 修改：`Tests/VoxFlowAppTests/TextProcessingBridges/PromptBuilderTests.swift`
- 修改：`Tests/VoxFlowAppTests/TextProcessingBridges/TextProcessingPipelineTests.swift`

### Docs

- 修改：`docs/voice-correction/voice_correction_technical_spec.md`
- 修改：`docs/voice-correction/voice_correction_phase1_tasks.md`
- 修改：`docs/voice-correction/implementation-reading-notes.md`
- 修改：`docs/voice-correction/opensource-import-plan.md`
- 可修改：`docs/voice-correction/project-decisions.md`

## 任务拆解

### T0 文档与开源边界

- [x] 更新 `docs/voice-correction/voice_correction_technical_spec.md`，补充 `目标词 + 误听写法` 是 UI / 产品模型，底层仍是 deterministic corrections。
- [x] 更新 `docs/voice-correction/opensource-import-plan.md`，明确 TypeWhisper GPLv3 允许 copy / 改写的文件清单。
- [x] 更新 `Packages/VoxFlowVoiceCorrectionKit/SOURCE_ATTRIBUTION.md`，补充 target terms / aliases 的来源说明。
- [x] 更新 `Packages/VoxFlowVoiceCorrectionKit/MODIFICATIONS.md`，说明 VoxFlow 相比 TypeWhisper 的 UI 分组、SQLite、OCR 边界差异。
- [x] 更新 `docs/voice-correction/voice_correction_phase1_tasks.md`，把本方案任务转成可勾选任务。

### T1 目标词核心模型

- [x] 写失败测试：`CorrectionTargetTermTests` 覆盖空文本拒绝、normalized 去重、生命周期默认值。
- [x] 新增 `CorrectionTargetTerm.swift`。
- [x] 跑 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter CorrectionTargetTermTests`，确认通过。
- [x] 写失败测试：`CorrectionRuleValidationTests` 覆盖 `targetID` Codable 往返和旧 JSON 缺字段兼容。
- [x] 修改 `CorrectionRule.swift` 增加 `targetID: UUID?`。
- [x] 跑 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter CorrectionRuleValidationTests`。

### T2 目标词投影

- [x] 写失败测试：`CorrectionTargetProjectionTests` 覆盖按 target 聚合 aliases。
- [x] 写失败测试：无 targetID 的旧 rules 可按 `replacement + scope` fallback 聚合。
- [x] 新增 `CorrectionTargetProjection.swift`。
- [x] 跑 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter CorrectionTargetProjectionTests`。

### T3 SQLite targets repository

- [x] 写失败测试：`SQLiteCorrectionTargetRepositoryTests` 覆盖 target CRUD。
- [x] 新增 `CorrectionTargetRecord.swift`。
- [x] 新增 `SQLiteCorrectionTargetRepository.swift`。
- [x] 修改 `AppDatabase.swift` 新增 `voice_correction_targets` 表。
- [x] 跑 `swift test --filter SQLiteCorrectionTargetRepositoryTests`。

### T4 Rules migration

- [x] 写失败测试：旧 rules 没有 targetID 时，migration 按 `replacement + scope` 生成 targets。
- [x] 写失败测试：migration 重复运行不重复创建 targets。
- [x] 修改 `CorrectionRuleRecord.swift` 增加 `targetID`。
- [x] 修改 `SQLiteCorrectionRuleRepository.swift` 读写 `targetID`。
- [x] 修改 `AppDatabase.swift` 增加幂等 migration。
- [x] 跑 `swift test --filter SQLiteCorrectionRuleRepositoryTests`。

### T5 自动学习归组

- [x] 写失败测试：用户把 `Q问` 改成 `Qwen`，已有 `Qwen` target 时新增 alias 到该 target。
- [x] 写失败测试：没有 `Qwen` target 时自动创建 target。
- [x] 写失败测试：`autoLearningAppliesImmediately = false` 时保存为未生效学习记录，但不进入主页面统计卡片。
- [x] 修改 `CorrectionObservationCoordinator.swift`，把 learned correction 写入 target-aware repository。
- [ ] 必要时新增 `LearnedCorrectionUndoService.swift`。
- [x] 跑 `swift test --filter VoiceCorrectionE2ETests` 和相关 observation tests。

### T6 撤销

- [x] 写失败测试：toast 撤销会删除刚学习 alias。
- [x] 写失败测试：如果 target 是自动创建且没有其他 aliases，撤销时一并删除 target。
- [x] 写失败测试：如果 target 已存在或还有其他 aliases，撤销只删除 alias。
- [ ] 实现 undo service。
- [x] 跑相关 `VoiceCorrectionViewModelTests`。

### T7 ViewModel 改为目标词视图

- [x] 写失败测试：ViewModel 输出 `targetRows`，不是 rule rows。
- [x] 写失败测试：搜索目标词可命中。
- [x] 写失败测试：搜索 alias 可命中对应目标词。
- [x] 写失败测试：选中 target 后输出 alias rows 和 recent learning rows。
- [x] 修改 `VoiceCorrectionViewModel.swift`。
- [x] 跑 `swift test --filter VoiceCorrectionViewModelTests`。

### T8 主 UI 改造

- [x] 写 presentation test：页面包含 `目标词库`、`目标词`、`误听写法`、`本周修正`。
- [x] 写 presentation test：页面不包含 `规则列表`、`原文`、`替换为`、`Benchmark`、`待确认候选`。
- [x] 修改 `VoiceCorrectionView.swift` 主布局。
- [ ] 如文件过大，拆出 `VoiceCorrectionTargetDetailView.swift` 和 `VoiceCorrectionTargetEditor.swift`。
- [x] 跑 `swift test --filter VoiceCorrectionViewPresentationTests`。

### T9 详情抽屉

- [x] 写 ViewModel test：选中 `Qwen` 后 aliases 包含 `q 问 / Q问 / queue win`。
- [x] 实现详情抽屉：目标词标题、常见误听写法、最近学习、高级设置折叠入口。
- [x] 高级设置默认折叠，主视图不显示匹配方式。
- [x] 跑 presentation tests。

### T10 新增目标词 popover

- [x] 写 ViewModel test：保存 target + 多行 aliases 后创建一个 target 和多条 rules。
- [x] 实现 `+ 新增目标词` popover。
- [x] 校验目标词不能为空。
- [x] 误听写法可为空。
- [x] 重复 alias 提示冲突，不静默覆盖。
- [x] 跑 ViewModel tests。

### T11 自动学习 toast

- [ ] 写 ViewModel test：自动学习成功生成 toast model。
- [ ] 写 ViewModel test：点击撤销调用 undo。
- [x] 实现 `VoiceCorrectionToastView.swift` 或内联轻提示。
- [x] Toast 3 秒自动消失，不阻塞主 UI。
- [x] 跑 presentation tests。

### T12 OCR 边界测试

- [x] 写 `PromptBuilderTests`：OCR temporary hotwords 进入 prompt。
- [x] 写 `TextProcessingPipelineTests`：OCR context 不调用 correction repository 写入。
- [x] 写 `TextProcessingPipelineVoiceCorrectionTests`：处理顺序仍是 LLM -> correction。
- [x] 确认 `ContextBoostTrace.safeForPersistence()` 不含 raw OCR text。
- [x] 跑 `swift test --filter PromptBuilderTests`。
- [x] 跑 `swift test --filter TextProcessingPipelineTests`。
- [x] 跑 `swift test --filter TextProcessingPipelineVoiceCorrectionTests`。

### T13 设置页检查

- [x] 写 presentation test：设置页包含易错词开关和 OCR 当前窗口临时上下文开关。
- [x] 确认主页面不展示这些开关。
- [ ] 如文案不清晰，修改 `SettingsRootView.swift`：
  - `易错词修正`
  - `自动学习`
  - `自动学习直接生效`
  - `影子模式`
  - `当前窗口 OCR 临时热词`
- [x] 跑 `swift test --filter SettingsRootViewLayoutTests`。

### T14 Benchmark 与回归

- [x] 确认现有 100 条 correction benchmark 仍使用 production engine。
- [x] 添加至少 5 条 target grouping fixture 或 tests，验证多个 aliases 指向同一 target 不影响 replacement。
- [x] 确认 benchmark report 继续记录 provider bias / OCR 不纳入 Phase 1 correction engine。
- [x] 跑 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit`。

### T15 最终验收

- [x] 跑 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit`。
- [x] 跑相关 targeted VoxFlowApp tests。
- [x] 跑 `swift test`。
- [x] 跑 `make debug`。
- [x] 跑 `make build`。
- [x] 如果全量命令因无关工作区问题失败，记录命令、错误文件、错误行号、是否与本方案相关。
- [x] 检查 `git diff --check`。
- [ ] 最终汇报真实验证、mock 验证、未验证项。

## 验收标准

功能验收：

- 用户主页面看到的是目标词库，不是规则表；
- 用户可以新增目标词和多个误听写法；
- 自动学习成功后，alias 自动归入目标词；
- 自动学习默认静默生效，只给轻提示和撤销；
- 主页面不出现待确认候选卡片；
- OCR 临时热词只进入 LLM prompt；
- OCR 不写入 target / rule repository；
- LLM 后仍运行 deterministic correction；
- LLM 失败时仍运行 deterministic correction；
- Agent Compose 不接入易错词 correction。

UI 验收：

- 左侧 `易错词` tab 保持一级导航；
- 标题、副标题、统计卡片符合新版设计；
- 主表列为 `目标词 / 误听写法 / 作用范围 / 修正次数 / 最近使用 / 状态 / 操作`；
- 右侧详情抽屉显示 aliases 和最近学习；
- 设置项仍在设置页，不进入主页面；
- 文字不溢出、不重叠；
- 不使用复杂营销式布局。

测试验收：

- `VoxFlowVoiceCorrectionKit` package tests 通过；
- target repository tests 通过；
- ViewModel tests 通过；
- UI presentation tests 通过；
- OCR Context Boost 边界 tests 通过；
- correction benchmark 通过现有门槛；
- 最终 `swift test`、`make debug`、`make build` 通过，或明确报告无关阻塞。

## 不做事项

本方案不做：

- 不做 fuzzy；
- 不接 Aho-Corasick；
- 不把 OCR 写入永久词库；
- 不从 OCR 直接学习；
- 不做 provider-specific hotword API；
- 不把待确认候选放主页面；
- 不重写 correction engine；
- 不恢复旧 `词汇表` UI；
- 不保留旧 `文本替换` 入口。

## 风险与缓解

### 风险：目标词模型和现有 rules 迁移不一致

缓解：

- migration 幂等；
- 旧 rules 没有 targetID 也能 fallback 聚合；
- repository tests 覆盖旧数据。

### 风险：自动学习误伤

缓解：

- 继续使用 high-confidence extraction；
- 拒绝 rewrite / insertion-only / deletion-only；
- 自动学习 toast 提供撤销；
- repeated revert 后 suspension。

### 风险：OCR 上下文污染长期词库

缓解：

- OCR provider 不持有 correction repository；
- pipeline tests 证明 OCR 不写 repository；
- trace 只持久化 Top-K hotwords metadata。

### 风险：UI 复杂度再次上升

缓解：

- 主页面只保留目标词管理；
- 设置项留在设置页；
- 候选不做主卡片；
- 高级项折叠到详情抽屉。

## 推荐实施顺序

1. 先做模型和 migration；
2. 再做 projection 和 ViewModel；
3. 再改 UI；
4. 最后接自动学习归组和 toast；
5. 最后补 OCR 边界测试和完整验收。

这样每一步都有测试保护，也能避免 UI 先行后发现数据模型不够用。
