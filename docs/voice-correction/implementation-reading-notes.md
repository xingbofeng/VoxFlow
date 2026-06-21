# Voice Correction Implementation Reading Notes

## Phase Split

这套方案按实际工程边界分为三期：

1. **Phase 1 / V1：确定性本地易错词后处理**
   - 统一接入所有 ASR 的 final transcript；
   - 建立本地 correction rule、RuleSnapshot、exact / boundary / substring matcher；
   - 完成非级联替换、冲突消解、ContextGate、安全门、审计、Shadow Mode、kill switch；
   - 完成插入后 focused text observation、保守自动学习、生命周期、负反馈；
   - 完成纯文本 Benchmark、fixture、baseline gate、JiWER 交叉校验；
   - 完成产品 UI，而不是只做临时或半成品设置页。

2. **Phase 2：性能与 Provider bias 增强**
   - 进入条件：active alias > 1,000，或 5,000 rules P95 超标，或 top-K prompt 有明确数据收益；
   - 可引入 Aho-Corasick matcher adapter，并与 V1 linear matcher 双跑；
   - 可做 top-K term selector 和 provider budget adapter；
   - Aho 输出必须与 linear matcher bit-for-bit 一致，可一键回退。

3. **Phase 3：受限 fuzzy**
   - 进入条件：已有高 precision deterministic corpus、足够真实 fuzzy 失败样本、hard-negative corpus、独立 fuzzy Benchmark；
   - 只面向英文技术词等低歧义场景；
   - 禁止中文短词 fuzzy；
   - fuzzy 只能对已召回的小候选集打分，不能全词库暴力比较。

## Phase 1 Scope

第一期不是“先做个算法核”，而是端到端可用的本地易错词系统：

- Core：`CorrectionRule`、`CorrectionContext`、`RuleSnapshot`、`CorrectionResult`、`TranscriptPostProcessor`。
- Matching：linear matcher，支持 exact / boundary / substring，基于 immutable raw text 收集全部 matches。
- Replacement：统一冲突消解，从后往前替换，同轮不重扫 replacement，禁止 A→B→C 级联。
- Storage：复用项目 SQLite 持久层，新增 correction rule / event / learning state 所需 schema；matcher 只能读 immutable snapshot，不直接读 DB。
- Pipeline：接入 ASR final 后、可选 LLM refinement 后、文本插入前；command / translation / interim 默认 bypass；异常 fail-open。
- Safety：secure field bypass，生产日志不记录完整 transcript，支持全局开关、Shadow Mode、自动学习开关。
- Learning：插入后 2 / 5 / 10 秒观察 focused text，使用 fake clock/fake observer 测试；只接受高置信 substitution；默认直接 active，可在设置页关闭为 candidate-only。
- Lifecycle：candidate / trusted / active / suspended / retired，支持 revertedCount、confidence 降低、重复反向修改 suspend。
- Benchmark：首版 100 条中英文 correction fixtures，precision / supported recall 100%，false replacement / regression 为 0，CER/WER 不退化；500 correction fixtures + 100 learning fixtures 作为扩展门槛。未通过或未纳入的剩余 case 必须记录原因和方向。
- UI：完整实现“易错词”tab，包含规则列表、搜索/筛选、新增/编辑、禁用/删除/清空、候选确认、Shadow/自动学习/自动学习直接生效/启用开关、最近审计事件。

## Open Source References

当前仓库 `LICENSE` 是 MIT。用户已确认可以按 TypeWhisper 的 GPLv3 协议履约，并明确允许在模块化边界内复制或改写 TypeWhisper GPLv3 源码。后续不能继续假定整个项目仍按纯 MIT 分发，必须把 GPLv3 模块化与分发策略作为实现任务处理。

若直接复制或改写 TypeWhisper GPLv3 源码，必须满足至少以下条件：

- 明确标记 copied / modified source 的来源、copyright、license；
- 保留 GPLv3 license text；
- 标注本项目对源码做过的修改；
- 分发时提供对应源码；
- 不添加 GPLv3 禁止的额外限制；
- 评估是否需要将整个组合/派生作品改为 GPLv3 分发，或建立足够清晰的进程/模块边界。

第一期可参考或采用的轮子和代码：

- **TypeWhisper / typewhisper-mac**
  - License: GPLv3。
  - 允许策略：可以直接复制或改写必要源码，但必须集中在独立 `VoxFlowVoiceCorrection` 模块或 package 内，并同步更新许可证、NOTICE / attribution、源码发布和合规文档。
  - 隔离策略：不要把 GPLv3 来源代码散落到 App 壳层、UI、ASR Provider 或通用基础设施；若希望主 App 继续尽量维持 MIT 授权，需要评估独立进程 / helper / IPC 边界。
  - 重点参考：`DictionaryEntry.swift`、`DictionaryService.swift`、`PostProcessingPipeline.swift`、`TextDiffService.swift`、`TargetAppCorrectionLearningService.swift`、`TextInsertionService.swift` 及对应测试。
  - 自动学习链路直接借鉴 TypeWhisper 的 focused text observation 思路：插入前后捕捉同一个 focused text element，按 2 / 5 / 10 秒轮询，只有高置信用户改写才学习规则；是否直接 active 由 `autoLearningAppliesImmediately` 控制。

- **FlashText**
  - License: MIT。
  - Phase 1 只借鉴 target + aliases 的数据模型与替换行为，不在 App 内嵌 Python。
  - 可参考 `KeywordProcessor` 的 `unclean alias -> clean target` 思路。

- **OpenBench**
  - License: MIT for code，datasets 各自有许可证。
  - Phase 1 只借鉴 keyword metric、dataset schema、报告结构，不把 OpenBench 引入 App，也不要求每个 ASR 跑音频 benchmark。

- **JiWER**
  - License: Apache-2.0。
  - 只用于 tools / CI 交叉验证 WER / CER；生产 App 不依赖 Python。

第一期明确不用：

- **Aho-Corasick-Swift**：Apache-2.0，但只作为 Phase 2 候选；V1 先 linear matcher。
- **BurntSushi/aho-corasick**：Rust，第一期不引入 Rust FFI。
- **SymSpell**：MIT，Phase 3 fuzzy 参考。
- **strsim-rs**：MIT，Phase 3 fuzzy 参考；没有 Rust core 时不直接用。

## Existing Project Upgrade Points

现有项目已有“词汇表”一级 tab，其中包含两个子功能：

- `词汇表 / 易错词`：当前只是简单词条和 alias 列表，主要用于 prompt 上下文；
- `词汇表 / 文本替换`：当前是简单 `source -> target` replacement rule。

本需求是对这套能力的升级，不是一个完全孤立的新功能。实现时需要把“易错词”升级成独立一级 tab，并重新定义其业务语义。旧 `词汇表 -> 易错词` 和旧 `词汇表 -> 文本替换` 都应在第一期删除，不做数据迁移，不做保留入口或兼容 UI。

主要改造点：

- `Sources/VoxFlowApp/FeatureBridges/NavigationRoute.swift`
  - 新增一级 route：`voiceCorrection` 或等价命名；
  - 标题必须是 `易错词`；
  - 图标建议使用 `text.badge.checkmark`、`checklist` 或接近语义的 SF Symbol。

- `Sources/VoxFlowApp/Views/SidebarView.swift`
  - 左侧主导航必须新增“易错词”tab；
  - 设计图里左侧 tab 漏画了“易错词”，实现和后续设计修订必须修正这一点。

- `Sources/VoxFlowApp/Views/MainShellView.swift`
  - route switch 中新增 `VoiceCorrectionView`；
  - 现有 `GlossaryView` 可以保留为“词汇表”，但不再承载新版易错词的完整交互。

- `Sources/VoxFlowApp/Views/GlossaryView.swift` / `Sources/VoxFlowApp/ViewModels/GlossaryViewModel.swift`
  - 现有 `GlossarySection.words` 的“易错词”是旧入口；
  - 第一阶段应删除旧 `词汇表 -> 易错词` 子功能，避免两个易错词入口并存；
  - 第一阶段也应删除旧 `词汇表 -> 文本替换` 子功能，避免简单替换和新版 correction engine 并存；
  - 旧数据直接删除，不迁移到新版 correction rule。

- `Sources/VoxFlowApp/Persistence/GlossaryRepository.swift`
  - 现有 `GlossaryTerm` 可以继续服务 prompt glossary；
  - 不应直接拿它当 V1 correction rule，因为缺少 match policy、scope、lifecycle、confidence、counters、provider/model/language、lastApplied 等字段。

- `Sources/VoxFlowApp/Persistence/ReplacementRuleRepository.swift`
  - 现有 `ReplacementRule` 是删除对象，不作为迁移来源或兼容层；
  - 不应原样作为 V1 correction rule，因为它只有 exact / contains / regex 和 beforeLLM / afterLLM，不符合 immutable matching、ContextGate、生命周期和审计要求。

- `Sources/VoxFlowApp/TextProcessingBridges/ReplacementRuleEngine.swift`
  - 当前实现会按 priority 逐条修改 `currentText`，因此会发生同轮级联；
  - V1 必须替换为基于 rawText 收集 spans、统一 conflict resolve、从尾部 apply 的引擎。

- `Sources/VoxFlowApp/TextProcessingBridges/TextProcessingPipeline.swift`
  - 当前 pipeline 已保留 `rawText` / `finalText`，这是可复用基础；
  - TypeWhisper 当前顺序是 LLM priority 300、snippets priority 500、dictionary/corrections priority 600；其插件文档也把 post-processor input 定义为 LLM 后文本；
  - V1 correction 应接在 ASR final 后、可选 LLM refinement 后、插入前，并明确 command / translation bypass；
  - LLM 失败时仍运行易错词：保留当前文本，继续执行 correction，最后插入；
  - 需要小心与现有 LLM refinement、glossary prompt、replacement rules 的顺序关系，T0 必须先画清楚。

- `Sources/VoxFlowDomain/Voice/VoiceTask.swift` / `Sources/VoxFlowApp/FeatureBridges/VoiceTaskCoordinator.swift`
  - `agentCompose` 是“帮我说”：语音输入作为意图，由 LLM 生成/改写输出，不是普通 dictation 原文插入；
  - 第一阶段易错词不接 Agent Compose，只接 `.dictation`。

- `Sources/VoxFlowApp/Persistence/AppDatabase.swift`
  - 项目已有 SQLite + migration 机制；
  - Phase 1 应优先复用 SQLite，而不是引入 SwiftData 或新数据库框架。
  - 旧表数据直接删除；第一期允许 destructive migration / drop old tables，移除 `glossary_terms` 和 `replacement_rules` 对旧功能的业务入口。

- `Sources/VoxFlowApp/App/DependencyContainer.swift` / `Sources/VoxFlowApp/App/AppServiceProviding.swift`
  - 新增 correction repositories、snapshot provider、feature flag store、observation coordinator 等依赖注入点。

- `Tests/VoxFlowAppTests/...`
  - 现有 `GlossaryViewModelTests`、`ReplacementRuleEngineTests`、`TextProcessingPipelineTests`、`TranscriptionMainChainRegressionTests` 需要扩展或迁移；
  - 新增 Core tests、SQLite migration/store tests、UI presentation/layout tests、benchmark fixture tests。

## UI Decision

产品 UI 必须完整实现，且新增的是左侧一级主导航 tab：

```text
易错词
```

这不是设置页里的一个小 toggle，也不是 `LLM 模型` 或 `ASR 模型` 的子页面。它是原本 `词汇表 -> 易错词 / 文本替换` 能力的升级版：从“给 prompt 提供词条 + 简单文本替换”升级为“ASR final transcript 后、LLM 后的本地确定性纠错系统”。

设计图备注：

- 当前已生成的 GPT Image 2 设计稿左侧导航没有新增“易错词”tab；
- 后续修订设计稿和实现时必须补上；
- 新 tab 应与 `首页 / 词汇表 / 风格 / 文件转写 / 笔记 / 设置 / 帮助` 同级；
- `词汇表` 可以保留为普通 glossary / prompt 词表入口，但其中旧的“易错词”和“文本替换”子功能在迁移完成后应删除，避免与新版一级 tab 冲突。

## Runtime Defaults

第一期按产品决策默认开启新版易错词：

- `correctionEnabled = true`
- `autoLearningEnabled = true`
- `autoLearningAppliesImmediately = true`
- `shadowModeEnabled = false`
- `providerBiasEnabled = false`
- `fuzzyEnabled = false`

默认开启不代表所有流程都参与纠错。Command、translation、interim transcript、secure field、无法确认 focused text 的学习场景仍然 bypass。

`autoLearningAppliesImmediately` 放在设置页，默认开启。开启时高置信自动学习直接生成 active 规则；关闭时只生成 candidate，用户在 `易错词` tab 确认后生效。

## Accessibility Learning Decision

Phase 1 必须做 Accessibility focused text observation 抽象。TypeWhisper 的自动学习是 focused text observation：

1. 插入前读取 Accessibility focused text element；
2. 插入后重新捕捉同一个 element 作为 baseline；
3. 按 2 / 5 / 10 秒轮询；
4. 只在用户修改了刚插入文本且 diff 高置信时学习规则。

因此 VoxFlow 第一阶段也必须做 Accessibility focused text observation 抽象，否则无法实现自动学习。CI 和单元测试不得依赖真实 Accessibility 权限，必须使用 fake observer / fake clock。

## Final Benchmark Shape

最终 Benchmark 是一个 SwiftPM bench target，使用生产 correction engine，输入 JSONL fixtures，输出 JSON / Markdown report，不依赖真实 ASR、音频或 Accessibility 权限。

目录：

```text
Packages/VoxFlowVoiceCorrectionKit/
├── Benchmarks/
│   ├── Fixtures/
│   │   ├── correction_cases_v1.jsonl
│   │   ├── learning_cases_v1.jsonl
│   │   └── rules_v1.json
│   └── Baselines/
│       └── phase1-baseline.json
└── Sources/VoxFlowVoiceCorrectionBench/
    ├── main.swift
    ├── BenchmarkCase.swift
    ├── BenchmarkRunner.swift
    ├── MetricsCalculator.swift
    └── ReportWriter.swift
```

首版 Phase 1 fixture 要求：

- `correction_cases_v1.jsonl` 首版 100 条中英文 case；
- negative case 数量不少于 positive case；
- 覆盖 exact、boundary、substring、hard negative、overlap、cascade prevention、punctuation、mode bypass；
- `learning_cases_v1.jsonl` 首版可以是 targeted tests 对应的小集合，后续扩展到 100 条；
- `rules_v1.json` 固定 benchmark 规则，避免测试依赖用户本地数据库。
- 未通过或未纳入的剩余 case 必须记录 `id`、原因、方向、是否阻塞本期。

运行：

```bash
swift run --package-path Packages/VoxFlowVoiceCorrectionKit VoxFlowVoiceCorrectionBench \
  --fixtures Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Fixtures \
  --baseline Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Baselines/phase1-baseline.json \
  --output .build/voice-correction-benchmark
```

报告必须包含：

- summary metrics；
- failed case table；
- expected events vs actual events；
- per-tag metrics；
- latency P50 / P95 / P99；
- CER / WER before and after；
- baseline diff。

开源 benchmark 参考：

- **JiWER**：ASR 文本评估通常用 WER / CER，并支持 transform 归一化与 substitution / insertion / deletion 频次输出；VoxFlow 使用同类指标衡量 correction 后是否退化，并用 JiWER 做 tools / CI 交叉校验。
- **OpenAI Evals**：评测数据使用 JSONL，配置和运行参数独立，便于复现；VoxFlow 的 rules、fixtures、baseline、report 必须固定落盘，不依赖用户本机数据库。
- **LanguageTool**：规则开发依赖 embedded examples，incorrect sentence 必须命中，correct sentence 不应命中，antipattern 用于阻止误伤；VoxFlow benchmark 必须要求每个易混 alias 配套 positive 和 hard-negative。
- **FlashText**：关键词替换库会同时验证替换结果和性能；VoxFlow benchmark 同时输出行为指标和 P50 / P95 / P99 latency。

## Phase 1 Execution Notes

实现过程中新增了一个 no-op guard：case-insensitive rule 命中时，如果 matched text 已经与 replacement 完全相同，则不生成 match/event。原因是 `claude -> Claude`、`ai 的 -> AI 的` 这类规则在文本已经正确时不应产生审计事件或 false positive。

T12 UI 实现时遇到 Swift 6.3.2 frontend 在 `@Sendable` Binding helper 上 IRGen 崩溃的问题。最终改为普通 computed `Binding` 属性，保持 UI 行为不变并规避编译器 bug。

当前 benchmark report：

```text
Total cases: 100
Passed cases: 100
Sentence exact match: 1.0
Correction precision: 1.0
Supported correction recall: 1.0
False replacement rate: 0.0
Regression rate: 0.0
CER before/after: 0.12367270455965022 / 0.0
WER before/after: 0.33134328358208953 / 0.0
```

未纳入项与方向：

- 500 correction + 100 learning extended benchmark：不阻塞 Phase 1 首版，后续在 100 条 gate 稳定后扩展。
- Real Accessibility permission observation benchmark：CI 使用 fake observer / fake clock，真实权限观测留作手工 smoke 或后续自动化。
- Provider bias and OCR/TTL context benchmark：Phase 1 correction engine 明确不消费 OCR 或 provider bias，留到 Phase 2 之后。
