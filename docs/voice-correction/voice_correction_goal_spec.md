# 易错词 Phase 1 Goal Spec

## 目标

在 VoxFlow 中完成新版一级 `易错词` tab 与本地确定性语音纠错系统第一期，实现：

- 左侧主导航新增一级 tab：`易错词`；
- 删除旧 `词汇表 -> 易错词`、旧 `词汇表 -> 文本替换` 和对应旧表数据；
- 引入 `VoxFlowVoiceCorrection` 模块；
- 在普通 `.dictation` final transcript 的 LLM 后、文本插入前运行易错词 correction；
- 借鉴 TypeWhisper focused text observation 思路完成自动学习；
- 自动学习默认开启，自动学习直接生效默认开启；
- 完成首版 100 条中英文 correction benchmark，并记录未通过或未纳入 case 的原因与方向；
- 完成单元测试、针对性测试和最终完整验收。

## 主执行入口

AI 必须严格按以下任务清单执行：

```text
docs/voice-correction/voice_correction_phase1_tasks.md
```

执行规则：

- 必须按 `T0 -> T13` 顺序推进；
- 每完成一个 checkbox，就在该 Markdown 文件中勾选；
- 不得跳过任务；
- 不得把未完成项标记为完成；
- 如果发现任务拆解与代码现实冲突，先更新任务清单和相关方案文档，再继续实现；
- `voice_correction_phase1_tasks.md` 是唯一任务拆解入口，不使用旧 YAML 或临时口头任务表。

## 提交策略

不要一步一提交。

推荐提交边界：

- 完成一组可独立验证的相关任务后再提交；
- 每次提交应覆盖一个清晰阶段，例如：
  - GPLv3 模块骨架与合规文件；
  - 旧入口/旧表删除；
  - core matcher；
  - SQLite store；
  - pipeline 接入；
  - focused observation 与学习；
  - benchmark；
  - UI；
  - final polish / docs；
- 不要为每个 checkbox 单独提交；
- 不要把未验证的大量改动长期堆到最后才第一次测试。

如果需要提交，提交信息必须遵循仓库 `AGENTS.md`：

- 使用 Conventional Commits；
- 中文提交说明；
- 添加 `Co-authored-by: OpenAI Codex <codex@openai.com>`；
- 提交前 review 本次提交全部变更。

## 测试策略

### 开发过程中的测试

每个任务或小阶段必须写单元测试，但不要每完成一个 checkbox 就全量跑测试。

执行方式：

- 写核心逻辑前先写失败测试；
- 完成小块实现后运行对应 targeted tests；
- targeted tests 优先使用 `swift test --filter ...`；
- 独立 package 内逻辑优先运行：

```bash
swift test --package-path Packages/VoxFlowVoiceCorrectionKit --filter <TestName>
```

- App 集成层优先运行：

```bash
swift test --filter <TestName>
```

不要在每个小 checkbox 后运行：

```bash
swift test
make debug
make build
```

这些全量门禁只在阶段边界或最终验收时运行。

### 必须覆盖的单元测试

第一期至少覆盖：

- rule validation；
- exact / boundary / substring matching；
- Unicode / CJK / punctuation boundary；
- conflict resolve；
- non-cascading replacement；
- ContextGate；
- SQLite repository CRUD；
- destructive migration / old table drop；
- snapshot failure fallback；
- LLM 成功后 correction；
- LLM 失败后 correction；
- command / translation bypass；
- focused text observation fake；
- 2 / 5 / 10 秒 polling；
- high-confidence learning extraction；
- rewrite / insertion / deletion / ambiguity rejection；
- auto-learning-immediate on/off；
- suppression list；
- negative feedback；
- UI view model；
- navigation route；
- benchmark metrics。

## Benchmark 策略

首版必须跑通 100 条中英文 correction fixtures。

Benchmark 命令：

```bash
swift run --package-path Packages/VoxFlowVoiceCorrectionKit VoxFlowVoiceCorrectionBench \
  --fixtures Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Fixtures \
  --baseline Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Baselines/phase1-baseline.json \
  --output .build/voice-correction-benchmark
```

JiWER 交叉检查：

```bash
uv run tools/voice_correction_jiwer_check.py \
  --report .build/voice-correction-benchmark/report.json
```

首版阻塞门槛：

- 100 条首版 fixtures 全部通过；
- `CorrectionPrecision = 1.000`；
- `SupportedCorrectionRecall = 1.000`；
- `FalseReplacementRate = 0`；
- `RegressionRate = 0`；
- `CERAfter <= CERBefore`；
- `WERAfter <= WERBefore`。

未通过或未纳入的 case 必须记录：

- case id；
- raw；
- expected；
- actual；
- 失败原因；
- 分类；
- 后续方向；
- 是否阻塞本期。

最终汇报必须回答：

- 100 条首版 fixtures 是否全过；
- 剩余未过或未纳入 case 是哪些；
- 为什么没过；
- 下一步方向是什么。

## 最终完整验收

全部任务完成后，再进行完整验收。最终验收必须包含：

```bash
swift test
make debug
make build
swift run --package-path Packages/VoxFlowVoiceCorrectionKit VoxFlowVoiceCorrectionBench \
  --fixtures Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Fixtures \
  --baseline Packages/VoxFlowVoiceCorrectionKit/Benchmarks/Baselines/phase1-baseline.json \
  --output .build/voice-correction-benchmark
uv run tools/voice_correction_jiwer_check.py \
  --report .build/voice-correction-benchmark/report.json
```

如果全量命令失败，最终汇报必须区分：

- 与本需求相关的失败；
- 当前工作树或环境中的既有失败；
- 未验证项；
- 替代验证方式。

不能只说“没跑”或“失败了”，必须写具体命令、错误文件/行号、影响判断。

## 不做事项

第一期明确不做：

- 不接 Agent Compose / 帮我说；
- 不接文件转写；
- 不接 translation 输出；
- 不处理 streaming interim transcript；
- 不做 fuzzy；
- 不引入 Aho-Corasick runtime；
- 不引入 Rust FFI；
- 不做 regex replacement；
- 不保留旧文本替换系统；
- 不迁移旧数据；
- 不为每个 ASR provider 单独做 hotword / prompt 接口。

## 完成定义

只有同时满足以下条件，才能声明 Phase 1 完成：

- `voice_correction_phase1_tasks.md` 所有必做 checkbox 已完成；
- 旧 UI 入口已删除；
- 旧表数据已 destructive drop；
- 新 `易错词` 一级 tab 可用；
- 普通 `.dictation` final transcript 会在 LLM 后运行 correction；
- LLM 失败时仍运行 correction；
- Agent Compose 不接入；
- 自动学习 focused observation 可用；
- 自动学习直接生效默认开启，可关闭为 candidate-only；
- 100 条 benchmark fixtures 全过；
- 未通过或未纳入的扩展 case 已记录；
- 单元测试和 targeted tests 已覆盖核心行为；
- 最终完整验收已运行并记录结果。
