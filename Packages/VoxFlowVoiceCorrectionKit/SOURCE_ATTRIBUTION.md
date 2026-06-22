# 源码归属

## 当前实现

没有逐字复制 TypeWhisper 的实现。Phase 1 core 模型大量改写了 TypeWhisper 文档中描述的领域概念，同时使用 VoxFlow 专属的命名、字段、校验规则和持久化边界。

## 已确认的 TypeWhisper 参考

- `TypeWhisper/Models/DictionaryEntry.swift`
  - 改写后的 VoxFlow 文件：`Core/CorrectionRule.swift`、`Core/CorrectionTargetTerm.swift`、`Core/CorrectionTargetProjection.swift`、`Core/MatchPolicy.swift`、`Core/RuleScope.swift`、`Core/RuleLifecycle.swift`。
  - 改写概念：原文 / 替换对、目标词与 alias 分组、enabled 状态、大小写敏感、source 元数据、confidence 与 usage 计数器。
- `TypeWhisper/Services/DictionaryService.swift`
  - 改写后的 VoxFlow 文件：`Matching/BoundaryClassifier.swift`、`Matching/LinearRuleMatcher.swift`、`Matching/ReplacementApplier.swift`、`Core/CorrectionEvent.swift`。
  - 改写概念：大小写敏感或不敏感的确定性匹配、boundary-safe 纠错、空手动替换、纠错事件元数据。
  - VoxFlow 专属新增：不可变 raw-text 匹配收集、UTF-16 span、确定性重叠解决、end-to-start 应用、非级联引擎组合。
  - VoxFlow 专属安全新增：`Matching/ContextGate.swift` 把 command、translation、interim transcript、安全字段、被禁用规则、非 active 生命周期、不匹配的 app/provider/model/language scope 排除在运行时纠错之外。
- `TypeWhisper/Services/PostProcessingPipeline.swift`
  - 改写后的 VoxFlow 文件：`Processing/VoiceCorrectionEngine.swift`。
  - 改写概念：一个确定性的字典纠错后处理阶段。
- `TypeWhisper/Services/TextDiffService.swift`
  - 改写后的 VoxFlow 文件：`Learning/HighConfidenceCorrectionExtractor.swift`。
  - 改写概念：高置信度替换提取，拒绝 rewrite、insertion-only、deletion-only、歧义、仅大小写、仅标点、超出插入范围、与已应用纠错重叠的反馈。
- `TypeWhisper/Services/TargetAppCorrectionLearningService.swift`
  - 改写后的 VoxFlow 文件：`Learning/FocusedTextObservation.swift`、App 层 `CorrectionObservationCoordinator.swift`。
  - 改写概念：捕获基线 focused element，插入后只重新捕获同一 element，按 2 / 5 / 10 秒轮询，只学习保守纠错。
  - VoxFlow 专属新增：学习到的替换会作为 target term 持久化，带一个或多个误听 alias，而不是平铺规则列表。
- `TypeWhisper/Services/TextInsertionService.swift`
  - 改写后的 VoxFlow 文件：App 层 `AccessibilityFocusedTextObserver.swift`。
  - 改写概念：AX focused element、可读 value、selected range、安全字段守护、同 element 校验；VoxFlow 保留现有的文本插入 contract。

## 非 TypeWhisper 参考

- FlashText：仅数据模型和替换行为思路，未复制运行时源码。
- JiWER：仅用作 benchmark 交叉校验工具，未复制生产源码。
- OpenAI Evals / LanguageTool 风格 fixture：仅借鉴 benchmark 结构，未复制运行时源码。
- VoxFlow OCR Context Boost：临时 hotword 仅用作 LLM prompt 上下文；不写入永久 target-term 存储，也不被纠错引擎直接应用。
