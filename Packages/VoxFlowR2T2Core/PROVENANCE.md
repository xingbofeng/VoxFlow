# PROVENANCE

本目录是 [xocialize/qwen3-asr-mlx-swift](https://github.com/xocialize/qwen3-asr-mlx-swift) 的**受控 fork（vendored copy）**，供 VoxFlow 的 Confucius4-R2T2 本机流式 Provider 使用。

## 固定的上游来源

| 项 | 值 |
|---|---|
| 仓库 | `https://github.com/xocialize/qwen3-asr-mlx-swift` |
| commit | `7c8768ead04c886489e62929f2c23902b99631ab` |
| 提交日期 | 2026-10-01 |
| 提交标题 | `Gates: pin the CPU before any MLX work (pinDevice first in every subcommand)` |
| 许可证 | MIT，Copyright (c) 2026 xocialize（见 `LICENSE`） |
| 归属说明 | 见 `NOTICE`（上游原文保留，未修改） |

## 为什么不直接依赖上游

上游 product/module 名同为 `Qwen3ASR`，与 VoxFlow 现有依赖 `speech-swift` 导出的 `Qwen3ASR` 冲突，无法在同一个 SwiftPM dependency graph 中并存；且上游要求 `swift-tools-version: 6.2` 与 `mlx-swift >= 0.31.5`，会强制升级 VoxFlow 当前 Swift 6.1.2 / MLX 0.31.4 基线，并外溢到所有依赖 `speech-swift` 的 Provider。因此改为项目内固定 commit 的隔离包。

## 本地相对上游的全部改动

### 包定义（`Package.swift`）

1. `swift-tools-version: 6.2` → `6.1`（适配 Xcode 16.4 / Swift 6.1.2）。
2. `mlx-swift`：`from: "0.31.5"` → `exact: "0.31.4"`（即 VoxFlow 现有版本）。
3. `swift-transformers`：`from: "1.3.0"` → `from: "1.3.3"`（与 VoxFlow 现有解析结果一致）。
4. 丢弃 `qwen3asr-gates` 可执行 target。上游该 target 的 `main.swift` 存在 `'main' attribute cannot be used in a module that contains top-level code` 冲突，与本 fork 无关；VoxFlow 亦不需要 parity gate 工具。
5. product / target / 目录：`Qwen3ASR` → `VoxFlowR2T2Core`。
6. 该 target 关闭编译警告：`swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Xfrontend", "-suppress-warnings"])]`。

   原因：上游源码引用当前 SDK 已弃用的 API——`cblas_dgemm`（Accelerate，需 `-DACCELERATE_NEW_LAPACK`）与 `createAttentionMask(h:cache:)`（mlx-swift-lm）——而 VoxFlow 的 `make debug` 门禁带 `-warnings-as-errors`。

   为什么改构建配置而不是改源码：`createAttentionMask` 的新旧重载语义不同（旧的重载从 `cache.first.maxSize` 推导 `windowSize`，新的要求单个 cache 并显式传 `windowSize`），改动会触及 ASR 解码路径的数值行为，而本 fork 的价值正是"源码与上游逐字节一致、可核验"。因此选择在此隔离包内关闭警告。

   注意：`-warnings-as-errors` 在驱动层与 `-suppress-warnings` 冲突，必须经 `-Xfrontend` 转发到前端才生效。

### 源码

**除下面列出的三处外，`Sources/VoxFlowR2T2Core/*.swift` 与上游 `Sources/Qwen3ASR/*.swift` 逐字节一致。**

#### 本地改动 1：`R2T2Stream.finish()` 的尾部冲刷条件（**行为修正**）

- 文件：`Sources/VoxFlowR2T2Core/R2T2Stream.swift`
- 上游：尾部缓冲为空时直接返回当前已确认文本，不发模型请求
  （`r2t2/r2t2_asr.py::finish_streaming_transcribe_no_reset`，上游 docstring 把它写成预期行为）。
- 本地：只要本次会话**处理过音频**（`consumedSamples > 0`），即使尾部缓冲为空也仍走一次 final decode；
  从未收到音频的会话仍然直接返回，不触发模型调用。另加 `didFinish` 保证幂等。
- 为什么必须改：非 final step 始终回滚最后 `options.unfixedTokens` 个 token（默认 1），
  这些 token 只有在**下一次** decode 里才会被重新生成并提交。录音恰好结束在 chunk 边界上
  （`320 ms + N × 160 ms`）时没有下一次，末字会永久丢失——对「按住说话、松开出字」的听写
  产品是用户可见的截尾。
- 风险：只影响「有音频且尾部为空」这一条此前不产生任何输出的分支，因此只会补上丢失的末尾内容，
  不改变其它路径的输出。`finish()` 的返回值语义仍是「final step 产生的增量」；
  调用方（`R2T2StreamingRuntimeDriver`）读的是 `committedText`，不受影响。

#### 本地改动 2：诊断 `steps` 的记录上限（**内存边界**）

- 文件：`Sources/VoxFlowR2T2Core/R2T2Stream.swift`
- 上游：每步 `steps.append(...)`，无上限。滚动窗口只约束音频，不约束这个数组，
  长录音会让它随会话时长线性增长。VoxFlow 从不读 `steps`。
- 本地：新增 `Options.maxRecordedSteps`，**默认 `0` 表示不记录**；`> 0` 时按该上限保留最近的条目，
  `Step.index` 改用单调递增计数，裁剪后不会重号。上游 parity gates 需要完整历史时显式设上限即可。

#### 本地改动 3：暴露被回滚的待定尾巴（**行为修正 / 新增 API**）

- 文件：`Sources/VoxFlowR2T2Core/R2T2Stream.swift`（新增 `R2T2Stream.pendingText` 与 `R2T2Text.pendingTail`）
- 上游：每一步解码后 `rollback(rawDecoded, k: options.unfixedTokens)` 扣下末尾 1 个 token，留到下一步
  带着更多上下文重新解码；被扣下的那段文本**不离开** `R2T2Stream`，调用方只看得到 `committedText`。
- 本地：新增 `public private(set) var pendingText`，取值由纯函数
  `R2T2Text.pendingTail(rawDecoded:committed:)` 算出——`committed` 不是 `rawDecoded` 前缀时返回空串，
  宁可什么都不暴露也不把错位文本交出去。`finish()`（final 已冲刷尾部）与 `resetContext()`（上下文已
  丢弃）都会清空它。
- 为什么必须改：尾巴不出 core 时 HUD 恒定落后一个 token。中文口述的用户可见表现是「说的最后一个字
  不显示、也不实时更新」——词表里 `今天` `我们` `什么` 这类双字词本身就是单个 token，回滚 1 个 token
  有时会扣掉两个字，因此看起来时好时坏。Provider 现在把它作为
  `PartialTranscript.unstableSuffix` 交给 HUD 作实时预览（见 `R2T2ASRSession`）。
- 风险与边界：`pendingText` 是**预览**语义，可被下一步改写，**不得**用于插入决策；`committedText`
  的语义与内容完全不变，最终文本仍然只由 final decode 产生。
  副作用：15 秒无 final 的超时兜底会取「最新 partial」，因此现在会包含这段待定尾巴——与 Qwen3 /
  NVIDIA 这些本来就暴露 `unstableSuffix` 的 Provider 行为一致。
- 覆盖：`Tests/VoxFlowR2T2CoreTests/PendingTailTests.swift`（model-free）。

#### 本地新增：`R2T2StreamPolicy`（不属于上游）

- 新文件：`Sources/VoxFlowR2T2Core/Sources/VoxFlowR2T2Core/R2T2StreamPolicy.swift`
- `R2T2Stream` 只有加载完 2.4 GB 权重才能构造，写在它内部的分支无法在 model-free 测试里钉住。
  上面两处决策被抽成纯函数（`shouldIssueFinalDecode`、`stepHistoryDropCount`），
  由新文件 `Tests/VoxFlowR2T2CoreTests/R2T2StreamPolicyTests.swift` 覆盖。

上游源码内部从不引用模块名，只引用以 `Qwen3ASR` 开头的类型名，因此模块改名不需要改一行源码。类型名**有意保留**：

- `Qwen3ASRModel` / `Qwen3ASRWeights` / `Qwen3ASRAudioEncoder` 等命名的是 **Qwen3-ASR 架构**；Confucius4-R2T2 正是 Qwen3-ASR-1.7B 的微调，改名反而更不准确。
- R2T2 专有的部分（`R2T2Stream`、`R2T2Text`）上游已按 R2T2 命名。
- 没有任何 VoxFlow 文件同时 `import VoxFlowR2T2Core` 与 speech-swift 的 `Qwen3ASR`，不存在类型歧义。

### 测试

上游三个测试（`JoinTests` / `LanguageTests` / `MelTests`）仅把 `@testable import Qwen3ASR` 改为 `@testable import VoxFlowR2T2Core`，其余逐字节一致。`R2T2StreamPolicyTests.swift` 与 `PendingTailTests.swift` 是本地新增，覆盖上面三处源码改动。全部为 model-free，可随 CI 运行。

## 与上游同步的步骤

1. `git fetch` 上游，选定新 commit。
2. 覆盖 `Sources/VoxFlowR2T2Core/` 与 `Tests/VoxFlowR2T2CoreTests/`，重新应用测试 import 改名，并**重新应用「源码」一节列出的三处本地改动**（`R2T2StreamPolicy.swift` 与 `R2T2StreamPolicyTests.swift` 两个新文件不会被覆盖，但需确认 API 未变）。
3. 按新 commit 复核 `Package.swift` 的三项目依赖约束是否仍成立；**若新 commit 要求高于 VoxFlow 当前基线的 Swift 或 MLX，暂停并单独决策，不得静默升级**。
4. 跑 `make test-r2t2-core` 与 Provider 测试，更新本文件顶部的 commit 表。

## 模型权重

本包**不含**模型权重。`mlx-community/Confucius4-R2T2-8bit` 由 VoxFlowModelStore 在用户显式发起时下载，其许可为 NetEase Youdao Model Use License Agreement，**不是** MIT，详见上游 `NOTICE` 与 `docs/resource-ownership.md`。
