## ADDED Requirements

### Requirement: 文件导入与任务快照
系统 MUST 允许用户通过浏览、拖放或多选导入 MP3、WAV、M4A、AAC、MP4、MOV 文件。每个文件必须创建独立任务，并在创建时持久化源文件绝对路径、显示文件名、入队时已选的 ASR Provider、识别语言、创建时间和 queued 状态；后续设置变化不得改变已入队任务的 Provider 或语言。

#### Scenario: 多选导入有效文件
- **WHEN** 用户一次选择三份受支持文件
- **THEN** 系统按选择顺序创建三份 queued 任务，队列与 SQLite 中的 Provider、语言和源路径快照完全一致

#### Scenario: 导入不支持格式
- **WHEN** 用户选择扩展名不在受支持集合中的文件
- **THEN** 系统拒绝该文件、显示可读格式错误，且不创建半成品任务或访问 Provider

### Requirement: 全局单任务串行调度
系统 MUST 在整个应用内一次只运行一个文件转写任务。queued 任务必须按入队顺序自动开始；正在运行、取消、失败、部分失败、完成或继续任务的状态转换必须由同一个队列服务串行化，不能因页面重复点击或异步回调启动并行转写。

#### Scenario: 导入多个任务后自动顺序处理
- **WHEN** 用户导入三份文件并启动第一份
- **THEN** 系统只将第一份标为 running，第一份结束后才开始第二份，且任意时刻数据库中最多一份任务为 running

#### Scenario: 重复启动运行任务
- **WHEN** 用户对同一 running 任务再次点击启动或继续
- **THEN** 系统保持原运行实例和进度，不创建第二个 Provider 会话或重复写入分段

### Requirement: 分段状态、取消与迟到回调隔离
系统 MUST 对每段持久化索引、起止毫秒、状态、文本、重试次数、Provider、模式、fallback 原因与脱敏错误。任务取消、删除、从头重试或继续运行后，属于旧运行 ID 的 partial、final、进度和错误回调必须被丢弃，不能覆写当前任务、其他任务或导出结果。

#### Scenario: 取消后收到旧段 final
- **WHEN** 用户取消正在转写的任务后，旧 Provider 发送 final 或进度回调
- **THEN** 任务保持 cancelled 状态，旧回调不新增/修改 Segment、不改变全文且不触发下一任务之外的输出

#### Scenario: 单段最终失败
- **WHEN** 一个任务至少有一段完成且至少一段在重试耗尽后失败
- **THEN** 任务状态为 partiallyFailed，已完成段和全文可见，失败摘要列出段索引且不会伪造失败段文本

### Requirement: 崩溃恢复与继续未完成任务
系统 MUST 在启动时将遗留的 running Job 及 running Segment 标为 interrupted，并保留所有 completed Segment。用户触发“继续”时，系统必须复用已完成段，只处理 interrupted、failed 或尚未创建的段；用户触发“从头重试”时才允许清除旧段和旧结果。

#### Scenario: 重启后继续长文件
- **WHEN** 应用在第 3/5 段完成后异常退出并重新启动
- **THEN** 任务显示 interrupted，“继续”只向 Provider 发送第 4 和第 5 段，前三段文本、时间戳和重试记录保持不变

#### Scenario: 源文件已移动
- **WHEN** 用户继续或从头重试任务时源文件路径已不存在或不可读取
- **THEN** 系统显示“源文件不可用”的可读错误，保留既有成功段、全文和导出能力，不删除任务记录
