# 易错词 Phase 1 实施任务清单

> 给后续执行者：本文件是第一期主任务入口。按顺序执行，完成一项勾一项。每个任务都要先写/改测试，再做实现，再运行对应验证。

执行纪律见：

```text
docs/voice-correction/voice_correction_goal_spec.md
```

**目标**：实现 VoxFlow 新版一级 `易错词` tab，完成 ASR final 后、LLM 后的本地确定性纠错和 TypeWhisper 式 focused text observation 自动学习。

**第一期固定决策**：

- 旧 `词汇表 -> 易错词`、旧 `词汇表 -> 文本替换` 和旧表数据直接删除，不迁移。
- 易错词只接普通 `.dictation` final transcript，不接 command、translation、interim、Agent Compose。
- 纠错顺序：ASR final -> 可选 LLM refinement -> 易错词 correction -> 文本插入。
- LLM 失败时仍运行易错词，保留当前文本继续 correction。
- 自动学习默认开启，自动学习直接生效默认开启；用户可在设置里关闭直接生效，改为 candidate-only。
- Benchmark 首版跑通 100 条中英文 correction fixtures；未通过或未纳入的剩余 case 必须记录原因和后续方向。

---

## T0 项目发现与集成地图

- [x] 确认当前 worktree 和分支：`/Users/counter/.config/superpowers/worktrees/voice-input-method-mac/voice-correction`，分支 `codex/voice-correction`。
- [x] 运行基线测试：`swift test`；记录通过/失败数量和失败原因。
- [x] 运行基线构建：`make debug`；记录通过/失败原因。
- [x] 阅读 `Sources/VoxFlowApp/TextProcessingBridges/TextProcessingPipeline.swift`，确认 LLM 前后现有处理点。
- [x] 阅读 `Sources/VoxFlowApp/FeatureBridges/VoiceTaskCoordinator.swift`，确认 `.dictation` 与 `.agentCompose` 分流点。
- [x] 阅读 `Sources/VoxFlowDomain/Voice/VoiceTask.swift`，确认 `VoiceTaskMode` 当前枚举。
- [x] 阅读 `Sources/VoxFlowApp/Persistence/AppDatabase.swift` 和 `Sources/VoxFlowApp/Persistence/DatabaseMigrator.swift`，确认 SQLite migration 写法。
- [x] 阅读 `Sources/VoxFlowApp/Views/GlossaryView.swift` 和 `Sources/VoxFlowApp/ViewModels/GlossaryViewModel.swift`，列出旧 UI 删除点。
- [x] 阅读 `Sources/VoxFlowApp/FeatureBridges/NavigationRoute.swift`、`Sources/VoxFlowApp/Views/SidebarView.swift`、`Sources/VoxFlowApp/Views/MainShellView.swift`，确认新增一级 tab 的真实落点。
- [x] 新建 `docs/voice-correction/integration-map.md`。
- [x] 在 `integration-map.md` 写明 ASR final -> LLM -> correction -> insertion 的落点。
- [x] 在 `integration-map.md` 写明 `.agentCompose` 是“帮我说”，第一期不接易错词。
- [x] 在 `integration-map.md` 写明旧表 `glossary_terms`、`replacement_rules` 会被 destructive migration 删除。
- [x] 在 `integration-map.md` 写明 TypeWhisper GPLv3 源码复制范围和 attribution 文件落点。
- [x] 复核 `docs/voice-correction/project-decisions.md` 与本任务清单无冲突。

**验收**：

- [x] `integration-map.md` 包含真实文件路径和关键 symbol。
- [x] `swift test` 基线结果已记录。
- [x] `make debug` 基线结果已记录。

---

## T1 GPLv3 模块与包结构

- [x] 新建目录 `Packages/VoxFlowVoiceCorrectionKit/`。
- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/Package.swift`。
- [x] 在 package 中定义 library target `VoxFlowVoiceCorrection`。
- [x] 在 package 中定义 executable target `VoxFlowVoiceCorrectionBench`。
- [x] 在 package 中定义 test target `VoxFlowVoiceCorrectionTests`。
- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/COPYING`，放入 GPLv3 许可证文本。
- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/NOTICE.md`，记录 TypeWhisper 项目、repo URL、参考 commit、许可证。
- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/SOURCE_ATTRIBUTION.md`，列出复制或改写的 TypeWhisper 文件。
- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/MODIFICATIONS.md`，记录 VoxFlow 对来源代码的修改方向。
- [x] 修改根 `Package.swift`，把 `Packages/VoxFlowVoiceCorrectionKit` 接入 workspace/package 依赖。
- [x] 新建空实现文件 `Packages/VoxFlowVoiceCorrectionKit/Sources/VoxFlowVoiceCorrection/VoxFlowVoiceCorrection.swift`。
- [x] 新建最小可编译 bench 入口 `Packages/VoxFlowVoiceCorrectionKit/Sources/VoxFlowVoiceCorrectionBench/main.swift`，实际 benchmark 逻辑留到 T11。
- [x] 新建 smoke test `Packages/VoxFlowVoiceCorrectionKit/Tests/VoxFlowVoiceCorrectionTests/VoxFlowVoiceCorrectionPackageTests.swift`。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit`。
- [x] 运行根目录 `swift test`，确认根包仍能解析。

**验收**：

- [x] 独立 package 测试通过。
- [x] 根 package 测试至少能开始编译，不因 package 接入失败退出。
- [x] GPLv3 合规文件齐全。

---

## T2 旧功能与旧表直接删除

- [x] 写数据库 migration 测试：旧库里存在 `glossary_terms` 和 `replacement_rules` 时，迁移后两张旧表不存在。
- [x] 写 UI/源码扫描测试或静态检查：`GlossaryView` 不再显示旧“易错词”和“文本替换”分段。
- [x] 修改 `Sources/VoxFlowApp/Persistence/AppDatabase.swift`，新增 destructive migration，drop `glossary_terms`。
- [x] 修改 `Sources/VoxFlowApp/Persistence/AppDatabase.swift`，新增 destructive migration，drop `replacement_rules`。
- [x] 删除或停止编译 `Sources/VoxFlowApp/Persistence/GlossaryRepository.swift` 中旧易错词相关业务入口；普通 glossary 若保留，只保留 prompt glossary 语义。
- [x] 删除或停止编译 `Sources/VoxFlowApp/Persistence/ReplacementRuleRepository.swift`。
- [x] 删除或停止编译 `Sources/VoxFlowApp/TextProcessingBridges/ReplacementRuleEngine.swift`。
- [x] 修改 `Sources/VoxFlowApp/TextProcessingBridges/TextProcessingPipeline.swift`，移除旧 replacement before/after LLM 调用。
- [x] 修改 `Sources/VoxFlowApp/Views/GlossaryView.swift`，删除旧“易错词”和“文本替换”分段。
- [x] 修改 `Sources/VoxFlowApp/ViewModels/GlossaryViewModel.swift`，删除旧易错词/文本替换状态和方法。
- [x] 更新或删除旧测试 `Tests/VoxFlowAppTests/TextProcessingBridges/ReplacementRuleEngineTests.swift`。
- [x] 更新或删除旧测试中对 `replacement_rules`、`glossary_terms` 的断言。
- [x] 运行 `swift test --filter SQLiteFoundationTests`。
- [x] 运行 `swift test --filter SQLiteGlossaryRepositoryTests`；如果普通 glossary 被保留，确保测试语义更新为 prompt glossary。
- [x] 运行 `swift test --filter ReplacementRuleEngineTests`，期望测试文件已删除或不再存在。

**验收**：

- [x] 旧 UI 入口不存在。
- [x] 旧 replacement pipeline 不再运行。
- [x] 旧表数据不会迁入新版 correction rule。
- [x] 数据库 migration/drop 测试通过。

---

## T3 核心领域模型

- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/Sources/VoxFlowVoiceCorrection/Core/CorrectionRule.swift`。
- [x] 定义 `CorrectionRule`，字段包含 `id`、`original`、`replacement`、`matchPolicy`、`scope`、`lifecycle`、`source`、`confidence`、`isEnabled`、`createdAt`、`updatedAt`、`lastAppliedAt`。
- [x] 新建 `MatchPolicy.swift`，定义 `exact`、`boundary`、`substring`。
- [x] 新建 `RuleScope.swift`，第一期支持 `global` 和 `application(bundleIdentifier:)`。
- [x] 新建 `RuleLifecycle.swift`，支持 `candidate`、`active`、`suspended`、`retired`。
- [x] 新建 `CorrectionContext.swift`，字段包含 mode、providerID、modelID、language、bundleIdentifier、isFinalTranscript、isSecureField。
- [x] 定义 `CorrectionInputMode`，只包含 `dictation`、`command`、`translation`。
- [x] 新建 `CorrectionResult.swift`，包含 `rawText`、`correctedText`、`events`、`warnings`。
- [x] 新建 `CorrectionEvent.swift`，记录 ruleID、original、replacement、range、scope、source。
- [x] 新建 `RuleSnapshot.swift`，持有 immutable rules 和版本号。
- [x] 写 `CorrectionRuleValidationTests`，覆盖空 original、相同 original/replacement、超长 original、自动学习 substring 拒绝、单字 CJK 自动学习拒绝。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter CorrectionRuleValidationTests`。

**验收**：

- [x] Core 类型都是 `Sendable` 或符合 Swift 并发要求。
- [x] Core 不 import AppKit、SwiftUI、ApplicationServices、ASR provider SDK。
- [x] 校验测试通过。

---

## T4 Matcher、边界判断与非级联替换

- [x] 新建 `BoundaryClassifier.swift`。
- [x] 写 `BoundaryClassifierTests`，覆盖英文单词边界、数字边界、中文短词、标点、emoji、大小写。
- [x] 新建 `LinearRuleMatcher.swift`。
- [x] 写 `LinearRuleMatcherTests`，覆盖 exact、boundary、substring、case-insensitive 默认行为、case-sensitive 手动规则。
- [x] 新建 `ConflictResolver.swift`。
- [x] 写 `ConflictResolverTests`，覆盖长匹配优先、scope 优先、manual 优先、confidence 优先、left-most、完全包含、部分重叠。
- [x] 新建 `ReplacementApplier.swift`。
- [x] 写 `ReplacementApplierTests`，覆盖从尾部替换、Unicode range、replacement 长度变化、replacement 为空、输出 event span。
- [x] 新建 `VoiceCorrectionEngine.swift`，串联 matcher、conflict resolver、replacement applier。
- [x] 写 `VoiceCorrectionEngineTests`，验证同轮不重扫 replacement，禁止 A -> B -> C 级联。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter BoundaryClassifierTests`。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter LinearRuleMatcherTests`。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter ConflictResolverTests`。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter ReplacementApplierTests`。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter VoiceCorrectionEngineTests`。

**验收**：

- [x] 所有 match 都基于 immutable raw text 收集。
- [x] replacement 输出不会在同一轮再次被扫描。
- [x] overlap 结果稳定。

---

## T5 ContextGate 与安全边界

- [x] 新建 `ContextGate.swift`。
- [x] 写 `ContextGateTests`，覆盖 `dictation` 允许、`command` 拒绝、`translation` 拒绝、interim 拒绝、secure field 拒绝。
- [x] 写 app scope 测试：bundleIdentifier 匹配时允许，不匹配时拒绝。
- [x] 写 lifecycle 测试：active 允许，candidate/suspended/retired 不自动应用。
- [x] 把 `ContextGate` 接入 `VoiceCorrectionEngine`。
- [x] 写 engine 级测试，确认 gate 拒绝时返回 rawText 且无 events。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter ContextGateTests`。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter VoiceCorrectionEngineTests`。

**验收**：

- [x] 第一阶段只有普通 dictation final transcript 会应用 correction。
- [x] secure field 不 correction、不 learning。
- [x] gate 拒绝时行为 fail-open。

---

## T6 SQLite Store、Snapshot 与旧表 Drop

- [x] 新建 `Sources/VoxFlowApp/VoiceCorrection/Persistence/CorrectionRuleRecord.swift`。
- [x] 新建 `Sources/VoxFlowApp/VoiceCorrection/Persistence/CorrectionRuleRepository.swift`。
- [x] 新建 `Sources/VoxFlowApp/VoiceCorrection/Persistence/SQLiteCorrectionRuleRepository.swift`。
- [x] 修改 `Sources/VoxFlowApp/Persistence/AppDatabase.swift`，新增 `voice_correction_rules` 表。
- [x] 修改 `Sources/VoxFlowApp/Persistence/AppDatabase.swift`，新增 `voice_correction_events` 表。
- [x] 修改 `Sources/VoxFlowApp/Persistence/AppDatabase.swift`，新增 `voice_correction_learning_suppression` 表。
- [x] 修改 `Sources/VoxFlowApp/Persistence/AppDatabase.swift`，确保旧 `glossary_terms` 和 `replacement_rules` 被 drop。
- [x] 写 `SQLiteCorrectionRuleRepositoryTests`，覆盖 create、update、delete、disable、clear all。
- [x] 写 duplicate key 测试：同 scope + original 不允许重复 active 规则。
- [x] 写 snapshot 测试：repository 输出 immutable `RuleSnapshot`。
- [x] 写 storage failure 测试：读库失败时 snapshot provider 返回 previous snapshot 或 empty snapshot。
- [x] 运行 `swift test --filter SQLiteCorrectionRuleRepositoryTests`。
- [x] 运行 `swift test --filter SQLiteFoundationTests`。

**验收**：

- [x] 新规则表可 CRUD。
- [x] 旧表被 drop。
- [x] matcher 不直接读 DB，只读 snapshot。

---

## T7 Pipeline 接入

- [x] 新建 `Sources/VoxFlowApp/VoiceCorrection/Integration/TranscriptPostProcessingCoordinator.swift` 或等价 bridge。
- [x] 新建 `Sources/VoxFlowApp/VoiceCorrection/Integration/VoiceCorrectionTextProcessor.swift`。
- [x] 修改 `Sources/VoxFlowApp/TextProcessingBridges/TextProcessingPipeline.swift`，在 LLM refinement 后调用 voice correction。
- [x] 写 `TextProcessingPipelineVoiceCorrectionTests`，验证 LLM 成功后再运行易错词。
- [x] 写 `TextProcessingPipelineVoiceCorrectionTests`，验证 LLM 失败后仍运行易错词。
- [x] 写测试验证 command / translation 不进入 correction。
- [x] 写测试验证 correction 抛错时返回当前文本并记录 warning，不阻塞插入。
- [x] 修改 `Sources/VoxFlowApp/App/DependencyContainer.swift`，注入 correction repository、snapshot provider、processor。
- [x] 修改 `Sources/VoxFlowApp/App/AppServiceProviding.swift` 或对应 service protocol，暴露 correction 依赖。
- [x] 运行 `swift test --filter TextProcessingPipelineVoiceCorrectionTests`。
- [x] 运行 `swift test --filter VoiceTaskCoordinatorTests`。

**验收**：

- [x] 所有 ASR provider 共享同一个 final transcript correction 出口。
- [x] 不要求 provider 支持 hotword/prompt。
- [x] LLM 失败时易错词仍运行。
- [x] Agent Compose 不接入易错词。

---

## T8 Focused Text Observation 抽象

- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/Sources/VoxFlowVoiceCorrection/Learning/FocusedTextObservation.swift`。
- [x] 新建 `FocusedTextObserving` protocol。
- [x] 新建 `Sources/VoxFlowApp/VoiceCorrection/Observation/AccessibilityFocusedTextObserver.swift`。
- [x] 参考 TypeWhisper `TextInsertionService`，实现 focused element capture / recapture 思路。
- [x] 新建 fake observer：`Tests/VoxFlowAppTests/VoiceCorrection/FakeFocusedTextObserver.swift`。
- [x] 写 `FocusedTextObservationTests`，覆盖同一 focused element 可 recapture。
- [x] 写 `FocusedTextObservationTests`，覆盖 focus changed 时取消。
- [x] 写 `FocusedTextObservationTests`，覆盖 unreadable value 时取消。
- [x] 写 `FocusedTextObservationTests`，覆盖 secure field 时取消。
- [x] 写 fake clock，支持 2 / 5 / 10 秒轮询。
- [x] 运行 `swift test --filter FocusedTextObservationTests`。

**验收**：

- [x] CI 不需要真实 Accessibility 权限。
- [x] observation 失败不影响文本插入。
- [x] production observer 与 fake observer 共享同一 protocol。

---

## T9 高置信自动学习

- [x] 新建 `HighConfidenceCorrectionExtractor.swift`。
- [x] 写测试：用户把 `q 问` 改成 `Qwen` 时提取 pair。
- [x] 写测试：rewrite 整句时拒绝学习。
- [x] 写测试：只插入新内容时拒绝学习。
- [x] 写测试：只删除内容时拒绝学习。
- [x] 写测试：ambiguous diff 时拒绝学习。
- [x] 写测试：改动不在刚插入文本范围内时拒绝学习。
- [x] 新建 `CorrectionObservationCoordinator.swift`。
- [x] 实现插入后 2 / 5 / 10 秒轮询。
- [x] 实现 `autoLearningEnabled = false` 时不启动观察。
- [x] 实现 `autoLearningAppliesImmediately = true` 时生成 app-scoped active rule。
- [x] 实现 `autoLearningAppliesImmediately = false` 时生成 app-scoped candidate rule。
- [x] 实现 applied correction overlap guard，避免把本轮已应用的规则再学习成反馈环。
- [x] 运行 `swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter HighConfidenceCorrectionExtractorTests`。
- [x] 运行 `swift test --filter CorrectionObservationCoordinatorTests`。

**验收**：

- [x] 高置信 substitution 能学习。
- [x] rewrite / insertion / deletion / ambiguity 都拒绝。
- [x] 默认直接 active。
- [x] 关闭直接生效后进入 candidate。

---

## T10 生命周期、负反馈与撤销

- [x] 新建 `LearningPolicy.swift`。
- [x] 新建 `RuleConfidenceReducer.swift`。
- [x] 写测试：用户手动新增规则直接 active。
- [x] 写测试：自动学习直接生效开启时直接 active，confidence 0.90。
- [x] 写测试：自动学习直接生效关闭时进入 candidate。
- [x] 写测试：用户改回后 confidence 降低。
- [x] 写测试：同一规则两次被改回后 suspended。
- [x] 写测试：删除或拒绝过的 pair 进入 suppression list。
- [x] 写测试：suppression list 内 pair 30 天内不再自动学习。
- [x] 写测试：撤销最近自动学习事件会删除或 suspend 对应规则。
- [x] 写测试：不会产生 A -> B -> C 反馈链。
- [x] 运行 `swift test --filter LearningPolicyTests`。
- [x] 运行 `swift test --filter RuleConfidenceReducerTests`。

**验收**：

- [x] active / candidate / suspended 状态转换明确。
- [x] 用户负反馈能降低 confidence。
- [x] 撤销入口可恢复最近自动学习。

---

## T11 Benchmark Harness

- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Fixtures/rules_v1.json`。
- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Fixtures/correction_cases_v1.jsonl`。
- [x] 写 100 条中英文 correction fixtures。
- [x] 确保 negative case 数量不少于 positive case。
- [x] 覆盖 exact、boundary、substring、hard negative、overlap、cascade prevention、punctuation、mode bypass。
- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Fixtures/learning_cases_v1.jsonl`，放入 targeted learning cases。
- [x] 新建 `Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Baselines/phase1-baseline.json`。
- [x] 新建 `Sources/VoxFlowVoiceCorrectionBench/BenchmarkCase.swift`。
- [x] 新建 `BenchmarkRunner.swift`。
- [x] 新建 `MetricsCalculator.swift`。
- [x] 新建 `ReportWriter.swift`。
- [x] 新建 `main.swift`，支持 `--fixtures`、`--baseline`、`--output` 参数。
- [x] 输出 `.build/voice-correction-benchmark/report.json`。
- [x] 输出 `.build/voice-correction-benchmark/report.md`。
- [x] report 中写入 failed case 列表。
- [x] report 中写入未通过 / 未纳入 case 的原因和后续方向。
- [x] 计算 SentenceExactMatchRate、CorrectionPrecision、SupportedCorrectionRecall、FalseReplacementRate、RegressionRate。
- [x] 计算 CERBefore、CERAfter、WERBefore、WERAfter。
- [x] 计算 P50 / P95 / P99 latency。
- [x] 新建 `tools/voice_correction_jiwer_check.py`，用 JiWER 交叉验证 WER / CER。
- [x] 运行 `swift run --package-path Packages/VoxFlowVoiceCorrectionKit VoxFlowVoiceCorrectionBench --fixtures Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Fixtures --baseline Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Baselines/phase1-baseline.json --output .build/voice-correction-benchmark`。
- [x] 运行 `uv run tools/voice_correction_jiwer_check.py --report .build/voice-correction-benchmark/report.json`。

**验收**：

- [x] 100 条首版 fixtures 全过。
- [x] precision = 1.0。
- [x] supported recall = 1.0。
- [x] false replacement = 0。
- [x] regression = 0。
- [x] CER / WER 不退化。
- [x] 未通过或未纳入 case 已记录原因和方向。

---

## T12 完整易错词 Tab UI

- [x] 修改 `Sources/VoxFlowApp/FeatureBridges/NavigationRoute.swift`，新增 `voiceCorrection` route。
- [x] 修改 `Sources/VoxFlowApp/FeatureBridges/NavigationRoute.swift`，标题返回 `易错词`。
- [x] 修改 `Sources/VoxFlowApp/FeatureBridges/NavigationRoute.swift`，图标使用 `text.badge.checkmark` 或同语义 SF Symbol。
- [x] 修改 `Sources/VoxFlowApp/Views/SidebarView.swift`，左侧一级导航新增 `易错词`。
- [x] 修改 `Sources/VoxFlowApp/Views/MainShellView.swift`，route switch 接入 `VoiceCorrectionView`。
- [x] 新建 `Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionView.swift`。
- [x] 新建 `VoiceCorrectionViewModel.swift`。
- [x] UI 顶部显示启用、自动学习、直接生效、Shadow Mode 四个开关。
- [x] UI 显示 Benchmark 状态：首版 100/100，通过/失败状态。
- [x] UI 显示 active 规则列表。
- [x] UI 显示 candidate 列表；只有关闭直接生效时才会增长。
- [x] UI 支持新增手动规则。
- [x] UI 支持编辑规则 original / replacement / scope / match policy。
- [x] UI 支持禁用规则。
- [x] UI 支持删除规则。
- [x] UI 支持清空全部规则。
- [x] UI 支持撤销最近自动学习事件。
- [x] UI 在 tab 标题或侧边栏显示 candidate / newly learned badge。
- [x] UI 顶部显示最近学习事件条，例如“已学习 2 条易错词”，带撤销按钮。
- [x] 不使用系统通知、录音 HUD 或打断式浮窗做学习反馈。
- [x] 写 `VoiceCorrectionViewModelTests`，覆盖开关、删除、禁用、清空、撤销。
- [x] 写 UI presentation 测试，确认 `易错词` 一级 tab 存在。
- [x] 运行 `swift test --filter VoiceCorrectionViewModelTests`。
- [x] 运行 `swift test --filter NavigationRoute` 或对应导航测试。

**验收**：

- [x] UI 是完整一级 tab，不是设置页里的临时面板。
- [x] 左侧导航出现 `易错词`。
- [x] 自动学习直接生效开关默认开启且可关闭。
- [x] 学习反馈只出现在 `易错词` tab 内。
- [x] UI 风格匹配现有 VoxFlow macOS 风格。

---

## T13 E2E、回归与最终报告

- [x] 写 E2E：MockASR -> TextProcessingPipeline -> VoiceCorrection -> FakeTextInsertion。
- [x] E2E 验证 raw / final 分离。
- [x] E2E 验证 `.dictation` 会 correction。
- [x] E2E 验证 `.command` 不 correction。
- [x] E2E 验证 LLM 失败后仍 correction。
- [x] 写 E2E：FakeFocusedTextObserver -> CorrectionObservationCoordinator -> repository。
- [x] E2E 验证 2 / 5 / 10 秒轮询。
- [x] E2E 验证 focus change 后取消学习。
- [x] E2E 验证直接生效开启时自动 active。
- [x] E2E 验证直接生效关闭时生成 candidate。
- [x] 运行 `swift test`。
- [x] 运行 `make debug`。
- [x] 运行 `make build`。
- [x] 运行 benchmark 命令。
- [x] 在最终报告中回答：100 条首版 fixtures 是否全过。
- [x] 在最终报告中列出：剩余未过或未纳入 case 是哪些。
- [x] 在最终报告中解释：为什么没过。
- [x] 在最终报告中写明：下一步方向是什么。
- [x] 更新 `docs/voice-correction/project-decisions.md`，记录最终实现与方案差异。
- [x] 更新 `docs/voice-correction/implementation-reading-notes.md`，记录执行中发现的新边界。

**验收**：

- [x] `swift test` 通过，或明确列出与本需求无关的失败。
- [x] `make debug` 通过，或明确列出与本需求无关的失败。
- [x] `make build` 通过，或明确列出与本需求无关的失败。
- [x] Benchmark report 生成。
- [x] 最终报告回答 benchmark 未过/未纳入 case 的原因与方向。
