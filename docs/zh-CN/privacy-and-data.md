# 隐私与数据

码上写默认本地优先。除非你显式配置云端 ASR 或 LLM Provider，否则工作上下文保存在 Mac 上。

## 本地数据

默认本地保存：

- 听写历史
- 截图和录屏记录
- OCR 文本
- 剪切板资产
- 笔记
- 易错词规则和学习候选
- 非敏感设置
- 启用后的本地诊断文件

默认数据目录：

```text
~/Library/Application Support/VoxFlow/
```

主数据库：

```text
voxflow.sqlite
```

## 凭据

API Key 和云端凭据默认保存在应用数据目录下的本地 `credentials.json` 文件中。

请保护好这个文件。凭据不会写入 UserDefaults、SQLite、日志、测试快照或导出的诊断归档。

## 云端调用

只有配置了相关功能时，码上写才会向外部发送数据：

- Apple Speech 的音频处理遵循 macOS 系统行为。
- 本地 ASR 模型在本机处理音频。
- 云端 ASR 会把录音发送给所选 Provider。
- LLM 纠错会把识别后的文本发送给你配置的 LLM Provider。
- 问 AI 会把问题和聊天上下文发送给你配置的 LLM Provider。
- 翻译或总结可以根据设置使用 Apple 系统翻译、本地模型或配置的 LLM。

## 剪切板和截图

剪切板资产会保存在本地，供启动台和工作台回看；噪音过滤会跳过无意义的高频变化。

剪切板图片 OCR 可以作为一次性入口使用。通过 `⌘⇧A` 捕获的截图会和 OCR 文本一起保存在本地，方便后续搜索和回看。

## 启动存储失败

如果持久化存储无法打开，码上写不会再静默切到临时内存存储。App 会先询问是否临时继续；该模式下新历史、资产和设置可能在重启后丢失。

## 诊断

诊断 trace 默认保存在本地。LLM trace 诊断可能包含 prompt、request 或 response 细节，应保持显式 opt-in。崩溃日志和诊断上传行为由设置控制。

公开隐私政策见 [PRIVACY.md](../PRIVACY.md)。
