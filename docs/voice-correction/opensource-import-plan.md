# Voice Correction Open Source Import Plan

## Confirmed Strategy

第一期确认走 **TypeWhisper GPLv3 模块化引入**：

- 可以复制或改写 TypeWhisper GPLv3 源码；
- copied / modified GPLv3 code 必须集中在独立 `VoxFlowVoiceCorrection` module / package 内；
- 不把 GPLv3 来源代码散落到 App 壳层、ASR Provider、通用 persistence、通用 UI 组件或基础设施；
- 模块内必须保留 GPLv3 license text、来源 commit、来源文件清单、修改说明；
- 分发时按 GPLv3 义务提供对应源码；
- 若该模块链接进同一个 App，需要按 GPLv3 组合分发风险处理。

当前 TypeWhisper 参考 commit：

```text
6c46bfc676539e2a1a245a01dca9a4afd6f2cb63
```

## TypeWhisper Files To Import Or Adapt

这些文件是第一期的主要源码参考。实现时允许复制后改写，但必须进入 GPLv3 模块边界：

1. `TypeWhisper/Models/DictionaryEntry.swift`
   - 作为 `CorrectionRule` / alias / replacement / enabled / caseSensitive / counters / timestamp 的数据模型参考；
   - VoxFlow 需要扩展 match policy、scope、lifecycle、confidence、provider/model/language。

2. `TypeWhisper/Services/DictionaryService.swift`
   - 作为 correction CRUD、apply corrections、exact / boundary / substring 行为参考；
   - VoxFlow 必须改为 immutable raw matching、统一 conflict resolver、non-cascading replacement。

3. `TypeWhisper/Services/PostProcessingPipeline.swift`
   - 作为 provider-independent post-processing pipeline 集成参考；
   - TypeWhisper 当前内置顺序为 LLM priority 300、snippets priority 500、dictionary / corrections priority 600；
   - VoxFlow 接入点必须位于 ASR final transcript 之后、可选 LLM refinement 之后，command / interim bypass。

4. `TypeWhisper/Services/TextDiffService.swift`
   - 作为 high-confidence correction extraction 参考；
   - VoxFlow 必须保守拒绝 rewrite / insertion / deletion / ambiguity。

5. `TypeWhisper/Services/TargetAppCorrectionLearningService.swift`
   - 作为插入后 focused text observation、2 / 5 / 10 秒 polling、学习候选生成参考；
   - Phase 1 直接借鉴这个学习思路：插入前/后捕捉同一个 focused element，用户高置信改写才学习规则；是否直接 active 由 VoxFlow 的设置控制；
   - VoxFlow 测试必须使用 fake observer / fake clock，不依赖真实 Accessibility 权限。

6. `TypeWhisper/Services/TextInsertionService.swift`
   - 只参考 active app / focused element / selected range / clipboard 恢复相关做法；
   - VoxFlow 已有 `VoxFlowTextInsertion`，不应绕过现有插入 contract。

7. `TypeWhisper/ViewModels/DictationViewModel.swift`
   - 只参考 dictation 生命周期集成点；
   - VoxFlow 实际落点以 `DictationOrchestrator`、`VoiceTaskCoordinator`、`TextProcessingPipeline` 和 ASR final 出口为准。

## VoxFlow File Mapping

具体借鉴 / 复制 / 改写关系必须放进模块，并同步写入 `SOURCE_ATTRIBUTION.md`。建议映射如下：

```text
Packages/VoxFlowVoiceCorrectionKit/
└── Sources/VoxFlowVoiceCorrection/
    ├── Domain/
    │   ├── CorrectionRule.swift
    │   │   ← TypeWhisper/Models/DictionaryEntry.swift
    │   ├── CorrectionContext.swift
    │   │   ← VoxFlow-specific, no direct TypeWhisper source
    │   ├── CorrectionMatch.swift
    │   │   ← TypeWhisper/Services/DictionaryService.swift
    │   ├── CorrectionResult.swift
    │   │   ← TypeWhisper/Services/PostProcessingPipeline.swift
    │   ├── AppliedCorrection.swift
    │   │   ← TypeWhisper/Services/DictionaryService.swift
    │   └── RuleSnapshot.swift
    │       ← VoxFlow-specific snapshot boundary
    ├── Matching/
    │   ├── LinearRuleMatcher.swift
    │   │   ← TypeWhisper/Services/DictionaryService.swift
    │   ├── BoundaryClassifier.swift
    │   │   ← TypeWhisper/Services/DictionaryService.swift
    │   ├── ContextGate.swift
    │   │   ← VoxFlow-specific safety gates
    │   ├── ConflictResolver.swift
    │   │   ← VoxFlow-specific non-cascading resolver
    │   └── ReplacementApplier.swift
    │       ← TypeWhisper/Services/DictionaryService.swift
    ├── Learning/
    │   ├── InsertionObservationToken.swift
    │   │   ← TypeWhisper/Services/TargetAppCorrectionLearningService.swift
    │   ├── HighConfidenceCorrectionExtractor.swift
    │   │   ← TypeWhisper/Services/TextDiffService.swift
    │   ├── LearningPolicy.swift
    │   │   ← TypeWhisper/Services/TargetAppCorrectionLearningService.swift
    │   └── RuleConfidenceReducer.swift
    │       ← VoxFlow-specific negative feedback policy
    ├── Metrics/
    │   ├── EditDistance.swift
    │   │   ← VoxFlow-specific / benchmark support
    │   ├── CorrectionMetrics.swift
    │   │   ← OpenBench metric concepts, no direct OpenBench source
    │   └── LatencySummary.swift
    │       ← OpenBench report concepts, no direct OpenBench source
    └── Processing/
        ├── TranscriptPostProcessor.swift
        │   ← TypeWhisper/Services/PostProcessingPipeline.swift
        └── VoiceCorrectionEngine.swift
            ← TypeWhisper/Services/PostProcessingPipeline.swift
              + TypeWhisper/Services/DictionaryService.swift
```

测试映射：

```text
Packages/VoxFlowVoiceCorrectionKit/
└── Tests/VoxFlowVoiceCorrectionTests/
    ├── RuleValidationTests.swift
    │   ← TypeWhisperTests/DictionaryServiceTests.swift
    ├── BoundaryClassifierTests.swift
    │   ← TypeWhisperTests/DictionaryServiceTests.swift
    ├── LinearRuleMatcherTests.swift
    │   ← TypeWhisperTests/DictionaryServiceTests.swift
    ├── ReplacementApplierTests.swift
    │   ← TypeWhisperTests/DictionaryServiceTests.swift
    ├── HighConfidenceCorrectionExtractorTests.swift
    │   ← TypeWhisperTests/TextDiffServiceTests.swift
    ├── LearningPolicyTests.swift
    │   ← TypeWhisperTests/TargetAppCorrectionLearningServiceTests.swift
    └── FixtureTests.swift
        ← VoxFlow benchmark fixtures
```

App integration mapping:

```text
Sources/VoxFlowApp/VoiceCorrection/
├── Integration/
│   ├── TranscriptPostProcessingCoordinator.swift
│   │   ← TypeWhisper/Services/PostProcessingPipeline.swift, adapted to VoxFlow ASR final outlet
│   └── ExistingASRResultAdapter.swift
│       ← VoxFlow-specific
├── Observation/
│   ├── FocusedTextObservationProvider.swift
│   │   ← TypeWhisper/Services/TargetAppCorrectionLearningService.swift interface concepts
│   ├── AccessibilityFocusedTextObserver.swift
│   │   ← TypeWhisper/Services/TextInsertionService.swift focused element concepts
│   └── SecureFieldGuard.swift
│       ← VoxFlow-specific privacy policy
└── Views/
    └── VoiceCorrectionView.swift
        ← VoxFlow-specific UI; do not copy TypeWhisper UI naming or layout
```

## TypeWhisper Tests To Port

这些测试结构应迁移到 VoxFlow 的测试体系，必要时复制后改写到 GPLv3 模块测试内：

1. `TypeWhisperTests/DictionaryServiceTests.swift`
   - correction apply；
   - usage count；
   - empty replacement；
   - Japanese / boundary case；
   - 不替换复合词内部；
   - prompt budget 相关测试只作为 Phase 2 provider bias 参考。

2. `TypeWhisperTests/TextDiffServiceTests.swift`
   - diff；
   - high-confidence correction extraction；
   - rewrite / ambiguity rejection。

3. `TypeWhisperTests/TargetAppCorrectionLearningServiceTests.swift`
   - observation；
   - polling；
   - learning candidate；
   - cancellation。

## TypeWhisper Files Not In Phase 1 Runtime

这些文件只作 Phase 2 / Provider bias 参考，第一期不要求 runtime 接入：

- `TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDK/TypeWhisperPlugin.swift`
- `TypeWhisperPluginSDK/Plugins/Qwen3Plugin/Qwen3ContextBiasFormatter.swift`

原因：

- 第一阶段主能力在 ASR final 之后；
- 不要求每个 Provider 支持 prompt / hotword / custom vocabulary；
- top-K provider bias 是 Phase 2。

## Other Open Source Usage

第一期使用策略：

- **FlashText** (`MIT`)
  - 只借鉴 target / aliases 数据模型；
  - 不引入 Python runtime；
  - 不复制 App runtime 代码。

- **OpenBench** (`MIT` code, datasets separately licensed)
  - 只借鉴 keyword metrics、dataset schema、report format；
  - 不把 OpenBench 作为 App runtime dependency；
  - 不要求第一期跑音频 benchmark。

- **JiWER** (`Apache-2.0`)
  - 作为 tools / CI 的 WER / CER cross-check；
  - 生产 App 不依赖 Python。

第一期不引入：

- **Aho-Corasick-Swift** (`Apache-2.0`)
  - Phase 2 才评估；
  - 触发条件：active alias > 1,000 或 5,000 rules P95 超标。

- **BurntSushi/aho-corasick** (`MIT / Unlicense`)
  - Rust 实现；
  - 第一阶段不引入 Rust FFI。

- **SymSpell** (`MIT`)
  - Phase 3 fuzzy 参考；
  - 第一阶段不做 fuzzy。

- **strsim-rs** (`MIT`)
  - Phase 3 fuzzy 参考；
  - 第一阶段不做 edit-distance fuzzy。

## Required Compliance Artifacts

如果复制或改写 TypeWhisper 源码，第一期必须新增：

```text
Packages/VoxFlowVoiceCorrectionKit/COPYING
Packages/VoxFlowVoiceCorrectionKit/NOTICE.md
Packages/VoxFlowVoiceCorrectionKit/SOURCE_ATTRIBUTION.md
Packages/VoxFlowVoiceCorrectionKit/MODIFICATIONS.md
```

其中：

- `COPYING`：GPLv3 license text；
- `NOTICE.md`：TypeWhisper 项目、作者、repo URL、commit、许可证；
- `SOURCE_ATTRIBUTION.md`：逐文件列出 copied / adapted source；
- `MODIFICATIONS.md`：说明 VoxFlow 对原文件做过的结构、命名、行为和测试修改。
