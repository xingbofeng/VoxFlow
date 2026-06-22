# 易错词 Phase 1 集成地图

## 基线状态

- Worktree：`/Users/counter/.config/superpowers/worktrees/voice-input-method-mac/voice-correction`
- 分支：`codex/voice-correction`
- `swift test`：通过，`1208 tests, 11 skipped, 0 failures`。运行期间出现 CoreData `Failed to create NSXPCConnection` 环境日志，但未造成测试失败。
- `make debug`：通过，`swift build -c debug -Xswiftc -warnings-as-errors` 构建成功。

## ASR Final -> LLM -> Correction -> Insertion 落点

当前普通听写主链路落在：

- `Sources/VoxFlowApp/FeatureBridges/VoiceTaskCoordinator.swift`
  - `VoiceTaskCoordinator.processAndDeliver(kind:)`
  - 从 `task.rawTranscript` 读取 ASR final 文本；
  - 调用 `textPipeline.process(rawText, target: originalTarget)`；
  - 将 `processingResult.finalText` 写入 `voice_tasks.final_text`；
  - 调用 `outputService.deliver(text:mode:target:originalTarget:)` 完成注入或复制。

当前文本处理落在：

- `Sources/VoxFlowApp/TextProcessingBridges/TextProcessingPipeline.swift`
  - `DefaultTextProcessingPipeline.process(_:target:onRefinedTextUpdate:)`
  - 现有顺序是：

```text
rawText
-> applyReplacementRules(stage: .beforeLLM)
-> optional LLM refinement
-> applyReplacementRules(stage: .afterLLM)
-> TextProcessingResult.finalText
```

Phase 1 要改成：

```text
rawText
-> existing deterministic cleanup, if any
-> optional LLM refinement
-> VoxFlowVoiceCorrection
-> TextProcessingResult.finalText
-> OutputService / TextInsertion
```

LLM 失败时，`DefaultTextProcessingPipeline` 当前已经保留 `text` 并返回 fallback；新版易错词必须在这个 fallback 文本上继续运行，最后 fail-open 返回当前文本。

## Dictation 与 Agent Compose 分流

模式定义在：

- `Sources/VoxFlowDomain/Voice/VoiceTask.swift`
  - `VoiceTaskMode.dictation`
  - `VoiceTaskMode.agentCompose`
  - `VoiceTaskMode.agentDispatch`

运行时分流在：

- `Sources/VoxFlowApp/FeatureBridges/VoiceTaskCoordinator.swift`
  - `VoiceWorkflowKind.init(mode:)`
  - `processAndDeliver(kind:)`：普通 dictation 走 `TextProcessingPipeline`，Phase 1 只接这里。
  - `processAgentComposeAndDeliver(context:stylePrompt:)`：这是中文 UI 的“帮我说”，用 `AgentPromptBuilder` 和 `agentRefiner` 直接生成文本，第一期不接易错词。

Phase 1 ContextGate 应保证只有 `.dictation` final transcript 被 correction；`.agentCompose`、`.agentDispatch`、command、translation、interim、secure field 都 bypass。

## SQLite Migration 落点

迁移入口：

- `Sources/VoxFlowApp/Persistence/AppDatabase.swift`
  - `AppDatabase.migrator(clock:)` 定义按 id 排序的 migration 列表；
  - `initialSchemaSQL` 当前创建 `glossary_terms` 和 `replacement_rules`。
- `Sources/VoxFlowApp/Persistence/DatabaseMigrator.swift`
  - `DatabaseMigrator.migrate(_:)` 读取 `schema_migrations`；
  - 每个 `DatabaseMigration` 在 transaction 中执行并记录 id。

Phase 1 需要新增 destructive migration：

- drop `glossary_terms`；
- drop `replacement_rules`；
- 创建 `voice_correction_rules`；
- 创建 `voice_correction_events`；
- 创建 `voice_correction_learning_suppression`。

旧表数据不迁移到新版 correction rule。

## 旧 UI 与旧业务删除点

旧一级 tab `词汇表` 当前文件：

- `Sources/VoxFlowApp/Views/GlossaryView.swift`
  - `GlossarySection.words` 显示旧“易错词”；
  - `GlossarySection.replacements` 显示旧“文本替换”；
  - `sectionPicker`、`wordListPanel`、`replacementPanel` 是第一期删除点。
- `Sources/VoxFlowApp/ViewModels/GlossaryViewModel.swift`
  - `terms`、`replacementRules` 是旧 UI 状态；
  - `saveTerm`、`addWordList`、`importWordList`、`deleteTerm` 是旧“易错词”入口；
  - `saveReplacementRule`、`saveSimpleReplacement`、`deleteReplacementRule` 是旧“文本替换”入口；
  - `exportData` / `importData` 当前混合导出旧 terms 和 replacement rules，第一期需要更新语义或删除旧 replacement 部分。
- `Sources/VoxFlowApp/Persistence/GlossaryRepository.swift`
  - 当前 `GlossaryTerm` 读写 `glossary_terms`，只可保留为普通 prompt glossary 语义；不能作为新版 correction rule。
- `Sources/VoxFlowApp/Persistence/ReplacementRuleRepository.swift`
  - 当前 `ReplacementRule` / `SQLiteReplacementRuleRepository` 读写 `replacement_rules`，第一期删除或停止编译。
- `Sources/VoxFlowApp/TextProcessingBridges/ReplacementRuleEngine.swift`
  - 当前按 priority 顺序修改 current text，存在同轮级联风险，第一期删除或停止编译。

## 新一级 Tab 落点

主导航由这些文件驱动：

- `Sources/VoxFlowApp/FeatureBridges/NavigationRoute.swift`
  - 新增 `NavigationRoute.voiceCorrection`；
  - `title` 返回 `易错词`；
  - `systemImage` 使用 `text.badge.checkmark` 或同语义 SF Symbol。
- `Sources/VoxFlowApp/Views/SidebarView.swift`
  - 使用 `NavigationRoute.allCases` 渲染左侧一级 tab；新增 route 后会同级出现在 `首页 / 词汇表 / 风格 / 文件转写 / 笔记 / 设置 / 帮助` 中。
- `Sources/VoxFlowApp/Views/MainShellView.swift`
  - `WorkbenchDetailView.body` 的 route switch 新增 `VoiceCorrectionView`。

设计稿备注：当前 GPT Image 2 设计稿左侧导航漏画了新增 `易错词` tab。工程实现必须补上，并保持与现有 VoxFlow macOS 侧边栏风格一致。

## GPLv3 TypeWhisper 引入边界

Phase 1 确认走 TypeWhisper GPLv3 模块化引入。独立 package 落点：

```text
Packages/VoxFlowVoiceCorrectionKit/
├── COPYING
├── NOTICE.md
├── SOURCE_ATTRIBUTION.md
├── MODIFICATIONS.md
└── Sources/VoxFlowVoiceCorrection/
```

参考 commit：

```text
6c46bfc676539e2a1a245a01dca9a4afd6f2cb63
```

主要复制或改写参考：

- `TypeWhisper/Models/DictionaryEntry.swift` -> `CorrectionRule` 等领域模型；
- `TypeWhisper/Services/DictionaryService.swift` -> matcher / replacement 行为；
- `TypeWhisper/Services/PostProcessingPipeline.swift` -> LLM 后 post-processing 顺序；
- `TypeWhisper/Services/TextDiffService.swift` -> 高置信 diff / learning extraction；
- `TypeWhisper/Services/TargetAppCorrectionLearningService.swift` -> focused text observation 与 2/5/10 秒 polling；
- `TypeWhisper/Services/TextInsertionService.swift` -> focused element capture / recapture 思路，仅参考，不绕过 VoxFlow 现有 text insertion contract。

GPLv3 来源代码必须集中在 `VoxFlowVoiceCorrection` package 内，不散落到 App 壳层、ASR Provider、通用 persistence、通用 UI。

## 项目决策复核

`docs/voice-correction/project-decisions.md` 与当前任务清单一致：

- 易错词是一级 tab；
- 旧 `词汇表 -> 易错词` 与旧 `词汇表 -> 文本替换` 删除，不迁移数据；
- correction 在 LLM 后运行，LLM 失败仍运行；
- Agent Compose / “帮我说”第一期不接；
- 自动学习走 TypeWhisper focused text observation；
- OCR 不参与 correction engine 或永久学习；
- 首版 benchmark 门槛是 100 条中英文 correction fixtures。
