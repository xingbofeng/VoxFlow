# Phase 2a OCR Context Boost 方案

## 目标

把当前目标应用的可见窗口作为短时上下文，用于 LLM 听写纠错。该功能截取当前目标窗口、运行 OCR、抽取少量临时关键词 / 命名实体候选，并只把这些候选注入现有的 LLM refinement prompt。

本方案是 Phase 1 确定性语音纠错与完整 Phase 2 性能 / provider bias 工作之间的过渡桥梁。

## 不做的事

- 本期不做可见 UI。
- 不做全屏 OCR。
- 不做持续后台录屏。
- 不接 screenpipe。
- 不接 Aho-Corasick。
- 不改 `VoiceCorrectionEngine`。
- 不做 fuzzy matching。
- 不从 OCR 写入永久词表或纠错规则。
- 不关闭现有 2s / 5s / 10s focused-text observation 学习流程。

## 运行流程

```text
开始听写
 立即启动 ASR
 并行截取当前目标 app 窗口 OCR
 ASR final
 DefaultTextProcessingPipeline
   → LLM refinement 前短暂等待 OCR 上下文
   → 把 Top-K 临时 hotword 注入 system prompt
   → LLM refinement
   → 现有 VoiceCorrectionProcessor / VoiceCorrectionEngine
 输出插入
 现有 CorrectionObservationCoordinator 可从后续用户编辑中学习
```

OCR 路径必须 fail-open。权限拒绝、无目标窗口、OCR 为空、超时或 extractor 失败时，除了 trace 诊断外，听写行为应保持不变。

## 当前代码锚点

- 现有手动截图 OCR：`Sources/VoxFlowApp/FeatureBridges/ScreenshotOCRService.swift`
- 现有当前窗口截取 / Vision OCR 参考：`Sources/VoxFlowApp/FeatureBridges/ContextPipeline.swift`
- 目标 app 元数据：`Sources/VoxFlowApp/AppKitAdapters/DictationTargetProvider.swift`
- 纠错前的 LLM pipeline：`Sources/VoxFlowApp/TextProcessingBridges/TextProcessingPipeline.swift`
- Prompt 构造：`Sources/VoxFlowApp/TextProcessingBridges/PromptBuilder.swift`
- Observation 学习：`Sources/VoxFlowApp/VoiceCorrection/Observation/CorrectionObservationCoordinator.swift`
- 运行时装配：`Sources/VoxFlowApp/App/AppRuntime.swift`

## Context Boost Package

创建一个轻量的 Foundation-first package：

```text
Packages/VoxFlowContextBoostKit/
├── Package.swift
├── Sources/VoxFlowContextBoost/
│   ├── TemporaryHotword.swift
│   ├── OCRContextSnapshot.swift
│   ├── HotwordExtractor.swift
│   ├── HotwordRanker.swift
│   ├── TemporaryHotwordStore.swift
│   └── ContextBoostPromptSectionBuilder.swift
└── Tests/VoxFlowContextBoostTests/
    ├── HotwordExtractorTests.swift
    ├── HotwordRankerTests.swift
    ├── TemporaryHotwordStoreTests.swift
    └── ContextBoostPromptSectionBuilderTests.swift
```

该 package 不得依赖 AppKit、SwiftUI、ScreenCaptureKit、Vision 或 VoxFlowApp 类型。App 层 adapter 负责把 `DictationTarget` 和 OCR 输出转换成 package 级别 value type。

## 数据模型

```swift
public struct TemporaryHotword: Sendable, Codable, Hashable {
    public let text: String
    public let normalizedText: String
    public let score: Double
    public let source: HotwordSource
    public let evidence: [HotwordEvidence]
    public let expiresAt: Date
}

public enum HotwordSource: String, Sendable, Codable {
    case ocrKeyphrase
    case ocrNamedEntity
    case ocrShape
    case activeApp
    case windowTitle
}

public struct HotwordEvidence: Sendable, Codable, Hashable {
    public let reason: String
    public let weight: Double
}

public struct OCRContextSnapshot: Sendable, Codable, Equatable {
    public let bundleID: String?
    public let appName: String?
    public let windowTitle: String?
    public let capturedAt: Date
    public let hotwords: [TemporaryHotword]
}
```

不要在 `TemporaryHotwordStore` 或持久化 trace 中保存截图或完整 OCR 文本。

## Hotword 抽取策略

“hotword”指当前窗口的关键词、关键短语、命名实体或专用 token 候选，不限于技术 token。

### 开源 / 平台参考

1. RAKE
   - 参考：`csurfer/rake-nltk`、`aneesha/RAKE`。
   - 许可证背景：常见实现是 MIT，但 Phase 2a 在 Swift 中重写算法，不复制 Python 代码。
   - 借鉴的算法形态：
     - 用停用词和标点把文本拆成候选短语；
     - 统计词频；
     - 统计 word degree / 局部共现；
     - 短语得分为组成词得分之和；
     - 保留短短语，通常 1-4 个 token。
   - 不照搬 NLTK 分词、Python API、仓库布局或停用词文件。

2. Apple NaturalLanguage
   - 在可用处使用 `NaturalLanguage.NLTagger` 的 `.nameType`。
   - 人名、地名、机构名等命名实体作为排序证据，不是硬依赖。
   - 不支持的语言或打标失败必须 fail open。

3. Shape-based 候选
   - 作为小型确定性规则在本地实现。
   - 补充 RAKE / NLTagger，覆盖自然语言 extractor 遗漏的标识符。

Phase 2a 不使用 KeyBERT、YAKE 或 TextRank。它们比该热路径需要的重，且会引入可避免的依赖 / 许可 / 模型复杂度。

### 候选来源

1. RAKE 风格关键短语：
   - 产品名；
   - 文档标题；
   - 聊天名；
   - issue 或错误短语；
   - 短主题短语。

2. 命名实体：
   - 人名；
   - 机构名；
   - 地名；
   - app 可见的专有名称。

3. Shape-based 候选：
   - `Qwen3-ASR`；
   - `WhisperKit`；
   - `Package.swift`；
   - `CorrectionContext`；
   - `VNRecognizeTextRequest`；
   - `com.apple.Terminal`；
   - 全大写缩写；
   - 版本号样字符串；
   - 连字符 / 下划线 token。

4. 中文短语候选：
   - 按行和标点拆分后保留 2-8 字短短语；
   - 对通用 UI 标签和长自然句降权；
   - Phase 2a 不实现复杂中文分词。

### 限制

- 抽取前 OCR 文本截断：最多 8,000 字符或 80 行。
- 排序前最多生成 200 个候选。
- Prompt Top-K 默认：8。
- Prompt Top-K 硬上限：12。
- TTL 默认：120 秒。

## 排序

用加法证据给候选打分：

- RAKE 得分；
- 命名实体标签；
- 专用 shape；
- 重复出现；
- 长度合理；
- app 或窗口标题匹配；
- 可用时 OCR 行显著度；
- 对通用 UI 词、长句、明显按钮和菜单标签做惩罚。

首次实现可用固定权重。在调参前必须确定性并由测试覆盖。

## Prompt 注入

只有当 Top-K 非空、且 LLM refinement 启用并配置时，才添加 prompt 段。

Prompt 段形态：

```text
临时屏幕上下文词，仅本次有效，不代表用户长期偏好：
- Qwen3-ASR
- Hyperframe
- speech-swift
- WhisperKit

这些词只用于判断专有名词、上下文关键词和可能被听错的短语。
不要添加上下文里有但用户没有说的信息。
不要润色、不要扩写、不要总结。
不确定时保留 ASR 原文。
```

Prompt 永远不能包含完整 OCR 文本。

## Trace

新增：

```swift
struct ContextBoostTrace: Equatable, Codable, Sendable {
    let appName: String?
    let bundleID: String?
    let hotwords: [String]
    let source: String
    let ttlSeconds: Int
    let appliedToLLMPrompt: Bool
    let failureReason: String?
}
```

`TextProcessingTrace.safeForPersistence()` 只保留脱敏后的 context boost 元数据。不得持久化截图、OCR 文本或 app 图标数据。

## 学习策略

不要因为使用了 OCR 上下文就关闭现有 observation 学习。

原因：`CorrectionObservationCoordinator` 从插入后的用户编辑中学习，不是直接从系统输出学习。OCR 上下文只是临时 LLM 证据。Phase 2a 保持当前保守 extractor 和 applied-correction 范围保护不变。

如果后续证据表明 OCR 上下文 LLM 输出导致错误学习，在后续任务中加上对 LLM 修改范围的保护。

## 性能策略

OCR 上下文不得延迟录音开始。

实现时序：

```text
按下快捷键
 立即开始录音
 并行启动当前窗口 OCR
 ASR final 到达
 LLM 前最多等 OCR 上下文 500 ms
 超时无上下文 → 本次听写不做 context boost
```

性能护栏：

- 录音开始前不做同步 OCR；
- LLM 前 OCR 超时：500 ms；
- 8,000 字符 OCR 文本上 extractor + ranker P95 低于 20 ms；
- Top-K prompt 数量上限 12；
- 权限拒绝、无窗口、OCR 为空、超时或 OCR 错误时 fail-open；
- 安全前提下，同一 bundle / window scope 的未过期 snapshot 可复用。

## 任务

### Task 1: Roadmap 文档

文件：

- 修改：`docs/voice-correction/implementation-reading-notes.md`
- 修改：`docs/voice-correction/voice_correction_technical_spec.md`

步骤：

1. 在 Phase 1 和完整 Phase 2 之间加入 Phase 2a。
2. 记录 Phase 2a 仅做当前窗口 OCR context boost。
3. Aho-Corasick 保留到完整 Phase 2。
4. fuzzy 保留到 Phase 3。

验收：

- Roadmap 明确写 Phase 2a 不含 Aho-Corasick 或 fuzzy。
- Phase 2 进入条件保持不变。

### Task 2: ContextBoostKit 骨架

文件：

- 新建：`Packages/VoxFlowContextBoostKit/Package.swift`
- 新建：`Packages/VoxFlowContextBoostKit/Sources/VoxFlowContextBoost/TemporaryHotword.swift`
- 新建：`Packages/VoxFlowContextBoostKit/Sources/VoxFlowContextBoost/OCRContextSnapshot.swift`
- 新建：`Packages/VoxFlowContextBoostKit/Tests/VoxFlowContextBoostTests/TemporaryHotwordStoreTests.swift`

步骤：

1. 新增 package 和公开 value type。
2. 新增 actor 支持的内存 TTL store。
3. 新增 put、topK、purgeExpired 测试。

验收：

- `swift test --package-path Packages/VoxFlowContextBoostKit` 通过。
- Store 永不暴露过期 hotword。

### Task 3: Hotword Extractor

文件：

- 新建：`Packages/VoxFlowContextBoostKit/Sources/VoxFlowContextBoost/HotwordExtractor.swift`
- 测试：`Packages/VoxFlowContextBoostKit/Tests/VoxFlowContextBoostTests/HotwordExtractorTests.swift`

步骤：

1. 写 RAKE 风格短语抽取的失败测试。
2. 写可注入 tagger 结果的命名实体证据失败测试。
3. 写 shape-based token 的失败测试。
4. 实现确定性抽取，带候选和输入长度上限。

验收：

- 能从聊天 / 文档文本中抽出非技术短语。
- 能抽出技术标识符。
- 过滤常见 UI 标签和长自然句。
- 不依赖 AppKit、Vision 或 ScreenCaptureKit。

### Task 4: Hotword Ranker

文件：

- 新建：`Packages/VoxFlowContextBoostKit/Sources/VoxFlowContextBoost/HotwordRanker.swift`
- 测试：`Packages/VoxFlowContextBoostKit/Tests/VoxFlowContextBoostTests/HotwordRankerTests.swift`

步骤：

1. 新增确定性排序测试。
2. 新增重复 normalizedText 合并测试。
3. 新增 Top-K 默认 8 和硬上限 12 的测试。
4. 实现加法打分和稳定 tiebreak。

验收：

- 多次运行排序结果一致。
- 重复候选合并为一个 hotword，证据合并。

### Task 5: Prompt Section Builder

文件：

- 新建：`Packages/VoxFlowContextBoostKit/Sources/VoxFlowContextBoost/ContextBoostPromptSectionBuilder.swift`
- 测试：`Packages/VoxFlowContextBoostKit/Tests/VoxFlowContextBoostTests/ContextBoostPromptSectionBuilderTests.swift`

步骤：

1. 新增测试证明 Top-K hotword 出现。
2. 新增测试证明 OCR 原文不会出现。
3. 实现中文护栏 prompt 段。

验收：

- Prompt 包含临时上下文约束。
- Prompt 只包含选中的 hotword 字符串，不含 OCR 原文。

### Task 6: 当前窗口 OCR Adapter

文件：

- 修改或拆分自：`Sources/VoxFlowApp/FeatureBridges/ContextPipeline.swift`
- 若拆分则新建：`Sources/VoxFlowApp/FeatureBridges/CurrentWindowOCRContextProvider.swift`
- 测试：`Tests/VoxFlowAppTests/FeatureBridges/CurrentWindowOCRContextProviderTests.swift`

步骤：

1. 从 `SystemScreenshotProvider` 抽出可复用的当前窗口截图 OCR 逻辑。
2. 新增接受 `DictationTarget?` 的 provider。
3. 返回 OCR 文本和 app 元数据给 ContextBoostKit 处理。
4. 新增 fake provider 测试：权限拒绝、无窗口、OCR 为空、OCR 成功。

验收：

- 只截取目标 app 窗口。
- 不使用交互式截图。
- 热路径不请求权限。
- fail-open。

### Task 7: TextProcessingPipeline 集成

文件：

- 修改：`Package.swift`
- 修改：`Sources/VoxFlowApp/TextProcessingBridges/TextProcessingPipeline.swift`
- 修改：`Sources/VoxFlowApp/TextProcessingBridges/PromptBuilder.swift`
- 测试：`Tests/VoxFlowAppTests/TextProcessingBridges/TextProcessingPipelineTests.swift`
- 测试：`Tests/VoxFlowAppTests/TextProcessingBridges/PromptBuilderTests.swift`

步骤：

1. 新增 `VoxFlowContextBoostKit` package 依赖。
2. 把可选 context boost reader 注入 `DefaultTextProcessingPipeline`。
3. LLM refinement 前读取 `target` 的 Top-K。
4. 用临时 hotword 构造 prompt。
5. LLM 禁用或无上下文时保留旧行为。

验收：

- 现有 pipeline 测试仍通过。
- 新的 fake LLM 测试证明存在 OCR hotword 时 prompt 改变。
- LLM 禁用路径不使用 OCR 上下文。

### Task 8: Trace 集成

文件：

- 修改：`Sources/VoxFlowApp/TextProcessingBridges/TextProcessingPipeline.swift`
- 修改：`Sources/VoxFlowApp/TextProcessingBridges/LLMDiagnosticCapture.swift`
- 测试：`Tests/VoxFlowAppTests/TextProcessingBridges/RepositoryBackedLLMRefinerTests.swift`
- 测试：`Tests/VoxFlowAppTests/TextProcessingBridges/LLMDiagnosticCaptureTests.swift`

步骤：

1. 新增 `ContextBoostTrace`。
2. 挂到 `TextProcessingTrace`。
3. 更新 safe persistence 和 diagnostic 脱敏。
4. 新增测试证明 OCR 原文不存在。

验收：

- 持久化 trace 只含 Top-K 和 app 元数据。
- 不编码截图、图标或 OCR 原文。

### Task 9: 运行时装配

文件：

- 修改：`Sources/VoxFlowApp/App/AppRuntime.swift`

步骤：

1. 创建 shared context boost store。
2. 把当前窗口 OCR context provider 接入听写流程。
3. 把 context boost reader 接入 `DefaultTextProcessingPipeline`。
4. 保持现有手动截图 OCR 服务不变。

验收：

- App runtime 构造不变，手动截图 OCR 行为不变。
- Context boost 依赖可选，fail-open。

### Task 10: 学习回归测试

文件：

- 测试：`Tests/VoxFlowAppTests/Dictation/DictationOrchestratorTests.swift`
- 测试：`Tests/VoxFlowAppTests/FeatureBridges/VoiceTaskCoordinatorTests.swift`

步骤：

1. 新增 `processingResult.trace.contextBoost.appliedToLLMPrompt == true` 的测试。
2. 验证注入的听写输出仍会安排 correction observation。
3. 验证安全字段仍跳过 observation。

验收：

- OCR 上下文不关闭 2s / 5s / 10s observation 调度。
- 现有安全字段守护不变。

### Task 11: Benchmark 和 Fixture

文件：

- 新建：`Packages/VoxFlowContextBoostKit/Tests/VoxFlowContextBoostTests/HotwordBenchmarkFixtures.swift`
- 如需要，在 `Packages/VoxFlowContextBoostKit/Sources/` 下新建或扩展 benchmark 命令

步骤：

1. 新增 30-50 条 fixture：
   - 聊天名和产品名；
   - 文档标题；
   - 技术标识符；
   - 中英混合短语；
   - hard negative：可见文本不得作为新内容注入。
2. 新增约 8,000 字符的性能 fixture。
3. 在测试或 benchmark 中本地测量 extract + rank P95。

验收：

- Fixture 测试确定性通过。
- 开发硬件上 8,000 字符 OCR 输入的 extract + rank P95 低于 20 ms。
- Benchmark 不依赖真实 OCR 或真实 LLM。

## 最终验收

按顺序运行：

```bash
swift test --package-path Packages/VoxFlowContextBoostKit
swift test
make debug
make build
```

如果无关仓库问题阻塞全量验收，报告具体命令、文件、行号，以及失败是否与 Phase 2a 相关。至少 ContextBoostKit 测试和针对性 VoxFlowApp 测试必须通过，才能声明功能完成。

## 完成定义

- 当前目标 app 窗口 OCR 能产生短时上下文 hotword。
- Top-K hotword 仅在 LLM refinement 启用时注入 LLM prompt。
- 不持久化 OCR 原文，不放入 trace。
- 现有语音纠错顺序保持 LLM 先、确定性纠错后。
- 现有 2s / 5s / 10s observation 学习保持开启。
- 手动截图 OCR 行为不变。
- Aho-Corasick 仍不进入 Phase 2a。
- 所有针对性测试和 package 测试通过。
