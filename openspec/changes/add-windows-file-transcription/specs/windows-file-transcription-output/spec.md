## ADDED Requirements

### Requirement: 稳定复制与多格式导出
系统 MUST 允许完成或部分完成任务复制最终文本，并导出 TXT、Markdown、SRT、译文 TXT、译文 Markdown 和双语 Markdown。没有最终文本时相关操作必须禁用；没有译文时译文相关格式必须禁用并给出可读原因。

#### Scenario: 导出原始结果
- **WHEN** 用户对已完成任务选择 TXT、Markdown 或 SRT 导出
- **THEN** 系统生成对应文本并打开保存位置选择，导出文件名使用源文件名的安全版本，原始源文件不被修改

#### Scenario: 部分完成任务导出
- **WHEN** 用户对 partiallyFailed 任务导出文本或 SRT
- **THEN** 系统只使用已完成段和已合并文本，并保留页面中的失败摘要；不得填补失败段、伪造时间戳或拒绝全部已成功结果

### Requirement: 从持久化分段生成准确 SRT
系统 MUST 在每次 SRT 导出时从 SQLite 中读取任务的 completed Segment，按 `segment_index` 排序，并使用持久化的 `start_ms`、`end_ms` 与文本生成标准 SRT。应用重启、页面重建或源文件暂时不可播放时，只要段记录存在，SRT 时间戳必须保持准确。

#### Scenario: 重启后导出 SRT
- **WHEN** 一份多段任务完成、应用退出并重新启动后用户导出 SRT
- **THEN** 导出包含每个完成段的原始时间范围，而不是把全文压缩为从 00:00:00 到总时长的一条字幕

### Requirement: 显式 OpenAI 全文翻译
系统 MUST 仅在用户点击“全文翻译”后复用已配置的官方 OpenAI Provider 处理最终文本。翻译状态必须独立保存为 pending/running/completed/failed；翻译失败、取消、未配置、HTTP/SSE 错误、空结果或模型错误必须保留原始转写和其状态，不得自动更换模型、Provider 或重试整份文件。

#### Scenario: 成功翻译并导出双语 Markdown
- **WHEN** 用户对已完成任务显式触发翻译且 OpenAI 返回有效译文
- **THEN** 页面显示与 macOS 相同语义的原文/译文对比，SQLite 保存译文与目标语言，双语 Markdown 可导出

#### Scenario: 翻译失败
- **WHEN** 用户触发全文翻译但 OpenAI 未配置或返回错误
- **THEN** 任务仍保持原有 completed 或 partiallyFailed 状态，原文复制/导出仍可用，页面显示翻译失败反馈且不泄露凭据或请求文本

### Requirement: 排除笔记和扩展内容工作流
文件转写页面 MUST 在首期不显示“保存为笔记”、摘要、字幕烧录、Groq 原生整文件模式或新增 Provider 配置入口。该页面必须只暴露本变更规定的转写、播放、翻译、复制、导出和诊断操作。

#### Scenario: 查看完成任务的操作区
- **WHEN** 用户选择一份已完成任务
- **THEN** 操作区只显示播放、复制、翻译和导出等已批准动作，不显示 Notes、截图、OCR、Agent、摘要或字幕烧录入口
