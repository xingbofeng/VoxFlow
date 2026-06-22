# 易错词项目决策

## 主导航 UI 位置

易错词管理必须作为左侧主导航里的独立一级 tab 实现，而不是并入 ASR 模型、LLM 模型、通用设置、数据与隐私页面，也不是继续藏在 `词汇表` 的二级分段里。

当前项目主导航由以下位置驱动：

- `Sources/VoxFlowApp/FeatureBridges/NavigationRoute.swift`
  - `NavigationRoute`
  - `NavigationRoute.title`
  - `NavigationRoute.systemImage`
- `Sources/VoxFlowApp/Views/SidebarView.swift`
  - 左侧主导航渲染
- `Sources/VoxFlowApp/Views/MainShellView.swift`
  - route switch 和详情页承载

第一期 UI 实现应新增独立 route，中文标题为：

```text
易错词
```

该 tab 承载：

- 功能开关；
- Shadow Mode 开关；
- 自动学习开关；
- active / candidate 规则列表；
- 禁用、删除、清空规则；
- 新增 / 编辑规则；
- 候选确认 / 忽略 / 暂停；
- 最近修正事件；
- 规则编辑后刷新 RuleSnapshot。

不要把易错词 UI 放进 `LLM 模型`、`ASR 模型` 或 `设置`。易错词是 ASR final transcript 之后的确定性本地后处理能力，不是 LLM 纠错配置，也不是某个 ASR Provider 的模型能力。

这是对当前 `词汇表 -> 易错词 / 文本替换` 功能的升级：旧功能提供 prompt 词条和简单替换，新功能提供本地、可审计、可学习、provider-independent 的语音纠错系统。第一期直接删除旧 `词汇表 -> 易错词` 子功能、旧 `词汇表 -> 文本替换` 子功能和对应旧表数据，不做数据迁移，不保留两套易错词入口，也不保留旧文本替换入口。

已生成的 GPT Image 2 设计稿左侧导航漏画了新增 `易错词` tab；后续设计稿修订和工程实现必须补上，并让它与 `首页 / 词汇表 / 风格 / 文件转写 / 笔记 / 设置 / 帮助` 同级。

## GPLv3 源码策略

当前仓库许可证是 MIT。用户已确认可以按照 TypeWhisper 的 GPLv3 协议履约，并明确倾向：

```text
如果可以按照模块来就按照模块来，复制就复制。
```

因此后续可以选择直接采用 TypeWhisper GPLv3 源码，但必须先把许可影响作为实现任务处理：

- 若直接复制或改写 TypeWhisper 源码，相关源码必须保留 GPLv3 授权信息、copyright 和修改说明；
- 分发时必须提供对应源码；
- 不能继续假定整个组合/派生作品仍保持纯 MIT 分发；
- 在实际引入 GPLv3 源码前，需要明确是整体转 GPLv3，还是通过清晰进程/模块边界隔离 GPLv3 组件。

工程策略：

- 优先把 copied / modified GPLv3 代码集中在独立 `VoxFlowVoiceCorrection` 模块或 package 内；
- 不把 GPLv3 来源代码散落到 App 壳层、UI、ASR Provider 或通用基础设施；
- 模块内必须保留 `COPYING` / `LICENSE.gplv3`、来源文件清单、原始 commit、修改说明；
- 如果该 GPLv3 模块被静态或动态链接进同一个分发 App，仍要按 GPLv3 组合分发风险处理；
- 如果希望主 App 尽量维持 MIT 授权，需要优先评估独立进程 / helper / IPC 边界是否足够清晰。

实现上不再强制“必须重新实现”。当直接复制或改写 TypeWhisper 源码能明显降低风险或工作量时，可以进入 GPLv3 模块化引入流程。

具体源码参考、复制范围、非 V1 开源库边界和合规产物见：

```text
docs/voice-correction/opensource-import-plan.md
```

## 运行时默认值

迁移完成后新版易错词默认开启：

- `correctionEnabled = true`
- `autoLearningEnabled = true`
- `autoLearningAppliesImmediately = true`
- `shadowModeEnabled = false`
- `providerBiasEnabled = false`
- `fuzzyEnabled = false`

默认开启只针对普通 dictation final transcript。Command、translation、streaming interim、secure field、无法确认 focused text 的场景仍然 bypass 或拒绝学习。

新增设置页开关：

- `自动学习并直接生效`：默认开启，用户可以关闭。
- 开启时，高置信 focused text observation 学到的规则直接进入 active。
- 关闭时，自动学习只生成 candidate，需要用户在 `易错词` tab 中确认后生效。
- 手动新增规则始终可以直接 active。

## 处理顺序

第一期纠错顺序按 TypeWhisper 当前实现和 VoxFlow 风险边界确定：

```text
ASR final
→ 现有数字/格式/标点等确定性清洗
→ 可选 LLM refinement
→ 易错词 correction
→ 文本插入
→ 插入后 focused text observation / automatic learning
```

TypeWhisper 的 `PostProcessingPipeline` 将 LLM 放在 priority 300，snippets 放在 500，dictionary / corrections 放在 600；其插件文档也说明 post-processor 的 `input` 是 LLM 后文本。因此 VoxFlow 第一阶段把易错词作为 LLM 后的最后确定性修正层。这样可以修掉 LLM 未修对或重新引入的固定误写，同时避免把用户规则提前送进 LLM 导致不可审计改写。

其他开源参考里，FlashText、JiWER、LanguageTool、OpenAI Evals 都不是“ASR + LLM + dictation correction”运行时管线，不能回答 LLM 前后顺序。第一期顺序以 TypeWhisper 这个最接近的开源 macOS dictation app 为准：LLM 后运行 dictionary / corrections。LLM 失败时，VoxFlow 仍运行易错词：ASR final → LLM 尝试 → 失败则保留当前文本 → 易错词 correction → 插入。

Agent Compose 说明：项目里的 `agentCompose` 即中文 UI 的“帮我说”，它把用户语音当成意图交给 LLM 生成/改写输出，不是普通听写原文插入。第一期易错词不接 Agent Compose。

## Accessibility Observation 阶段

Phase 1 必须实现 Accessibility focused text observation 抽象，否则自动学习不能上线。

这里直接借鉴 TypeWhisper 的学习思路：

1. 插入前捕捉当前 focused text element；
2. 插入后重新捕捉同一个 element，形成 baseline；
3. 按 2 / 5 / 10 秒轮询同一个 element；
4. 只在用户修改了刚插入文本且 diff 高置信时学习规则；
5. `自动学习并直接生效` 开启时进入 active，关闭时进入 candidate。
6. focus 变化、文本不可读、secure field、diff ambiguous 时直接拒绝学习。

实现要求：

- production 使用真实 Accessibility observer；
- 单元测试和 CI 使用 fake observer / fake clock；
- CI 不依赖真实 TextEdit、系统 Accessibility 权限或桌面焦点；
- 自动学习失败必须 fail-open，不影响插入主链路。

## Phase 1 Benchmark 门槛

第一阶段 Benchmark 是硬要求，但首版落地门槛调整为：

- 跑通 100 条中英文纯文本 correction fixtures；
- negative case 数量不少于 positive case；
- 覆盖 exact、boundary、substring、hard negative、overlap / cascade、punctuation、mode bypass；
- 使用 production correction engine；
- `CorrectionPrecision = 1.000`
- `SupportedCorrectionRecall = 1.000`
- `FalseReplacementRate = 0`
- `RegressionRate = 0`
- `CERAfter <= CERBefore`
- `WERAfter <= WERBefore`

PR 阻塞范围包含这 100 条首版门槛和 targeted learning tests。原方案中的 500 correction cases + 100 learning cases 保留为扩展门槛，不作为第一期首个提交的阻塞条件。未通过或未纳入的剩余 case 必须写进 benchmark report：包含 `case id`、失败原因、归类、后续方向、是否阻塞本期。

第一期最终答复必须回答：

- 100 条首版 fixtures 是否全过；
- 剩余未过或未纳入 case 是哪些；
- 为什么没过；
- 下一步方向是什么。

最终 Benchmark 形态：

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

运行命令：

```bash
swift run --package-path Packages/VoxFlowVoiceCorrectionKit VoxFlowVoiceCorrectionBench \
  --fixtures Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Fixtures \
  --baseline Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Baselines/phase1-baseline.json \
  --output .build/voice-correction-benchmark
```

输出：

- `.build/voice-correction-benchmark/report.json`
- `.build/voice-correction-benchmark/report.md`
- 失败 case 列表，包含 `id`、`raw`、`expected`、`actual`、expected events、actual events、命中的 rule ids；
- 未通过 / 未纳入 case 列表，包含原因和后续方向；
- metrics：sentence exact match、precision、supported recall、false replacement、regression、CER/WER before/after、P50/P95/P99 latency。

## 学习反馈

自动学习反馈不弹系统级打断提示。

第一期反馈位置：

- `易错词` tab 侧边栏或 tab 标题显示 candidate / newly learned badge；
- `易错词` tab 顶部显示最近学习事件条，例如“已学习 2 条易错词”，提供撤销入口；
- 规则列表中新增或自动生效的规则用 `新` / `自动学习` 标记；
- 如果 `自动学习并直接生效` 关闭，candidate 出现在候选列表中等待确认。

不在录音 HUD、系统通知、浮窗里频繁弹提示，避免打断连续输入。

Benchmark 借鉴的开源做法：

- JiWER：使用 WER / CER / edit-distance 类指标，并输出 substitution / insertion / deletion error counts；VoxFlow 用它做 Python cross-check 和错误分布报告。
- OpenAI Evals：数据和评测逻辑分离，样本用 JSONL，运行参数可复现；VoxFlow 使用固定 fixtures、rules、baseline 和输出目录。
- LanguageTool：每条规则有 incorrect example 和 correct example / antipattern，用自动测试证明“该命中”和“不该命中”；VoxFlow 每条高风险 alias 必须有正例和 hard-negative。
- FlashText：关键词替换类库会单独看替换行为与性能；VoxFlow 把行为 gate 和 P50 / P95 / P99 latency 都放进 bench report。

## Phase 1 实现笔记

当前实现与方案保持一致，补充以下落地细节：

- 新版 `易错词` 已作为 `NavigationRoute.voiceCorrection` 一级 tab 接入，左侧导航与 `首页 / 词汇表 / 风格 / 文件转写 / 笔记 / 设置 / 帮助` 同级。
- 旧 `词汇表 -> 易错词`、旧 `词汇表 -> 文本替换` 和旧表数据走 destructive migration 删除，不做迁移。
- runtime settings key 使用 `settings.voiceCorrection.*` 命名；默认值为启用、自动学习、自动学习直接生效均开启，Shadow Mode 关闭。
- Shadow Mode 当前实现为“计算会命中的 correction events，但返回原文本作为 final text”，不修改用户输入。
- Benchmark 首版落地为 100 条 correction fixtures：positive 50，negative 50，覆盖 exact、boundary、substring、hard negative、overlap、cascade prevention、punctuation、mode bypass、app scope、secure field。
- 当前 benchmark 结果：100/100 passed，precision 1.0，supported recall 1.0，false replacement 0，regression 0，CER 0.12367270455965022 -> 0.0，WER 0.33134328358208953 -> 0.0。
- JiWER cross-check 已通过；Swift bench 的 CER 口径按 JiWER 默认空白归一化处理。
- 未纳入项写入 report：500 correction + 100 learning 扩展门槛、真实 Accessibility 权限观测 benchmark、Provider bias / OCR / TTL context benchmark。
