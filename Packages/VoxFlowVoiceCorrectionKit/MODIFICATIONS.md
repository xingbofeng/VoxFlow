# 修改说明

本 package 把 TypeWhisper 启发的纠错思路适配到 VoxFlow 架构。

已实现和计划中的差异：

- 使用 VoxFlow 命名：`VoxFlowVoiceCorrection`，不沿用 TypeWhisper 运行时命名。
- 纠错只作用于普通听写 final transcript，且在可选 LLM refinement 之后。
- Agent Compose、command、translation、interim transcript 和安全字段不纳入 Phase 1 纠错。
- 对不可变 raw input 做匹配，一次性解决冲突，并从尾部应用替换以避免级联替换。
- 规则通过 VoxFlow SQLite repository 持久化，matcher 始终基于不可变快照。
- 产品模型呈现为“目标词 + 别名”，运行时仍是确定性的“原文 -> 替换”纠错规则。
- focused text observation 测试使用 fake observer 和 fake clock，CI 不需要 Accessibility 权限。
- UI 实现是 VoxFlow 专属，不复制 TypeWhisper 的 UI 布局或命名。

## Core 模型实现

- 把规则模型拆分为 VoxFlow 专属的 `Core` value type，带 `Codable`、`Equatable` 和严格的 `Sendable` 边界。
- 显式加入全局 / 应用 scope、生命周期、规则来源、provider/model/language 元数据、计数器、不可变快照、纠错事件和 fail-open 警告。
- 加入空规则或自替换规则校验、size 与 confidence 限制，以及保守的自动学习限制。

## 确定性匹配实现

- 用无状态 matcher、resolver、applier value type 替换 TypeWhisper 的 service-owned mutation 流。
- 从不可变 raw text 收集所有匹配，并按 resolver 决定从尾部应用替换，防止同轮级联。
- span 使用 UTF-16 offset 表示，AppKit、Accessibility、SQLite 事件和 benchmark 报告共用一套范围约定。
- 按 source、scope、policy、confidence、length、position、rule ID 确定性地解决重叠。
- 加入 VoxFlow 专属的 `ContextGate`，让 Phase 1 纠错只作用于普通听写 final transcript，对不支持的模式或隐私敏感字段 fail-open。

## Focused text observation 实现

- 用 Foundation-only 的 observation contract 替代直接耦合 `AXUIElement`，element 身份用 opaque identity 表示。
- Accessibility 读取留在 App adapter 层，并阻止读取安全字段值。
- 加入 fake observer 和 fake clock 边界，单元测试不需要 Accessibility 权限或墙钟延迟。
- 加入保守的学习 coordinator：按 TypeWhisper 的 2 / 5 / 10 秒偏移轮询，存 app scope 的学习规则，遵守自动学习与直接生效设置，并拒绝来自已应用纠错的反馈环。
- 加入纯函数 high-confidence extractor，在持久化之前拒绝 rewrite、insertion-only、deletion-only、歧义、超出范围、重叠等情况。
- 加入学习生命周期策略：手动规则、active/candidate 自动规则、30 天抑制、undo 动作、confidence 降低，以及反复被用户回退后的暂停。

## 目标词 UI 与持久化实现

- 加入 `CorrectionTargetTerm` 和 `CorrectionTargetProjection`，让 VoxFlow 可以展示目标词库，同时在底层保留 TypeWhisper 式的确定性 alias。
- 加入 SQLite target 持久化和一个破坏性 / 前向迁移：按 `replacement + scope` 从旧纠错规则 backfill target。
- 加入 target-aware 自动学习：插入后用户编辑会创建或复用被纠正的 target term，然后把误听文本存为 alias。
- OCR context boost 不进入永久学习。OCR hotword 只能作为临时上下文进入 LLM prompt，不写 target、不创建 alias、不直接喂给纠错引擎。
