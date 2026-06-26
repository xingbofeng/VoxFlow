# Hyperframe / macOS 多 ASR 语音输入法
# 个人“易错词”后处理系统 V1 技术方案与 Codex 验收规格

版本：V1.0
目标平台：macOS / Swift
设计原则：ASR 无关、确定性优先、失败开放、自动学习保守、Benchmark 先行、重单元测试、轻 E2E

---

## 0. VoxFlow 项目落地修订

以下决策覆盖本文后续旧草案中的推荐值：

- 新版 UI 是左侧主导航一级 tab，标题为 `易错词`；已生成设计稿漏画该 tab，工程实现必须补上。
- 这是对旧 `词汇表 -> 易错词 / 文本替换` 的升级；第一期直接删除旧 `易错词` 子功能、旧 `文本替换` 子功能和旧表数据，不做迁移，不保留旧入口。
- 第一阶段确认走 TypeWhisper GPLv3 模块化引入；模块命名按 VoxFlow 项目命名，不叫 TypeWhisper。
- 新版易错词默认开启：`correctionEnabled = true`，`autoLearningEnabled = true`，`autoLearningAppliesImmediately = true`，`shadowModeEnabled = false`，`providerBiasEnabled = false`，`fuzzyEnabled = false`。
- 纠错顺序为 ASR final 后、可选 LLM refinement 后、文本插入前。TypeWhisper 当前内置顺序为 LLM priority 300、snippets priority 500、dictionary / corrections priority 600，因此易错词作为 LLM 后的确定性最后修正层。
- Benchmark 是第一期硬要求；首版落地门槛为 100 条中英文 correction fixtures，未通过或未纳入的剩余 case 必须记录原因和方向；500 correction + 100 learning 作为扩展门槛。

---

## 1. 背景

当前 App 已具备：

- macOS 全局交互入口；
- HUD / Command 等功能；
- 多个 ASR 模型或 Provider；
- 语音转文字后向当前应用输入文本的能力或规划。

现在需要新增“个人易错词”能力：

1. ASR 将 `Qwen` 识别成“q 问”“去问”；
2. 用户后续手动改成 `Qwen`；
3. 系统在本地保守学习该纠错；
4. 后续无论换用哪个 ASR，只要返回相同误识别文本，后处理层都可修正；
5. 不依赖每个 ASR 都支持 hotword / custom vocabulary；
6. 不依赖把几千个词塞进 prompt；
7. 能用 Benchmark 证明算法有效，并且没有把本来正确的文本改坏。

核心判断：

> 第一阶段的主能力必须放在 ASR 之后，而不是寄希望于每个 ASR 的 prompt、热词或自定义词表。

---

## 2. 第一阶段目标

### 2.1 必须实现

- Provider-independent 的后处理入口；
- 本地 correction rule 存储；
- `exact / boundary / substring` 三种确定性匹配策略；
- 在不可变原文上收集匹配，统一消解冲突，一次性替换；
- 禁止同轮级联替换；
- App scope / dictation mode / secure-field 等最小安全门；
- 替换事件审计；
- 用户后续编辑的保守观察和 candidate 学习；
- 自动学习规则的生命周期、负反馈和撤销；
- 第一阶段即提供纯文本 Benchmark；
- Benchmark 必须能够检测：
  - 该改的有没有改；
  - 不该改的有没有被改；
  - CER/WER 是否退化；
  - 延迟是否明显上升；
- Shadow Mode 与 kill switch；
- 单元测试为主，只保留极少量自动 E2E 和人工 smoke test。

### 2.2 第一阶段明确不做

- 不把全部个人词库塞进 prompt；
- 不要求每个 ASR Provider 增加自定义词表接口；
- 不做中文短词 fuzzy；
- 不做 LLM 语义改写；
- 不使用音频侧 keyword spotting；
- 不默认处理 voice command；
- 不在 streaming interim transcript 上学习；
- GPLv3 来源代码只通过明确的模块化引入流程进入项目；
- 不为了第一期引入 Rust FFI；
- 不为了第一期引入 Aho-Corasick 运行时依赖。

---

## 3. 总体架构

```text
Microphone
   ↓
Existing ASR Provider
   ├── Whisper / WhisperKit
   ├── Qwen ASR
   ├── Apple Speech
   ├── Parakeet
   ├── Cloud ASR
   └── Other providers
   ↓
Final ASR Result
   ├── rawText
   ├── providerID
   ├── modelID
   ├── language
   ├── alternatives?       optional
   └── confidence?         optional
   ↓
TranscriptPostProcessingCoordinator
   ├── existing deterministic cleanup
   ├── optional LLM refinement
   └── VoiceCorrection final deterministic pass
   ↓
VoiceCorrectionCore
   ├── RuleSnapshot
   ├── LinearRuleMatcher V1
   ├── BoundaryClassifier
   ├── ContextGate
   ├── ConflictResolver
   ├── ReplacementApplier
   └── CorrectionResult
   ↓
TextInsertionService
   ↓
Focused external app
   ↓
CorrectionObservationCoordinator
   ├── recapture focused text
   ├── high-confidence diff
   ├── negative feedback
   └── automatic learning
```

必须保留两个文本：

```text
rawText       ASR 原始结果，永远不被覆盖
finalText     后处理和其他 workflow 后的最终文本
```

这样才能：

- Benchmark 原始效果和后处理效果；
- 分析某条规则是否误伤；
- 防止自动学习形成反馈环；
- 支持用户撤销规则。

---

## 4. 与现有项目的集成边界

### 4.1 语音听写入口

易错词模块只接语音听写 final transcript：

```text
ASR final result
→ VoiceCorrection
→ Text insertion
```

### 4.2 Voice Command

第一阶段默认：

```text
dictation mode    开启 correction
command mode      关闭 correction
translation mode  关闭 correction
```

原因：对可执行命令做模糊或个人化纠错，可能改变执行语义。

后续若需要 command correction，只允许：

- 手动规则；
- `safeForCommand == true`；
- exact 或明确的长短语 boundary；
- 禁止 fuzzy；
- 命令执行前仍需原有安全校验。

### 4.3 HUD

后处理预期是毫秒级，不新增显式 HUD 状态，避免状态闪烁。

状态建议：

```text
Listening
→ Transcribing
→ Existing processing
→ Inserting
```

后处理在 `Transcribing` 与 `Inserting` 之间完成，只记录内部 trace。

若后处理异常：

```text
fail open → 插入 rawText
```

不能因为易错词模块故障阻断语音输入。

---

## 5. 推荐项目结构

优先建立本地 Swift Package，隔离纯算法和 AppKit / SwiftData：

```text
Packages/
└── VoxFlowVoiceCorrectionKit/
    ├── Package.swift
    ├── Sources/
    │   ├── VoiceCorrectionCore/
    │   │   ├── Domain/
    │   │   │   ├── CorrectionRule.swift
    │   │   │   ├── CorrectionContext.swift
    │   │   │   ├── CorrectionMatch.swift
    │   │   │   ├── CorrectionResult.swift
    │   │   │   └── RuleSnapshot.swift
    │   │   ├── Matching/
    │   │   │   ├── LinearRuleMatcher.swift
    │   │   │   ├── BoundaryClassifier.swift
    │   │   │   ├── ContextGate.swift
    │   │   │   ├── ConflictResolver.swift
    │   │   │   └── ReplacementApplier.swift
    │   │   ├── Learning/
    │   │   │   ├── HighConfidenceCorrectionExtractor.swift
    │   │   │   ├── LearningPolicy.swift
    │   │   │   └── RuleConfidenceReducer.swift
    │   │   └── Metrics/
    │   │       ├── EditDistance.swift
    │   │       ├── CorrectionMetrics.swift
    │   │       └── LatencySummary.swift
    │   └── VoxFlowVoiceCorrectionBench/
    │       └── main.swift
    └── Tests/
        └── VoiceCorrectionCoreTests/
            ├── RuleValidationTests.swift
            ├── BoundaryClassifierTests.swift
            ├── LinearRuleMatcherTests.swift
            ├── ConflictResolverTests.swift
            ├── ReplacementApplierTests.swift
            ├── ContextGateTests.swift
            ├── CorrectionEngineFixtureTests.swift
            ├── HighConfidenceCorrectionExtractorTests.swift
            ├── LearningPolicyTests.swift
            └── MetricTests.swift

App/
└── VoiceCorrection/
    ├── Persistence/
    │   ├── CorrectionRuleRecord.swift
    │   ├── CorrectionRuleStore.swift
    │   └── SQLiteCorrectionRuleStore.swift
    ├── Integration/
    │   ├── TranscriptPostProcessingCoordinator.swift
    │   ├── ExistingASRResultAdapter.swift
    │   ├── CorrectionFeatureFlags.swift
    │   └── CorrectionDiagnostics.swift
    ├── Observation/
    │   ├── FocusedTextObservationProvider.swift
    │   ├── AccessibilityFocusedTextObserver.swift
    │   ├── CorrectionObservationCoordinator.swift
    │   └── SecureFieldGuard.swift
    └── UI/
        └── VoiceCorrectionView.swift

Benchmarks/
├── Fixtures/
│   ├── rules_v1.json
│   ├── correction_cases_v1.jsonl
│   ├── learning_cases_v1.jsonl
│   └── generated_scale_config.json
└── Baselines/
    └── phase1-baseline.json
```

若现有工程不适合本地 Package，可保持同样模块边界放在 App target 中，但 `VoiceCorrectionCore` 不能 import：

- AppKit；
- ApplicationServices；
- SwiftData；
- UI 框架；
- 任一具体 ASR SDK。

---

## 6. 第一阶段依赖决策

### 6.1 运行时依赖

第一阶段新增运行时第三方依赖：

```text
0 个
```

使用：

- Swift Standard Library；
- Foundation；
- AppKit / ApplicationServices，仅 App adapter；
- SwiftData，仅在项目现有存储适合时。

这样风险最低，也避免：

- GPL 污染；
- Rust FFI；
- 旧 Swift 库兼容问题；
- 某 ASR SDK 的能力差异。

### 6.2 测试与工具依赖

允许在 `tools/` 或 CI 中使用：

- `jiwer`：WER / CER 交叉验证；
- Python 标准库；
- OpenBench 的 metric 和 dataset 设计作为参考。

生产 App 不依赖 Python。

---

## 7. 开源仓库与精确参考文件

> 许可证结论只是工程选型说明，不替代法律意见。商业闭源项目尤其不要直接复制 GPLv3 代码。

### 7.1 TypeWhisper

仓库：

- https://github.com/TypeWhisper/typewhisper-mac
- 参考 commit：`6c46bfc676539e2a1a245a01dca9a4afd6f2cb63`
- 许可证：GPLv3
- 使用方式：优先模块化引入；允许复制或改写必要源码，但必须按 GPLv3 履约，集中在独立 VoxFlowVoiceCorrection 模块或 package 内，并保留来源、许可证和修改说明。
- 具体复制 / 改写范围与合规产物见 `docs/voice-correction/opensource-import-plan.md`。

精确参考文件：

1. `TypeWhisper/Models/DictionaryEntry.swift`
   - `term / correction` 类型；
   - original / replacement；
   - enabled / caseSensitive；
   - usageCount；
   - createdAt / updatedAt。

2. `TypeWhisper/Services/DictionaryService.swift`
   - correction CRUD；
   - `applyCorrections(to:)`；
   - exact / boundary / substring；
   - boundary-safe replacement；
   - usageCount；
   - 从用户编辑学习 correction。

3. `TypeWhisper/Services/PostProcessingPipeline.swift`
   - 字典 correction 放在统一后处理 pipeline 中；
   - 这是本项目应使用的主要集成思想。

4. `TypeWhisper/Services/TextDiffService.swift`
   - word diff；
   - high-confidence correction extraction；
   - 过滤大规模 rewrite；
   - 限制建议数量。

5. `TypeWhisper/Services/TargetAppCorrectionLearningService.swift`
   - 插入后轮询；
   - 默认 2 / 5 / 10 秒；
   - 重新捕获 focused text；
   - 只在刚插入范围内提取变化。

6. `TypeWhisper/Services/TextInsertionService.swift`
   - AX focused element；
   - AX value / selected text / selected range；
   - clipboard + ⌘V；
   - Accessibility 写入后验证；
   - active app context；
   - clipboard 保存恢复。

7. `TypeWhisperTests/DictionaryServiceTests.swift`
   - correction 应用；
   - usageCount；
   - 空 replacement；
   - 日文边界；
   - 不替换复合词内部；
   - prompt budget 测试。

8. `TypeWhisperTests/TextDiffServiceTests.swift`
   - diff 和 correction extraction 的单元测试结构。

9. `TypeWhisperTests/TargetAppCorrectionLearningServiceTests.swift`
   - observation / poll / learning 的测试结构。

10. `TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDK/TypeWhisperPlugin.swift`
    - `DictionaryTermsSupport`；
    - `DictionaryTermsBudget`；
    - provider capability；
    - term 数量、单词长度、总字符预算；
    - clipped prompt 设计。

11. `TypeWhisperPluginSDK/Plugins/Qwen3Plugin/Qwen3ContextBiasFormatter.swift`
    - 不同 Provider 如何将有限 term 转成 Provider-specific prompt。

12. `TypeWhisper/ViewModels/DictationViewModel.swift`
    - dictation 生命周期的集成位置参考。

建议链接格式：

```text
https://github.com/TypeWhisper/typewhisper-mac/blob/
6c46bfc676539e2a1a245a01dca9a4afd6f2cb63/
<上述路径>
```

### 7.2 Aho-Corasick-Swift

仓库：

- https://github.com/fpg1503/Aho-Corasick-Swift
- 参考 commit：`d48e7b4f370a3554f89339ee58c754916322b217`
- 许可证：Apache-2.0
- 使用阶段：Phase 2，而非 V1。

精确参考文件：

- `Source/Trie/Trie.swift`
  - Trie；
  - parse；
  - overlap 处理；
  - tokenize。

- `Source/Trie/TrieConfig.swift`
  - `removeOverlaps`；
  - `onlyDelimited`；
  - case insensitive；
  - diacritic insensitive。

- `Source/Extensions/StringExtensions.swift`
  - Unicode / boundary 辅助。

- `Tests/AhoCorasickTests.swift`
  - 多 pattern、overlap、boundary 测试结构。

- `Package.swift`
  - SPM 集成入口。

采用策略：

```text
V1：不用
Phase 2：先做兼容性 PoC
通过后才引入或 fork
```

Phase 2 引入门槛：

- alias > 1,000；
- 或 V1 线性 matcher 在 5,000 / 10,000 规则 Benchmark 上未达性能目标；
- Swift 版本、Unicode range、strict concurrency 测试通过；
- Apache 许可证和 NOTICE 保留。

### 7.3 BurntSushi/aho-corasick

仓库：

- https://github.com/BurntSushi/aho-corasick
- 许可证：MIT / Unlicense
- 语言：Rust。

能力：

- 多 pattern search；
- overlapping matches；
- ASCII case-insensitive；
- leftmost-first；
- leftmost-longest；
- search and replace；
- SIMD。

使用建议：

```text
只有当项目已经有 Rust core / UniFFI / C FFI 时考虑。
第一期绝对不为它新引入 Rust。
```

### 7.4 FlashText

仓库：

- https://github.com/vi3k6i5/flashtext
- 参考 commit：`f49274459bc9879789c6e6bb64bf05af755de0b3`
- 许可证：MIT
- 使用方式：借鉴数据模型与替换行为，不在 App 内嵌 Python。

精确参考文件：

- `flashtext/keyword.py`
  - `KeywordProcessor`；
  - `add_keyword(unclean, clean)`；
  - `replace_keywords`；
  - `extract_keywords(..., span_info=True)`；
  - clean target 对多个 alias。

- `test/test_dictionary_loading.py`
- `test/test_loading_keyword_list.py`
- `test/test_file_load.py`

建议借鉴的数据模型：

```json
{
  "Qwen": ["q 问", "去问", "queue win"],
  "Hyperframe": ["hyper frame", "海帕 frame"]
}
```

### 7.5 SymSpell

仓库：

- https://github.com/wolfgarbe/SymSpell
- 参考 commit：`148059304d907120ca4f768d68e47ec01e6f861a`
- 许可证：MIT
- 使用阶段：Phase 3，可选 fuzzy。

精确参考文件：

- `SymSpell/SymSpell.cs`
  - `Lookup`；
  - `LookupCompound`；
  - delete-only candidate index；
  - edit distance candidate；
  - frequency ranking。

- `SymSpell.CommandLine/SymSpell.CommandLine.cs`
  - 命令行 benchmark / usage 参考。

适用：

- `Chat GBT → ChatGPT`；
- `Whisper Kid → WhisperKit`；
- 空格拆分、合并；
- 英文拼写误差。

不适用：

- `去问 → Qwen`；
- `请问 → Qwen`；
- 高歧义中文短词。

### 7.6 strsim-rs

仓库：

- https://github.com/rapidfuzz/strsim-rs
- 参考 commit：`dacc84c0dc61eff0ee0ff66962bcf2e17018ad26`
- 许可证：MIT
- 精确文件：`src/lib.rs`

提供：

- Levenshtein；
- normalized Levenshtein；
- Damerau-Levenshtein；
- Jaro；
- Jaro-Winkler；
- Sørensen-Dice。

使用建议：

- 只有当项目已有 Rust core 时直接使用；
- 否则 Phase 3 在 Swift 中实现非常小的受限距离函数；
- fuzzy 只对已经召回的小候选集打分，禁止全词库暴力比较。

### 7.7 OpenBench

仓库：

- https://github.com/argmaxinc/OpenBench
- 参考 commit：`9966861f4c4c4fa4dfad048af7820241a3c32374`
- 代码许可证：MIT；
- 数据集各自有许可证。

精确参考文件：

- `src/openbench/metric/metric.py`
  - WER；
  - keyword precision；
  - keyword recall；
  - keyword F-score；
  - streaming latency。

- `src/openbench/metric/keyword_boosting_metrics/boosting_metrics.py`
  - keyword metric 具体计算。

- `config/benchmark_config/base.yaml`
  - benchmark 配置方式。

- `config/benchmark_config/datasets/earnings22-keywords.yaml`
  - keyword dataset 配置。

- `config/benchmark_config/datasets/earnings22-keywords-debug.yaml`
  - 小规模 debug benchmark。

- `src/openbench/dataset/dataset_aliases.py`
  - dataset alias 组织。

- `BENCHMARKS.md`
  - no-keyword / chunk-keyword / file-keyword 三组结果；
  - WER / precision / recall / F1 报告格式。

第一期使用方式：

```text
借鉴指标、dataset schema 和报告结构；
不把整个 OpenBench 引入 App；
不要求每个 ASR 跑音频 benchmark。
```

### 7.8 JiWER

仓库：

- https://github.com/jitsi/jiwer
- 参考 commit：`2227002889f20f3fb19d523eeb322732cb67b431`
- 许可证：Apache-2.0

精确参考文件：

- `src/jiwer/measures.py`
  - WER / CER API。

- `src/jiwer/process.py`
  - reference / hypothesis 对齐；
  - substitutions / insertions / deletions。

- `src/jiwer/alignment.py`
  - alignment 可视化。

- `src/jiwer/transformations.py`
  - 文本 normalize。

- `tests/test_alignment.py`
- `tests/test_empty_ref.py`
- `docs/usage.md`

使用方式：

- CI / tools 使用；
- Swift Benchmark 先算一份；
- JiWER 再交叉验证；
- 两者不一致则 Benchmark 失败。

---

## 8. Core API 设计

### 8.1 CorrectionRule

```swift
public struct CorrectionRule: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID

    public var original: String
    public var replacement: String

    public var matchPolicy: MatchPolicy
    public var scope: RuleScope
    public var allowedModes: Set<InputMode>

    public var source: RuleSource
    public var lifecycle: RuleLifecycle

    public var caseSensitive: Bool
    public var confidence: Double

    public var observedCount: Int
    public var appliedCount: Int
    public var revertedCount: Int

    public var providerID: String?
    public var modelID: String?
    public var language: String?

    public var isEnabled: Bool

    public var createdAt: Date
    public var updatedAt: Date
    public var lastAppliedAt: Date?
}
```

### 8.2 MatchPolicy

```swift
public enum MatchPolicy: String, Codable, Sendable {
    case exact
    case boundary
    case substring
}
```

约束：

- 自动学习规则默认 `.boundary`；
- 自动学习不允许 `.substring`；
- 单字 CJK 自动学习默认拒绝；
- replacement 为空的删除规则必须手动创建；
- `original == replacement` 拒绝；
- original / replacement 超长拒绝；
- original 为空拒绝。

### 8.3 RuleScope

```swift
public enum RuleScope: Codable, Sendable, Equatable {
    case global
    case application(bundleIdentifier: String)
    case project(id: String)
    case session(id: UUID)
}
```

第一阶段支持：

- global；
- application。

自动学习默认：

```text
application scope
```

不能直接学成 global。

### 8.4 InputMode

```swift
public enum InputMode: String, Codable, Sendable {
    case dictation
    case command
    case translation
}
```

第一阶段只允许 `.dictation`。

### 8.5 CorrectionContext

```swift
public struct CorrectionContext: Sendable {
    public let sessionID: UUID
    public let mode: InputMode

    public let providerID: String
    public let modelID: String?
    public let language: String?

    public let applicationName: String?
    public let bundleIdentifier: String?
    public let projectID: String?

    public let isFinalTranscript: Bool
    public let isSecureField: Bool
}
```

第一阶段不放完整屏幕文本，避免隐私和污染。

### 8.6 CorrectionResult

```swift
public struct CorrectionResult: Sendable {
    public let rawText: String
    public let finalText: String
    public let replacements: [AppliedCorrection]
    public let skippedReasons: [CorrectionSkip]
    public let elapsedNanoseconds: UInt64
    public let failedOpen: Bool
}
```

### 8.7 TranscriptPostProcessor

```swift
public protocol TranscriptPostProcessor: Sendable {
    func process(
        rawText: String,
        context: CorrectionContext
    ) async -> CorrectionResult
}
```

强制：

- 永不 throw 到上层；
- 任何内部错误返回 rawText；
- 只能处理 final transcript；
- 不能 mutate 原 ASR result。

---

## 9. Rule Store 与内存快照

### 9.1 协议

```swift
public protocol CorrectionRuleStore: Sendable {
    func fetchEnabledRules() async throws -> [CorrectionRule]
    func upsert(_ rule: CorrectionRule) async throws
    func delete(id: UUID) async throws
    func recordApplied(id: UUID, at: Date) async throws
    func recordReverted(id: UUID, at: Date) async throws
    func replaceSnapshotIfNeeded() async throws -> RuleSnapshot
}
```

### 9.2 持久化选型

优先：

```text
项目已有 SwiftData → 继续 SwiftData
项目已有 SQLite/GRDB → 继续现有方案
项目无持久层 → SwiftData
```

不要为了这个功能单独引入数据库框架。

### 9.3 处理性能

每次语音输入不能直接逐条读数据库。

流程：

```text
DB
→ RuleSnapshot
→ in-memory matching
```

`RuleSnapshot` 必须：

- immutable；
- Sendable；
- 有 version；
- 规则更新后异步重建；
- 处理线程只读；
- DB 失败时使用上一个快照或空快照。

---

## 10. V1 Matcher

### 10.1 为什么第一期不用 Aho-Corasick

第一期规则规模未知，首要目标是：

- 正确性；
- 可测试；
- 易定位误伤；
- 易回滚。

因此 V1 使用线性 matcher：

```text
for rule in eligibleRules:
    find all matches in immutable rawText
```

是否需要 Aho-Corasick，由 Benchmark 决定。

### 10.2 exact

```text
trimmed rawText == trimmed original
```

仅整段匹配。

### 10.3 boundary

默认策略。

Latin / number alias：

- 前一个字符不能是 Latin / number / `_`；
- 后一个字符不能是 Latin / number / `_`。

CJK：

- 不把“字符串前后存在汉字”简单视为合法词边界；
- 两字或更短的高歧义 CJK alias 必须 app scoped；
- 第一阶段不做自动中文分词；
- 必要时由规则明确声明 `.substring`，但只允许手动规则。

### 10.4 substring

仅显式手动规则可用。

典型：

```text
⌘⇧V → ⌘⇧V
open ai dot com → openai.com
```

禁止：

- 自动学习 substring；
- 单字 substring；
- 高歧义中文短语 substring。

---

## 11. 不可变匹配与冲突消解

禁止：

```text
A → B
B → C
导致 A 在同一轮变成 C
```

正确流程：

1. 所有 matcher 只读 `rawText`；
2. 收集所有 candidate spans；
3. ContextGate 过滤；
4. ConflictResolver 统一处理重叠；
5. 从文本尾部向前替换；
6. replacement 不参与同轮再次扫描。

优先级建议：

```text
manual source
> imported source
> trusted learned
> candidate learned

application scope
> global scope

exact
> boundary
> substring

higher confidence
> lower confidence

longer match
> shorter match

left-most
> right-most
```

`ConflictResolver` 必须完全确定性。

---

## 12. ContextGate V1

```swift
public protocol ContextGate: Sendable {
    func accepts(
        match: CorrectionMatch,
        context: CorrectionContext
    ) -> Bool
}
```

第一阶段规则：

- `isFinalTranscript == false` → 拒绝；
- mode 非 dictation → 拒绝；
- secure field → 拒绝；
- App scope 不匹配 → 拒绝；
- language 限制不匹配 → 拒绝；
- lifecycle 非 active / trusted → 拒绝；
- disabled → 拒绝；
- confidence 低于阈值 → 拒绝；
- 单字 CJK auto learned → 拒绝。

第一阶段不做复杂附近词语义打分。

像：

```text
去问 → Qwen
```

这种规则只能：

- application scope；
- 多次重复学习；
- 或手动创建；
- 默认不得 global。

---

## 13. 多 ASR Provider 设计

### 13.1 关键原则

后处理层永远位于 Provider 统一出口之后：

```text
Provider-specific SDK
→ Existing normalized ASR result
→ Correction engine
```

因此：

- Provider 不支持 prompt：仍可 correction；
- Provider prompt 很短：仍可 correction；
- Provider 更换：个人词库仍有效；
- 本地和云端 ASR 共用同一 correction。

### 13.2 Optional Provider Capability

第一阶段只定义接口，不要求所有 Provider 实现：

```swift
public enum VocabularyBiasKind: String, Sendable {
    case unsupported
    case prompt
    case keyterms
    case customVocabulary
}

public struct VocabularyBiasBudget: Sendable {
    public var maxTerms: Int?
    public var maxCharsPerTerm: Int?
    public var maxWordsPerTerm: Int?
    public var maxTotalChars: Int?
}

public protocol VocabularyBiasCapabilityProviding {
    var vocabularyBiasKind: VocabularyBiasKind { get }
    var vocabularyBiasBudget: VocabularyBiasBudget? { get }
}
```

默认适配器：

```swift
extension ExistingASRProvider {
    var vocabularyBiasKind: VocabularyBiasKind { .unsupported }
}
```

不支持的 Provider 不需要改业务逻辑。

### 13.3 Phase 2 top-K

未来只选择当前最相关 term：

```text
App scope
+ project scope
+ recent usage
+ frequency
→ top-K
→ provider budget clipping
```

完整词库始终留在后处理层。

---

## 14. 自动学习设计

### 14.1 Observation token

插入之前创建：

```swift
public struct InsertionObservationToken: Sendable {
    public let sessionID: UUID
    public let bundleIdentifier: String?
    public let rawText: String
    public let insertedText: String
    public let appliedCorrections: [AppliedCorrection]
    public let focusedElementIdentity: String?
    public let baselineValueHash: String?
    public let insertedRange: NSRange?
    public let createdAt: Date
}
```

生产日志不记录完整 rawText；token 仅存在于本地短生命周期内。

### 14.2 观察策略

参考 TypeWhisper：

```text
2 秒
5 秒
10 秒
```

每次：

- 确认 focus 仍是同一个元素；
- bundle ID 未变；
- 不是 secure field；
- 可以读取文本；
- 文本长度在限制内；
- 用户没有切换文档或大规模 rewrite。

### 14.3 V1 高置信提取

只接受：

- 修改发生在刚插入区域内；
- 修改前后 token 数相同；
- 最多 3 个 substitution；
- 非纯标点；
- 非仅大小写变化；
- original / replacement 非空；
- original != replacement；
- changed ratio 不超过阈值；
- 插入文本在 baseline 中可唯一定位；
- 修改不与现有 applied correction span 冲突。

不接受：

- 大段重写；
- 增加句子；
- 删除整段；
- 多词拆分 / 合并；
- App 自动格式化；
- final text 无法可靠定位；
- interim transcript；
- secure field；
- command mode。

### 14.4 防反馈环

若当前 dictation 已经应用 correction：

```text
raw:       q 问
inserted:  Qwen
user final: 去问
```

不能学习：

```text
Qwen → 去问
```

必须记录：

```text
原规则 q 问 → Qwen 被用户反向修改
→ revertedCount + 1
→ confidence 降低
```

新规则学习只允许：

- changed span 不与已应用 correction 重叠；
- 或能明确映射回 raw span。

第一阶段若无法证明，宁愿不学习。

### 14.5 生命周期

```swift
public enum RuleLifecycle: String, Codable, Sendable {
    case observed
    case candidate
    case trusted
    case active
    case suspended
    case retired
}
```

建议默认：

- 手动规则：active；
- `autoLearningAppliesImmediately = true` 时，高置信第一次观察直接 active，confidence 0.90；
- `autoLearningAppliesImmediately = false` 时，高置信观察生成 candidate，confidence 0.40，用户确认后 active；
- 用户改回：confidence -0.35；
- `revertedCount >= 2`：suspended；
- 长期不用：衰减；
- 模型版本改变后：不删除，但降低优先级。

---

## 15. Security 与隐私

硬性规则：

- secure field 不读取；
- secure field 不学习；
- secure field 不打日志；
- 密码管理器可配置 App 黑名单；
- 原始整句默认不写 production log；
- 只存 alias / replacement / scope / counters；
- 所有学习默认本地；
- 云同步必须显式开启；
- 支持删除单条；
- 支持清空全部；
- 支持全局 kill switch；
- 支持关闭自动学习；
- 支持关闭自动学习直接生效，改为 candidate-only；
- 支持 Shadow Mode；
- candidate 可在 `易错词` tab 中查看。

`SecureFieldGuard` 至少检查：

- AX role / subrole；
- value 是否不可读取；
- bundle blacklist；
- 项目已有 privacy mode；
- 观察能力不确定时默认拒绝学习。

---

## 16. Benchmark：第一期必须交付

### 16.1 为什么先做纯文本 Benchmark

后处理引擎的输入是 ASR 文本，不是音频。

第一期需要独立回答：

```text
在给定 raw transcript 和规则时：
算法是否真的纠正？
是否误伤？
是否造成整体文本退化？
延迟是多少？
```

音频端到端 Benchmark 放在后续，不作为第一期阻塞项。

### 16.1.1 开源 Benchmark 参考

第一期 benchmark 设计参考以下开源项目的做法：

- JiWER：ASR 文本评估使用 WER / CER / edit-distance，并支持 transform 归一化与 substitution / insertion / deletion 频次输出。
- OpenAI Evals：评测数据使用 JSONL，评测配置和样本分离，便于复现和 review。
- LanguageTool：规则测试内嵌 incorrect / correct examples，incorrect 必须命中，correct 和 antipattern 必须避免误伤。
- FlashText：关键词替换类库同时关注替换正确性和性能曲线。

VoxFlow 因此采用：

- JSONL fixtures；
- 固定 rules 文件；
- fixed baseline；
- positive + hard-negative pairs；
- event-level assertion；
- CER / WER before-after；
- substitution / insertion / deletion error counts；
- P50 / P95 / P99 latency；
- Markdown + JSON report；
- failure table with `id` / `raw` / `expected` / `actual` / expected events / actual events。

### 16.2 Fixture Schema

`correction_cases_v1.jsonl`：

```json
{
  "id": "qwen_positive_001",
  "raw": "我想把 q 问 模型接进去",
  "expected": "我想把 Qwen 模型接进去",
  "context": {
    "mode": "dictation",
    "providerID": "mock",
    "modelID": "mock-v1",
    "language": "zh",
    "bundleIdentifier": "com.todesktop.cursor"
  },
  "expectedEvents": [
    {
      "ruleID": "qwen-q-wen",
      "from": "q 问",
      "to": "Qwen",
      "shouldApply": true
    }
  ],
  "tags": ["positive", "zh-en", "technical"]
}
```

负例：

```json
{
  "id": "qwen_negative_001",
  "raw": "我去问一下他这个问题",
  "expected": "我去问一下他这个问题",
  "context": {
    "mode": "dictation",
    "providerID": "mock",
    "language": "zh",
    "bundleIdentifier": "com.tencent.xinWeChat"
  },
  "expectedEvents": [],
  "tags": ["negative", "ambiguity"]
}
```

### 16.3 初始数据集规模

首版第一期最低硬门槛：

- 100 条中英文 correction fixtures；
- negative case 数量不少于 positive case；
- 必须覆盖 exact、boundary、substring、hard negative、overlap / cascade、punctuation、mode bypass；
- 每条 fixture 都要能追踪 expected events；
- 使用 production correction engine，不用测试专用替代实现。

扩展门槛：

- 正向 exact：50；
- 正向 boundary：100；
- 反向 hard negative：200；
- overlap / cascade：50；
- Unicode / emoji / punctuation：50；
- mode / app scope / secure：50；
- learning extraction：100 独立 case。

扩展到稳定公开版前，总计至少：

```text
500 correction cases
100 learning cases
```

正负例比例至少：

```text
negative >= positive
```

高歧义 alias 的负例应为正例的 5～20 倍。

### 16.4 指标

必须计算：

1. `SentenceExactMatchRate`
2. `CorrectionPrecision`
3. `CorrectionRecall`
4. `CorrectionF1`
5. `FalseReplacementRate`
6. `RegressionRate`
7. `CERBefore`
8. `CERAfter`
9. `WERBefore`
10. `WERAfter`
11. `P50Latency`
12. `P95Latency`
13. `P99Latency`

事件级指标以 fixture 中的 `expectedEvents` 为准，不依赖模糊文本对齐。

定义：

```text
TP：预期替换且正确替换
FP：发生了 fixture 未预期的替换
FN：预期替换但未发生
Regression：raw 已等于 expected，但 final 不等于 expected
FalseReplacement：negative case 被改变
```

### 16.5 Phase 1 Benchmark 验收门槛

首版 100 条支持集和扩展支持集都必须满足：

```text
CorrectionPrecision       = 1.000
CorrectionRecall          = 1.000
FalseReplacementRate      = 0
RegressionRate            = 0
SentenceExactMatchRate    = 1.000
CERAfter                  <= CERBefore
WERAfter                  <= WERBefore
```

学习提取支持集：

```text
LearningPrecision         = 1.000
所有明确支持的 substitution case 必须提取
所有 rewrite / ambiguity case 必须拒绝
```

首版第一期不强制 100 条 learning fixture，但必须有 targeted learning tests，覆盖 high-confidence substitution、rewrite 拒绝、ambiguous diff 拒绝、focus change 取消、fake clock / fake observer。

未通过或未纳入的剩余 case 必须写入 `report.md` 和 `report.json`：

- `id`
- 当前结果
- 失败原因
- 分类：matcher / boundary / conflict / metric / fixture-data / not-yet-supported
- 后续方向
- 是否阻塞本期

性能：

- Release build；
- Reference Apple Silicon；
- 1,000 rules + 200 字符：P95 < 10 ms；
- 5,000 rules + 200 字符：P95 < 25 ms；
- 10,000 rules + 200 字符：记录结果，不强制第一期通过；
- 若 5,000 规则不达标，Phase 2 Aho-Corasick 升级进入必做。

共享 CI runner 不用绝对时间阻塞 PR，使用：

- 功能指标硬门；
- performance baseline 相对退化 >20% 阻塞；
- Reference Mac nightly 跑绝对门槛。

### 16.6 Runner

命令目标：

```bash
swift run --package-path Packages/VoxFlowVoiceCorrectionKit VoxFlowVoiceCorrectionBench \
  --fixtures Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Fixtures \
  --baseline Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Baselines/phase1-baseline.json \
  --output .build/voice-correction-benchmark
```

CI cross-check：

```bash
uv run tools/voice_correction_jiwer_check.py \
  --report .build/voice-correction-benchmark/report.json
```

### 16.7 Baseline Gate

提交：

```text
Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Baselines/phase1-baseline.json
```

PR 失败条件：

- precision 下降；
- 新增 false replacement；
- 新增 regression；
- supported recall 下降；
- CERAfter 上升；
- benchmark fixture 未全部执行；
- report schema 变化但未升级版本；
- production engine 与 benchmark engine 不是同一实现。

---

## 17. Unit Test 设计

### 17.1 RuleValidationTests

覆盖：

- 空 original；
- self replacement；
- 过长；
- 单字 CJK auto rule；
- auto substring；
- invalid confidence；
- duplicate key；
- empty replacement 手动规则；
- scope 编解码。

### 17.2 BoundaryClassifierTests

覆盖：

- Latin；
- number；
- underscore；
- 中文；
- 中英混合；
- emoji；
- smart quote；
- punctuation；
- Katakana / Japanese compound 参考 TypeWhisper；
- 组合字符；
- NFC / NFD；
- 字符串首尾。

### 17.3 LinearRuleMatcherTests

覆盖：

- exact；
- case-sensitive；
- case-insensitive；
- 多 occurrence；
- no match；
- app scope；
- language scope；
- disabled；
- final vs interim。

### 17.4 ConflictResolverTests

覆盖：

- 长匹配优先；
- scope 优先；
- manual 优先；
- confidence 优先；
- left-most；
- 相同 span 不同 replacement；
- non-overlap 全保留；
- 完全包含；
- 部分重叠；
- 结果稳定性。

### 17.5 ReplacementApplierTests

覆盖：

- 从尾部替换；
- Unicode range；
- emoji；
- 多 replacement；
- replacement 长度变化；
- replacement 为空；
- 不级联；
- 输出 event span。

### 17.6 ContextGateTests

覆盖：

- dictation；
- command；
- secure field；
- app scope；
- global；
- language；
- candidate / active / suspended；
- confidence threshold。

### 17.7 HighConfidenceCorrectionExtractorTests

覆盖：

- 单 token substitution；
- 多 token 但数量相等；
- 大 rewrite 拒绝；
- insertion 拒绝；
- deletion 拒绝；
- punctuation-only 拒绝；
- case-only 拒绝；
- >3 suggestions 拒绝；
- 插入区域外修改拒绝；
- applied correction overlap 拒绝。

### 17.8 LearningPolicyTests

覆盖：

- 第一次 candidate；
- 第二次 trusted；
- 第三次 active；
- 跨 App 不合并；
- negative feedback；
- suspend；
- decay；
- duplicate；
- model version change。

### 17.9 FixtureTests

所有 JSONL case 参数化执行。

要求：

```text
fixture case 失败时输出：
- case id
- raw
- expected
- final
- applied rules
- skipped reasons
```

---

## 18. E2E 策略

### 18.1 自动 E2E，仅两条

1. `MockASR → coordinator → correction → FakeTextInsertion`
   - 验证所有 Provider 共用统一出口；
   - 验证 raw / final 分离；
   - 验证 command 不受影响。

2. `FakeFocusedTextObservationProvider`
   - baseline；
   - 2 / 5 / 10 秒 fake clock；
   - 用户修改；
   - candidate 产生；
   - focus change 后取消。

禁止在 CI 中依赖真实 TextEdit / Accessibility 权限。

### 18.2 人工 Smoke

开发版检查：

1. TextEdit；
2. Notes；
3. Safari textarea；
4. Chrome textarea；
5. Cursor；
6. 密码字段；
7. 中英文混合；
8. 切换两个 ASR Provider；
9. 关闭 feature flag；
10. Shadow Mode。

Smoke 文档必须记录：

- App；
- bundle ID；
- 输入方式；
- raw；
- final；
- 用户修改；
- 是否学习；
- 是否发生误伤。

---

## 19. Feature Flag 与上线策略

```swift
struct CorrectionFeatureFlags {
    var correctionEnabled: Bool
    var shadowModeEnabled: Bool
    var autoLearningEnabled: Bool
    var providerBiasEnabled: Bool
    var fuzzyEnabled: Bool
}
```

上线顺序：

1. 默认开启新版易错词和自动学习；
2. Shadow Mode 默认关闭，但保留一键开启用于诊断；
3. 手动规则 correction；
4. trusted learned correction；
5. auto learning；
6. Phase 2 prompt top-K；
7. Phase 3 fuzzy。

Shadow Mode：

- 完整执行 matcher；
- 不改变 final text；
- 记录 wouldApply event；
- 不上传 raw sentence；
- Benchmark / debug 可导出本地数据。

---

## 20. Codex 任务拆解与验收

执行纪律和最终验收以 Goal Spec 为准：

```text
docs/voice-correction/voice_correction_goal_spec.md
```

主执行清单以中文 Markdown checkbox 文件为准：

```text
docs/voice-correction/voice_correction_phase1_tasks.md
```

本节保留为技术规格中的概要索引；执行时逐项勾选上面的 Markdown 清单。

### T0：项目发现与集成地图

任务：

- 找到所有 ASR Provider；
- 找到 interim / final 统一出口；
- 找到文本插入服务；
- 找到 active app / bundle ID；
- 找到 command / dictation mode；
- 找到持久化方案；
- 找到 feature flag 机制；
- 输出 `docs/voice-correction/integration-map.md`。

验收：

- 文档列出真实文件路径和关键 symbol；
- 明确 correction 插入点；
- 明确 command 不接入；
- build 无变化；
- 所有原测试通过；
- 不改生产行为。

### T1：建立 VoiceCorrectionCore

任务：

- 创建本地 Package 或纯 Core 模块；
- 定义 domain types 和 protocol；
- strict concurrency；
- Core 不依赖 AppKit / SwiftData / ASR SDK。

验收：

- `swift test` 通过；
- Core 可独立编译；
- `Sendable` 检查通过；
- 无 provider-specific import；
- domain validation 单元测试通过。

### T2：Rule Store

任务：

- Store protocol；
- in-memory test store；
- SQLite adapter；
- snapshot；
- destructive migration：drop old `glossary_terms` and `replacement_rules` data / tables as approved；
- unique rule key。

验收：

- CRUD 测试；
- duplicate idempotent；
- migration 测试；
- DB error 返回旧 snapshot / 空 snapshot；
- matcher 不直接访问 DB。

### T3：V1 Matcher

任务：

- exact；
- boundary；
- substring；
- 所有 match 基于 rawText；
- 输出 spans。

验收：

- Boundary 单元测试全过；
- 不做级联；
- Unicode case 全过；
- disabled / scope / mode 生效；
- 测试覆盖所有 policy。

### T4：Conflict Resolver 和 Replacement

任务：

- 确定性排序；
- 重叠消解；
- 末尾向前替换；
- applied event。

验收：

- overlap / cascade fixture 全过；
- 同一输入重复 1,000 次输出一致；
- replacement 不参与同轮再次匹配；
- raw 永不改变。

### T5：统一 ASR 后处理接入

任务：

- 接 final ASR result；
- provider-agnostic；
- command bypass；
- fail open；
- off-main processing。

验收：

- Mock provider matrix 测试；
- 任一 provider 不需支持 prompt；
- correction failure 时插入 raw；
- interim 不触发；
- HUD 无新增闪烁状态。

### T6：安全与审计

任务：

- secure field guard；
- replacement event；
- OSLog privacy；
- 无 raw production logging；
- kill switch。

验收：

- secure case 全部 bypass；
- 日志测试不包含 raw sentence；
- feature off 时 bit-for-bit 原行为；
- shadow 不修改文本。

### T7：Benchmark Harness

任务：

- fixture schema；
- 首版 100 条中英文 correction cases；
- targeted learning tests；
- 扩展到 500 correction cases / 100 learning cases 的数据目录和命令预留；
- metrics；
- JSON / Markdown report；
- baseline gate；
- JiWER cross-check。

验收：

- PR 可一条命令运行；
- 使用 production engine；
- supported set precision / recall 100%；
- false replacement / regression 为 0；
- CER/WER 不退化；
- baseline comparison 有单元测试；
- 报告包含失败 case。

### T8：Observation Provider

任务：

- 抽象 focused text observation；
- AX adapter；
- fake adapter；
- fake clock；
- 2 / 5 / 10 poll；
- cancellation。

验收：

- 不需要真实 Accessibility 权限即可跑单测；
- focus change 取消；
- secure field 取消；
- text 不可读时取消；
- 不影响插入主链路。

### T9：High-confidence Learning

任务：

- changed range；
- inserted range；
- token expansion；
- conservative extraction；
- candidate rule；
- applied-span overlap guard。

验收：

- targeted learning tests 全过；
- 100 learning fixtures 作为扩展门槛；
- supported substitution 全提取；
- rewrite / insert / delete / ambiguity 全拒绝；
- 一次修改不会直接生成 global active rule。

### T10：Lifecycle 与负反馈

任务：

- candidate / trusted / active；
- observedCount；
- revertedCount；
- suspend；
- decay；
- model fingerprint。

验收：

- state transition 单测；
- 用户改回后 confidence 降低；
- 两次改回 suspend；
- 不产生 A→B→C 反馈链。

### T11：完整易错词 Tab UI

任务：

- 开关；
- Shadow；
- auto learning；
- auto learning applies immediately；
- active / candidate 列表；
- 设置页开关：启用、Shadow、自动学习、自动学习直接生效；
- tab 内学习反馈：badge、最近学习事件条、规则标记；
- disable；
- delete；
- clear all。

验收：

- UI 完整实现，不是临时或半成品设置页；
- 无弹窗打扰；
- 自动学习事件在 `易错词` tab 内显示 badge / 最近学习事件条；
- 用户可撤销；
- 删除后 snapshot 更新；
- UI 不阻塞主线程；
- 符合项目现有 SwiftUI / macOS 视觉风格。

### T12：轻 E2E 与文档

任务：

- 两个自动 E2E；
- 人工 smoke checklist；
- architecture doc；
- benchmark usage；
- privacy doc；
- rollback doc。

验收：

- 自动 E2E 稳定；
- smoke checklist 完成；
- CI 命令文档可复制；
- feature flag rollback 验证；
- 所有原有功能 regression tests 通过。

---

## 21. 第一阶段 Definition of Done

必须全部满足：

- [ ] 所有 ASR 共享统一 correction 出口；
- [ ] 不要求 Provider 支持 prompt；
- [ ] raw / final 分离；
- [ ] command 默认 bypass；
- [ ] exact / boundary / substring 完成；
- [ ] 不级联；
- [ ] overlap 确定性；
- [ ] secure field bypass；
- [ ] failure fail-open；
- [ ] auto learning 保守；
- [ ] candidate 生命周期；
- [ ] negative feedback；
- [ ] Shadow Mode；
- [ ] 首版 100 条中英文 correction fixtures；
- [ ] targeted learning tests；
- [ ] 500 correction fixtures / 100 learning fixtures 扩展门槛已记录；
- [ ] Precision = 100%；
- [ ] Supported Recall = 100%；
- [ ] False Replacement = 0；
- [ ] Regression = 0；
- [ ] CER / WER 不退化；
- [ ] Benchmark PR gate；
- [ ] 单元测试为主；
- [ ] 只有两条自动 E2E；
- [ ] TypeWhisper GPL 代码若被复制或改写，已完成 GPLv3 模块化引入、来源标注、许可证文本和修改说明；
- [ ] README / architecture / rollback 文档齐全。

---

## 22. Phase 2 进入条件

满足任一条件：

- active alias > 1,000；
- 5,000 rule P95 超标；
- 线性 matcher 占用明显；
- top-K prompt 有明确数据收益；
- 已积累真实 Shadow corpus。

Phase 2 内容：

1. Aho-Corasick matcher adapter；
2. 与 Linear matcher 双跑对比；
3. 结果必须 bit-for-bit 相同；
4. top-K term selector；
5. Provider budget adapter；
6. A/B/C/D Benchmark：
   - ASR only；
   - ASR + prompt；
   - ASR + correction；
   - ASR + prompt + correction。

Aho 上线验收：

- 所有 V1 fixture 结果完全相同；
- 10,000 alias 性能显著优于 linear；
- Unicode range 无差异；
- memory 在预算内；
- 可一键回退 Linear matcher。

---

## 23. Phase 3 进入条件

必须先有：

- 高 Precision 的 exact correction；
- 足够多真实 fuzzy 失败样本；
- hard-negative corpus；
- feature flag；
- 独立 fuzzy Benchmark。

Phase 3：

- SymSpell / edit-distance candidate；
- English technical terms only；
- high threshold；
- app / project scope；
- 禁止中文短词 fuzzy；
- fuzzy false replacement 必须接近 0。

---

## 24. 给 Codex 的执行要求

Codex 执行时必须：

1. 先完成 T0，不先写算法；
2. 复用现有项目架构和命名；
3. 可以按任务逐个验证，但最终提交方式按用户要求收敛，不强制每个任务独立 commit；
4. 提交前必须包含对应测试和 Benchmark 结果；
5. 不修改无关 HUD / Command 行为；
6. 不新增网络请求；
7. 不保存完整 production transcript；
8. 若复制或改写 TypeWhisper GPL 源码，必须走 GPLv3 模块化引入流程；
9. Benchmark 使用生产 engine；
10. 任何无法确认的 Accessibility 行为，默认不学习；
11. 任何 correction 异常，返回 rawText；
12. 不在第一期添加 fuzzy 或 Aho；
13. 不在第一期要求 Provider prompt 支持；
14. correction / auto learning 默认开启，Shadow / provider bias / fuzzy 默认关闭；
15. 每个 PR 附 Benchmark diff。

---

## 25. 最终结论

第一期最稳方案是：

```text
多个 ASR
→ 统一 final transcript
→ TypeWhisper 思路的确定性后处理
→ 本地 app-scoped 个人 correction
→ 保守自动学习
→ Benchmark 强门禁
→ Shadow rollout
```

开源利用策略：

```text
TypeWhisper
→ 可借鉴完整流程、文件分层和测试思路
→ 也可在 GPLv3 履约前提下模块化复制或改写必要源码

Aho-Corasick-Swift
→ Phase 2 可直接依赖或 fork
→ 第一阶段由 Benchmark 决定是否需要

FlashText
→ 借鉴 target / aliases 数据模型

SymSpell / strsim
→ Phase 3 fuzzy 参考

OpenBench
→ 借鉴 keyword metric 和 benchmark 报告

JiWER
→ CI 中交叉验证 WER / CER
```

第一阶段的成功标准不是“它看起来更智能”，而是：

> 对明确规则 100% 生效；对 hard-negative 0 误伤；整体 CER/WER 不退化；任何 ASR 都能共用；功能失败不影响原始听写。
