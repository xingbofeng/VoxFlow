# Delta: 全应用“帮我说”

**Change ID:** `add-context-aware-voice-workflows`
**Affects:** 快捷键、上下文采集、LLM Prompt、HUD、剪贴板、首页详情

## ADDED Requirements

### Requirement: “帮我说”动作绑定

系统 SHALL 将“语音转录”和“帮我说”建模为独立动作，并阻止无法区分的快捷键冲突。

#### Scenario: 保留现有转录快捷键

- GIVEN 用户升级前使用按住右 Command 进行语音转录
- WHEN 设置迁移完成
- THEN 原有转录快捷键保持有效
- AND 不自动改绑为“帮我说”

#### Scenario: 长按槽位可用

- GIVEN 用户的长按触发未承担语音转录
- WHEN 用户配置“帮我说”
- THEN UI 可以推荐使用长按触发

#### Scenario: 长按已占用

- GIVEN 长按已绑定语音转录
- WHEN 用户配置“帮我说”
- THEN UI 引导设置独立快捷键
- AND 不允许保存冲突绑定

#### Scenario: 未配置“帮我说”

- GIVEN “帮我说”没有可用触发方式
- WHEN 用户查看相关设置或入口
- THEN 显示“设置快捷键”

### Requirement: 面向所有应用触发

“帮我说” SHALL 可在任意前台应用中触发，不依赖应用专用 Adapter。

#### Scenario: 在未知应用中触发

- GIVEN 当前应用未命中内置注册表且没有用户风格规则
- WHEN 用户触发“帮我说”
- THEN 系统仍开始录音和上下文采集
- AND 使用默认风格指导

#### Scenario: 用户口述具体任务

- GIVEN 当前窗口包含一段聊天内容
- WHEN 用户说“帮我回 XXX 的微信，告诉他六点前发”
- THEN 该完整口述作为用户任务指令传给 LLM
- AND 程序不要求先把任务分类为微信回复

### Requirement: 录音与上下文并行

系统 SHALL 在“帮我说”开始时并行启动录音和上下文采集，且上下文不得阻塞录音启动。

#### Scenario: 上下文采集较慢

- GIVEN Accessibility 或视觉采集尚未完成
- WHEN 用户开始说话
- THEN 录音和 ASR 正常进行

#### Scenario: 上下文超时

- GIVEN 上下文采集超过有界超时
- WHEN ASR 已获得口述文本
- THEN 取消或忽略迟到的上下文
- AND 仅根据口述继续生成

### Requirement: 通用上下文快照

系统 SHALL 采集当前应用、窗口元数据及可用的可见文本，并可使用当前窗口视觉内容作为兜底。

#### Scenario: Accessibility 可读

- GIVEN 当前窗口通过 Accessibility 暴露可见文本
- WHEN 系统采集上下文
- THEN 优先使用结构化文本
- AND 去重、裁剪并标记来源

#### Scenario: Accessibility 不可读

- GIVEN 当前窗口未暴露足够文本
- AND 当前 LLM Provider 支持视觉输入
- WHEN 系统采集上下文
- THEN 可以临时捕获当前窗口视觉内容用于本次请求
- AND 请求结束后释放截图

#### Scenario: 不支持视觉输入

- GIVEN Accessibility 无可用文本
- AND 当前 Provider 不支持视觉输入
- WHEN 系统完成上下文采集
- THEN 返回无上下文快照和警告
- AND 不阻断口述生成

#### Scenario: 安全输入区域

- GIVEN 当前焦点是 Secure Text Field 或其他明确安全区域
- WHEN 用户触发“帮我说”
- THEN 不读取或上传窗口上下文
- AND 仅根据口述生成或提示上下文已禁用

### Requirement: 固定 Agent Prompt

系统 SHALL 使用固定 Agent Prompt 将应用元数据、应用风格、上下文和用户口述组合为生成请求。

#### Scenario: 生成聊天回复

- GIVEN 上下文中包含对方询问交付时间
- AND 用户口述“告诉他可以，六点半之前发”
- WHEN LLM 处理固定 Agent Prompt
- THEN 输出可直接使用的回复正文
- AND 不解释对方说了什么
- AND 不虚构地点、人物或额外承诺

#### Scenario: 上下文不足

- GIVEN 上下文为空或不完整
- WHEN LLM 生成文本
- THEN 忠实执行明确口述
- AND 采用保守表达
- AND 不补充用户没有提供的事实

#### Scenario: 技术应用

- GIVEN 当前应用风格为 coding
- WHEN 用户要求生成代码、命令或技术文本
- THEN Prompt 指导模型保留代码、命令、变量名、路径和英文术语

### Requirement: 只复制最终文本

“帮我说”第一版 SHALL 只把生成结果复制到系统剪贴板，不自动注入或发送。

#### Scenario: 生成成功

- GIVEN LLM 返回非空最终文本
- WHEN 输出阶段执行
- THEN 清空并写入系统剪贴板
- AND 不恢复旧剪贴板
- AND HUD 显示“已复制到剪贴板”

#### Scenario: 禁止自动发送

- GIVEN 当前应用是微信、邮件或其他通信工具
- WHEN “帮我说”生成完成
- THEN 不发送 Command-V
- AND 不模拟 Enter
- AND 不调用任何发送动作

#### Scenario: 复制失败

- GIVEN 系统剪贴板写入失败
- WHEN 输出阶段结束
- THEN 保存最终文本和失败原因
- AND 首页提供再次复制

### Requirement: 上下文预览

系统 SHALL 在首页现有历史详情中显示“帮我说”使用的裁剪后文本上下文。

#### Scenario: 查看上下文

- GIVEN 一个“帮我说”任务已采集文本上下文
- WHEN 用户打开该任务详情
- THEN 显示应用、窗口、上下文来源和裁剪后正文
- AND 不显示或保存原始窗口截图

### Requirement: 清晰的 HUD 状态

HUD SHALL 显示“帮我说”当前阶段和降级结果。

#### Scenario: 正常生成

- GIVEN 上下文采集和 ASR 正常
- WHEN 任务推进
- THEN HUD 依次可显示读取窗口、转写、生成和已复制状态

#### Scenario: 上下文失败

- GIVEN 当前窗口上下文不可用
- WHEN 系统继续处理
- THEN HUD 显示“未读取到当前窗口，将仅根据口述生成”

### Requirement: LLM 配置门禁

“帮我说” SHALL 要求存在可用的 LLM 配置，但不得影响普通语音转录。

#### Scenario: 未配置 LLM

- GIVEN 用户没有可用 LLM Provider
- WHEN 用户触发“帮我说”
- THEN 不开始无法完成的生成任务
- AND 显示进入 LLM 设置的操作
- AND 普通语音转录仍然可用

## MODIFIED Requirements

### Requirement: 文本处理模式

文本处理层 SHALL 根据 VoiceTaskMode 选择保守纠错 Prompt 或固定 Agent Prompt。

#### Scenario: 普通转录

- GIVEN VoiceTaskMode 为 `dictation`
- WHEN 处理原始转写
- THEN 沿用当前保守纠错、术语表和应用风格链路

#### Scenario: “帮我说”

- GIVEN VoiceTaskMode 为 `agentCompose`
- WHEN 处理原始口述
- THEN 使用 Agent Prompt 和上下文
- AND 不受“仅纠错、不改写”的普通转录约束限制

## REMOVED Requirements

(None)
