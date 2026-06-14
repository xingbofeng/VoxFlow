# Delta: 可靠语音任务

**Change ID:** `add-context-aware-voice-workflows`
**Affects:** 录音编排、SQLite、历史详情、文本注入、剪贴板、恢复流程

## ADDED Requirements

### Requirement: 语音任务持久化

系统 SHALL 在录音开始时创建持久化 VoiceTask，并在每个关键阶段保存当前可恢复数据。

#### Scenario: 开始录音

- GIVEN 当前没有活动任务
- WHEN 用户触发语音转录或“帮我说”
- THEN 创建状态为 recording 的 VoiceTask
- AND 保存任务模式、创建时间和目标应用信息

#### Scenario: 阶段性落盘

- GIVEN VoiceTask 正在处理
- WHEN 音频、原始转写、上下文或最终文本中的任一项完成
- THEN 立即更新该任务
- AND 不等待整个任务完成

#### Scenario: 应用异常退出

- GIVEN 原始转写已经保存
- WHEN VoxFlow 在 LLM 或输出阶段异常退出
- THEN 重新启动后仍可查看原始转写
- AND 任务显示为未完成或失败

### Requirement: 明确的任务模式和状态

VoiceTask SHALL 区分普通语音转录和“帮我说”，并保存当前阶段、完成状态、输出结果及结构化失败原因。

#### Scenario: 普通转录完成

- GIVEN 普通语音转录成功注入目标应用
- WHEN 系统结束任务
- THEN 模式为 `dictation`
- AND 状态为 completed
- AND 输出结果标记为 injected

#### Scenario: “帮我说”完成

- GIVEN LLM 成功生成并复制最终文本
- WHEN 系统结束任务
- THEN 模式为 `agentCompose`
- AND 状态为 completed
- AND 输出结果标记为 copied

### Requirement: 输出前重新校验目标

普通语音转录 SHALL 在自动注入前重新校验录音开始时锁定的目标应用和窗口。

#### Scenario: 目标未变化

- GIVEN 当前应用和窗口与任务目标一致
- WHEN 普通转录准备输出
- THEN 可以执行现有文本注入策略

#### Scenario: 应用发生变化

- GIVEN 用户已从目标应用切换到另一个应用
- WHEN 普通转录准备输出
- THEN 不得发送粘贴按键
- AND 将最终文本复制到剪贴板
- AND 任务记录目标变化原因

#### Scenario: 窗口发生变化

- GIVEN Bundle ID 相同但目标窗口标识明显不一致
- WHEN 普通转录准备输出
- THEN 停止自动注入
- AND 将最终文本复制到剪贴板

### Requirement: 普通转录失败降级

系统 SHALL 保证普通转录在 LLM 或注入失败后仍保留可用文本。

#### Scenario: LLM 纠错失败

- GIVEN ASR 已产生非空原始转写
- WHEN LLM 纠错失败
- THEN 使用原始转写作为最终文本
- AND 继续尝试安全输出
- AND 保存警告

#### Scenario: 注入失败

- GIVEN 已产生最终文本
- WHEN 文本注入失败
- THEN 将最终文本保留在剪贴板
- AND 任务进入 partiallyCompleted 或 failed
- AND 首页提供再次操作

### Requirement: 转写失败音频恢复

系统 SHALL 为完全转写失败的任务保留临时音频，并在 24 小时后清理。

#### Scenario: ASR 完全失败

- GIVEN 没有 final 或可用 partial 文本
- WHEN ASR 结束并报错
- THEN 保存音频引用和失败原因
- AND 首页提供“重新转写”

#### Scenario: 音频过期

- GIVEN 失败音频创建时间超过 24 小时
- WHEN 清理服务运行
- THEN 删除该音频
- AND 保留任务元数据和失败原因

#### Scenario: 转写成功

- GIVEN 任务已有非空原始转写
- WHEN 任务完成或进入后续阶段
- THEN 不长期保存临时音频

### Requirement: 重启恢复提示

系统 SHALL 在启动时识别未完成任务，但不得自动执行网络请求、剪贴板写入或文本注入。

#### Scenario: 发现未完成任务

- GIVEN 本地存在一个或多个未完成 VoiceTask
- WHEN VoxFlow 启动
- THEN 显示一次可关闭提示
- AND 提供进入首页查看的操作
- AND 不自动重试

### Requirement: 首页任务详情与恢复操作

首页 SHALL 在现有历史详情中显示任务数据，并按可恢复内容提供操作。

#### Scenario: 查看失败任务

- GIVEN 一个任务在 LLM 生成后复制失败
- WHEN 用户打开首页详情
- THEN 显示原始口述、上下文预览、最终文本和失败原因
- AND 提供“复制”和“重新生成”

#### Scenario: 查看转写失败任务

- GIVEN 一个任务没有原始转写但音频仍在保留期
- WHEN 用户打开首页详情
- THEN 提供“重新转写”
- AND 不显示不可用的“重新生成”

## MODIFIED Requirements

### Requirement: 历史记录保存

现有历史记录 SHALL 扩展为可呈现 VoiceTask 的完成和恢复信息，同时兼容旧记录。

#### Scenario: 读取旧历史

- GIVEN 数据库中存在升级前的历史记录
- WHEN 应用完成 schema 迁移并读取记录
- THEN 旧记录按 `dictation/completed` 展示
- AND 原始转写、最终文本和已有 trace 不丢失

### Requirement: 文本注入结果

TextInjector SHALL 返回可观察的成功或失败结果，以便任务编排记录和降级。

#### Scenario: 注入不可确认

- GIVEN 系统无法确认粘贴已执行
- WHEN TextInjector 返回失败
- THEN orchestrator 不得把任务标记为成功注入

## REMOVED Requirements

(None)
