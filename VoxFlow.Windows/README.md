# VoxFlow Windows

## Windows 内置 Agent

Windows Agent 使用“C#/WPF 宿主 + 最小 Rust sidecar”：C# 负责快捷键、ASR、前台窗口、WPF、DPAPI、UI Automation、文件/网络/输入工具和 SQLite task/trace；Rust `voxflow-agent.exe` 只负责 OpenAI-compatible 模型回合和 tool-calling loop。它与 macOS 共用 Rust `builtin_agent`，但不复用 macOS 的 Swift UI/权限代码。

Windows 不打包完整 Unix `voxflow` CLI、Router、MCP、PTY、外部 Agent CLI 或 Agent Dispatch。sidecar 只能从安装目录 `AgentRuntime/` 启动；发布时重新构建、生成 manifest，并校验固定文件名、x64 PE 和 SHA-256。缺失或篡改时 Agent 不可用，绝不从 PATH 查找替代程序。

首版工具集合固定为 17 项，均由 C# host 执行；不暴露 shell、删除、进程执行、安装、提权或自动提交。文件、Notebook、目录/搜索、听写历史、剪贴板、键盘、文本框、HTTPS、URL、网页搜索/抓取、状态响应和用户提问工具均已接入统一意图、路径、目标、大小、UIPI、脱敏与取消策略。Agent 只有在受控 sidecar、ASR、默认 LLM 和 tool-calling 能力都通过启动前检查时才会占用麦克风。

Windows sidecar 的构建证据见 [Windows Built-in Agent build evidence](docs/windows-builtin-agent-build-evidence.md)。发行脚本使用静态 MSVC CRT 构建并把 sidecar 固定在 `runtime/agent/`；安装布局门禁会对其 PE 架构、字节数、SHA-256 和导入依赖重新检查。

这里是 VoxFlow Windows V1 的独立实现目录。Windows 版以当前 macOS 版的已确认交互、配置和视觉基线为准，采用 WPF、.NET 10、MVVM 与 Windows 原生能力实现；不复用 macOS 的 Swift/MLX 运行时。

## 目录约定

```text
VoxFlow.Windows/
├── src/
│   ├── VoxFlow.Windows.Domain/
│   ├── VoxFlow.Windows.Application/
│   ├── VoxFlow.Windows.Infrastructure/
│   ├── VoxFlow.Windows.Platform/
│   ├── VoxFlow.Windows.Providers.Qwen/
│   ├── VoxFlow.Windows.Providers.Cloud/
│   └── VoxFlow.Windows.App/
├── tests/
│   ├── VoxFlow.Windows.Domain.Tests/
│   ├── VoxFlow.Windows.Application.Tests/
│   ├── VoxFlow.Windows.Infrastructure.Tests/
│   ├── VoxFlow.Windows.Platform.Tests/
│   ├── VoxFlow.Windows.Providers.Qwen.Tests/
│   ├── VoxFlow.Windows.Providers.Cloud.Tests/
│   ├── VoxFlow.Windows.App.Tests/
│   └── VoxFlow.Windows.IntegrationTests/
├── native/qwen-asr/          # 固定上游来源与许可证
├── native/qwen-asr-bridge/   # 本项目稳定 C ABI
├── installer/                # per-user x64 EXE 安装器
├── docs/                     # 追踪表、验收与安全规则
├── scripts/                  # 仅开发/验证脚本，不存放真实凭据
├── .env.live.example
└── .gitignore
```

项目依赖只允许由外向内：App 指向 Application/Domain，Infrastructure、Platform 和 Providers 指向 Application/Domain。测试目录与生产模块一一映射。真实模型、构建输出、诊断日志和本机联调配置均不进入版本控制。

## 本机实时联调环境变量

复制样例后，只能在本机填写服务凭据：

```bash
cp .env.live.example .env.live
```

`.env.live` 已被忽略。它可包含 OpenAI 官方 API、腾讯云流式 ASR、阿里云流式 ASR、火山引擎流式 ASR 的本机联调变量；发布程序不会携带其中任何值。实时联网测试必须手动触发，CI 只运行离线测试。

不要把真实密钥写入 `.env.live.example`、README、测试 fixture、日志、截图或 Git 提交。提交前运行：

```bash
bash tests/check-no-secrets.test.sh
```

该测试会先证明扫描器能拒绝一个运行时生成的合成泄漏 fixture，再检查提交的环境变量样例、README 和忽略规则。扫描器只报告文件、行号和规则名称，绝不回显疑似凭据内容。
