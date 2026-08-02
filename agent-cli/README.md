# VoxFlow Agent CLI（Rust）

`agent-cli/` 是 VoxFlow 的 Rust 辅助程序源码目录。它是一个 crate、两个 binary，不是两套独立的 Agent 实现。

```text
agent-cli/（crate: voxflow）
├── voxflow        Unix/macOS 完整 CLI：router、session、MCP、PTY、wrapper
└── voxflow-agent  Windows 内置 Agent sidecar：builtin_agent 模型循环 + JSONL
```

跨平台共用 `src/builtin_agent.rs`：OpenAI-compatible Chat Completions、工具调用循环、JSONL event、循环上限、超时与敏感字段脱敏。平台宿主能力不共用：macOS 由 Swift/AppKit 实现；Windows 由 C#/WPF 实现文件、剪贴板、键盘、UI Automation、网络和用户交互工具。Rust 只编排模型回合和工具调用。

## Windows sidecar

Windows 发布物只带 `voxflow-agent.exe`，不带完整 `voxflow` CLI、Router、MCP、PTY、Unix socket、外部 Agent CLI 或 Agent Dispatch。

```powershell
cd agent-cli
cargo build --release --target x86_64-pc-windows-msvc `
  --no-default-features --features builtin-agent --bin voxflow-agent
cargo test --all-targets
```

`voxflow-agent` 从 stdin 读取一行 JSONL run request，再读取 Windows host 的 ToolResult，只向 stdout 写 JSONL runtime event。API Key 只存在于首行 stdin 请求的内存生命周期，不能出现在 argv、环境变量、stdout、trace 或日志中。

## feature 与安全边界

- `builtin-agent`：最小内置 Agent 模型循环；Windows sidecar 使用它。
- `full-cli`：完整 Unix CLI 依赖。
- Router、session、PTY、MCP、wrapper 和 Unix socket 均为 `cfg(unix)`，不会编译进 Windows sidecar。
- JSONL schema 当前为 v1；未知版本在 Windows host 侧 fail-closed。
- 默认限制：12 个模型回合、10 次工具调用、同一调用/失败最多 2 次；Provider timeout 为 1～600 秒，Windows task 默认 300 秒。
- sidecar 不持有 Windows 权限、不读数据库、不执行 shell、不直接修改文件或输入文本。
