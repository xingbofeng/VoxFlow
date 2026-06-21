# Vibe Coding 指挥中心设计

Vibe Coding 指挥中心是 VoxFlow 面向 coding-agent 终端的语音指挥能力：用户按住快捷键说出队员名和指令，VoxFlow 把指令投递到对应的 Codex、Claude、CodeBuddy 或任意终端 Agent，并自动提交。

本文里的公开产品名使用 **Vibe Coding 指挥中心**；代码和领域模型内部可继续使用 `AgentDispatch` / `agentDispatch`，表示“把语音指令投递到本地已注册 Agent session”的任务模式。它和 **Agent Compose / 帮我说** 不是同一能力；帮我说仍然保持只复制、不注入、不自动发送。

## 设计图

- HUD 设计图：[docs/assets/vibe-coding-command-center-hud.png](assets/vibe-coding-command-center-hud.png)
- 设置页交互图：[docs/assets/vibe-coding-command-center-settings.png](assets/vibe-coding-command-center-settings.png)

## UI 一致性

Vibe Coding 指挥中心必须延续当前 VoxFlow 设置页的视觉语言，不另起一套设计系统。

- 设置页保持单列竖向滚动、浅色背景、白色圆角卡片、细边框、轻阴影、绿色主色和柔和图标块。
- HUD 使用同一套浅色卡片语言，不使用深色玻璃、紫色渐变、营销式 hero 或装饰性背景。
- 文案风格保持“设置项 + 简短说明 + 明确操作”，不写教程式长段落。
- 控件形态复用现有设置页习惯：按钮、开关、分段控件、状态 chip、轻量提示条。
- “Vibe Coding 指挥中心”是用户可见名称；代码内部的 `AgentDispatch` 不直接暴露给用户。
- UI 实现时以本文设计图为视觉基准；如因 SwiftUI 组件限制需要调整，必须保持层级、间距、主色、信息密度和交互含义一致。

## 目标

- 保持 Codex、Claude、CodeBuddy 等 CLI 的原始交互体验基本不变。
- 支持任意终端 Agent 命令，不限定固定供应商或固定终端。
- 让 VoxFlow 可以把语音指令路由到已注册的 Agent session。
- 通过 wrapper 拥有的 PTY 输入通道自动提交指令，不依赖 GUI 焦点或剪切板。
- 准确命名队员时直接发送；目标不明确时用 HUD 让用户确认。
- 保留用户确认过的队员别名，用于后续自然语言目标匹配。
- VoxFlow.app 产品化后自动管理 router / MCP / helper，不要求用户手动启动常驻服务。

## 非目标

- 不做 GUI 粘贴加回车 fallback。
- 不做 auto-yes、auto-retry、自动权限批准或用户任务 prompt 改写。
- 不把 MCP 当作终端输入通道。
- 不做多 agent 架构，不让 agent 互相派活。
- 不在 Router 里长期复制保存 agent 输出全文。
- P1/P2 不依赖模型做目标解析。

## 核心概念

- **Vibe Coding 指挥中心**：用户可见的功能名和设置页入口。
- **Agent Dispatch / agentDispatch**：代码内部任务模式，表示语音投递到本地已注册 Agent session。
- **Agent session / 队员会话**：由 wrapper 启动并注册的本地 coding-agent CLI 会话。
- **Agent card / 队员卡片**：Router 维护的 active session 摘要，供 HUD 和 resolver 实时读取。
- **Agent alias / 队员别名**：用户确认过的目标短语，例如“前端”“后端”“数据库”，以后可解析到同一个 Agent session。
- **Provider session reference**：Codex、Claude、CodeBuddy 等 CLI 自己的会话 ID、transcript 路径或日志引用，挂到 Agent session 上用于恢复、诊断和统计。

## 关键决策

### 不迁移终端工作流

用户当前主要使用 Ghostty，也可能使用 iTerm2 或 Terminal。Vibe Coding 指挥中心不能要求用户迁移到 tmux、cmux 或新的终端工作台。

原因：

- tmux / cmux 对用户有学习成本。
- 迁移终端会破坏现有布局、快捷键、字体、主题和工作流。
- 用户真正需要的是“把语音指令投喂到指定队员”，不是新的多 agent IDE。

因此本方案只要求用户用 `vox flow ...` 启动需要被指挥的 Agent 会话；终端仍然是用户原来的终端。

### 不做通用终端上下文读取

从 iTerm2 / Ghostty / Terminal 读取“当前终端上下文”在通用层很不稳定：

- 不同终端暴露能力不同。
- 屏幕内容不等于真实 TTY 输入状态。
- GUI 读屏或 Accessibility 读取容易受焦点、滚动区域、主题和隐私权限影响。
- 很难判断某个终端里的 CLI 是否正在等待输入。

本方案不把“读当前 terminal 内容”作为主路径。主路径是 wrapper 拥有 PTY，因此天然知道自己启动了什么、输入通道在哪、会话是否还活着。

### 选择 wrapper，而不是 GUI 投喂

GUI 投喂方案通常是“聚焦窗口 -> 粘贴 -> 回车”。本方案不采用，原因：

- 会抢焦点，干扰用户当前操作。
- 依赖窗口位置和当前前台 app，容易误投。
- 会使用剪切板，污染用户剪切板或和现有 TextInjector 事务冲突。
- 自动回车风险高，一旦目标错了就是不可逆操作。

wrapper 启动 Claude / Codex / CodeBuddy 时拥有它的 PTY，可以直接写入对应输入通道并提交 Enter。这样不会改变终端 app，也不需要知道窗口在屏幕哪里。

### wrapper 必须保持透明

wrapper 的底线是“原始体验不能变”。

允许的变化：

- 启动时显示一段短 banner。
- 更新 window title。
- 状态变化时打印一行轻量提示。
- 在 VoxFlow app / HUD 里显示队员列表。

不允许的变化：

- 不重写 Codex / Claude / CodeBuddy TUI。
- 不加常驻终端侧 roster。
- 不拦截用户输入去做 auto-yes / auto-retry。
- 不修改用户任务 prompt。
- 不自动批准权限。

### MCP 是自报身份，不是投喂通道

MCP 只能被 Codex / Claude / CodeBuddy 这类 MCP client 在自己的回合里主动调用。VoxFlow 不能通过 MCP “推送消息”给它们。因此 MCP 在本方案里的职责只有一个：让当前 Agent session 低频自报“我是谁、我在做什么、日志引用在哪”。

真正投喂仍然走 wrapper input channel。

### 用户确认过的信息优先

Router 里的目标识别信号按优先级排序：

```text
用户确认过的 alias
  >
准确命名的 active card label
  >
agent_id / cli / repo / cwd / branch
  >
MCP self_summary
  >
provider log/session refs
  >
模型候选重排
```

模型、MCP summary、日志索引都不能覆盖用户确认过的 alias。alias 的学习必须由用户确认触发。

## 用户体验

### 设置页

设置页采用单列竖向滚动，不做左右分栏。新增卡片标题为 **Vibe Coding 指挥中心**，小字说明：

```text
用语音把指令发给正在工作的终端 Agent
```

卡片里需要包含：

- 启用指挥中心：开启后复用现有语音输入快捷键进入 Vibe Coding 指挥 HUD。
- 注册终端命令：主按钮“注册命令”，辅助按钮“复制示例”。
- 打开方式提示：告诉用户在 Ghostty / iTerm2 / Terminal 中启动队员终端。
- 准确命名时直接发送：默认开启。
- 未命中队员名：默认“询问确认”，可选“取消发送 / 模型判断 / 默认发送到当前输入框”。
- MCP 自报身份：默认开启，说明“省 token：不做心跳，仅低频更新”。

设置页里的终端打开提示语固定为三行：

```text
vox flow codex
vox flow --claude
vox flow --codebuddy
```

实现上为了让提示语可复制可执行，需要提供一个 `vox` shim，使 `vox flow ...` 转发到 bundled `voxflow` helper。内部 canonical 命令仍是 `voxflow`，用于脚本、日志和调试；用户文案优先展示上面三行。

#### 注册命令按钮

“注册命令”不是让用户手动配置 MCP 或手动启动 daemon。它只负责让用户能在自己的终端里直接执行三行提示语。

建议行为：

- 检查 bundled `voxflow` helper 是否存在且可执行。
- 在用户目录创建 VoxFlow CLI bin 目录，例如 `~/Library/Application Support/VoxFlow/bin/`。
- 写入或更新 `vox` shim 和 `voxflow` shim。
- 检查该 bin 目录是否在当前 shell PATH。
- 如果已在 PATH，显示“已注册”。
- 如果不在 PATH，提供一键复制 shell 配置片段，并在设置页明确显示“需要重开终端后生效”。
- 不要求用户单独启动 `voxflow serve`、`voxflow mcp` 或其它常驻服务。

注册成功后，设置页展示三行可复制命令：

```text
vox flow codex
vox flow --claude
vox flow --codebuddy
```

如果用户要启动任意其它 Agent，设置页可以在折叠的“更多示例”里显示：

```text
voxflow run -- custom-agent --flag
```

### HUD

HUD 不修改终端 UI，也不在终端里常驻显示队员列表。它是 VoxFlow 自己的轻量浮层。

HUD 至少有这些状态：

- **监听中**：显示“正在听你说”，并实时预览当前可喊的队员列表。
- **准确命中**：展示识别到的原句、目标队员和发送内容；硬规则命中时显示“100% 直接发送”。
- **需要确认**：未准确命中队员名时展示候选队员。
- **已发送**：小 toast 告知发送到哪个队员。
- **发送失败**：小 toast 告知失败原因，例如“队员已退出”。

监听中 HUD 的队员列表来自 Router 的 active cards，每次开始语音指挥时实时读取，不依赖模型。

HUD 行为约束：

- HUD 不拿焦点。
- HUD 不要求用户切换当前 app。
- 高置信直发状态只短暂展示，不阻塞。
- 歧义确认状态才需要用户操作。
- 失败 toast 需要明确失败原因，但不暴露内部栈信息。
- HUD 中的队员名只来自 active cards 或用户确认过的 alias，不展示模型臆测名称。

### App 队员面板

除 HUD 外，VoxFlow app 应提供一个独立的 Vibe Coding 队员面板，用于查看当前注册的 Agent sessions、管理别名和查看调度记录。它不是终端侧 UI，也不放在设置页里承载日常状态管理。

队员面板展示：

- 队员名 / alias。
- CLI 类型，例如 codex / claude / codebuddy / custom。
- cwd / repo / branch。
- 状态：active / exited / stale。
- 最近投喂时间。
- self_summary 摘要和 phase。
- provider session refs 是否存在。

队员面板允许：

- 复制启动命令。
- 管理用户确认过的 alias。
- 清理 stale sessions。
- 查看最近 dispatch log。

队员面板不允许：

- 直接编辑 agent 输出。
- 直接改写 provider transcript。
- 让 agent 互相派活。

## 准确命名直发规则

只要 ASR 文本里提到了准确队员名，并且归一化后只命中一个 active card，就按硬规则 100% 执行发送，不调用模型、不二次确认。

允许的归一化只包括：

- 大小写等价。
- 全角 / 半角等价。
- 阿拉伯数字和中文数字等价，例如 `1` / `一`。
- 常见空白和标点差异。

不允许的归一化：

- 不做语义近似。
- 不把“前台”猜成“前端”。
- 不把“数据那边”猜成“数据库”。
- 不让模型把未确认别名写入 alias。

直发条件：

```text
ASR 文本
  ↓
解析 target_phrase / message
  ↓
归一化后准确命中唯一队员名或用户确认过的 alias
  ↓
message 非空
  ↓
直接 Router send submit=true
```

需要确认的情况：

- 同时命中多个队员。
- 只说了队员名但没有指令。
- 未命中任何队员名。
- 队员已退出或 input channel 不可用。
- 规则解析结果和模型 fallback 冲突。

示例：

| ASR 文本 | Active cards | 结果 |
| --- | --- | --- |
| `前端，把按钮改成白色` | 前端、后端、数据库 | 直发给前端 |
| `frontend，把按钮改成白色` | frontend、backend、database | 直发给 frontend |
| `一号，把按钮改白` | 一号、二号 | 直发给一号；`1号` 等价 |
| `把按钮改成白色` | 前端、后端、数据库 | HUD 询问确认 |
| `前端后端看一下这个问题` | 前端、后端 | HUD 询问确认，不直发 |
| `前台，把按钮改白` | 前端 | 不直发，除非用户确认过“前台”是前端 alias |

## 总体架构

```text
Ghostty / iTerm2 / Terminal
  ↓
vox flow codex / vox flow --claude / vox flow --codebuddy
  ↓
vox shim
  ↓
voxflow helper
  ↓
Transparent PTY Wrapper
  ↓
原始 Codex / Claude / CodeBuddy / 任意 Agent CLI

旁路：
VoxFlow 语音
  ↓
ASR
  ↓
IntentParser
  ↓
Agent Router Core
  ↓
TargetResolver
  ↓
send_message(agent_id, message, submit: true)
  ↓
wrapper 输入通道
```

## Rust Helper

最终产物是一个 Rust helper binary，canonical 命令名为 `voxflow`。VoxFlow.app 产品化后应把 helper 和 `vox` shim 打包进 app bundle，并由 app 自动注册、启动和管理。

用户可见打开方式：

```bash
vox flow codex
vox flow --claude
vox flow --codebuddy
```

内部和开发调试命令：

```bash
voxflow codex
voxflow claude
voxflow codebuddy
voxflow run -- custom-agent --flag
voxflow list
voxflow send <target> <message>
voxflow resolve <target>
voxflow serve
voxflow mcp
```

`list/send/resolve/serve/mcp/run` 是 `voxflow` 内置子命令；其他首词默认当 agent 命令。复杂命令或与内置子命令冲突时使用 `voxflow run -- ...`。

helper 内部包含：

```text
pty.rs       透明 PTY wrapper
session.rs   Agent session card 与 registry
input.rs     FIFO / Unix socket 输入通道
router.rs    list / resolve / send / learn_alias / log
ipc.rs       本地 socket API
mcp.rs       MCP facade
shim.rs      vox flow 用户命令转发
```

P1 只实现最小子集：`run/list/send` 和 `vox flow ...` 转发，并保证 wrapper 透明。

默认启动会注入一段极短的 Agent Dispatch 身份提示，让支持 MCP 的 agent 低频调用 `update_self_summary` 自报工作摘要。该提示不得修改用户任务、不得自动批准权限、不得引导 agent 互相派活；它只说明“如可用，低频更新自己的队员身份摘要”。

### yes-agent / agent-yes 借鉴清单

Rust wrapper 应明确借鉴本地 review 过的 yes-agent / agent-yes Rust 实现，但目标不是 fork 它的产品，而是抽取一层 “transparent PTY + input channel + registry” 内核。

本地参考目录：

```text
/tmp/agent-yes-review/rs/
```

重点参考文件：

| agent-yes 文件 | 可借鉴内容 | VoxFlow 改造目标 |
| --- | --- | --- |
| `rs/src/pty_spawner.rs` | `portable_pty` spawn、terminal size、resize、reader/writer、process group cleanup | 改造成 `pty.rs`，保留透明 PTY 行为和 kill process group，去掉 agent-yes config/prompt 依赖 |
| `rs/src/fifo.rs` | Unix FIFO / Windows named pipe 思路、FIFO RDWR 保活、0600 权限、cleanup | 改造成 `input.rs`，路径迁移到 VoxFlow AgentRouter 目录，协议只接收待发送文本 |
| `rs/src/pid_store.rs` | JSONL registry、跨进程锁、stale cleanup、status update | 改造成 `session.rs`，字段从 pid record 扩展为 Agent card，增加 `agent_id`、cwd/repo/branch、provider refs |
| `rs/src/messaging.rs` | 外部命令向指定会话发送消息的 CLI plumbing | 改造成 `router.rs` / `send`，只负责写入目标 input channel 并提交 Enter |
| `rs/src/reaper.rs` | 进程清理和 orphan 处理思路 | 合并到 wrapper lifecycle，确保 child/process group/FIFO/registry 清理 |
| `rs/src/cli.rs` | CLI 子命令结构 | 参考命令组织，但命令名和语义换成 `voxflow` / `vox flow` |
| `rs/tests/integration_tests.rs`、`rs/tests/test_ctrl_c.sh` | PTY、Ctrl-C、send、cleanup 的测试思路 | 改写成 fake agent / echo agent 自动化 smoke，不依赖真实 Codex/Claude/CodeBuddy |

可直接搬运或近似搬运的技术点：

- `portable_pty::{native_pty_system, CommandBuilder, PtySize}` 作为 PTY 基础。
- `ioctl(TIOCGWINSZ)` 读取 terminal size。
- SIGWINCH / resize 同步思路。
- PTY writer 用 `Arc<Mutex<Box<dyn Write + Send>>>` 或等价封装。
- child process group cleanup，避免子进程泄漏。
- FIFO 使用 `mkfifo` + `0600` 权限。
- Unix FIFO 用 RDWR 保持读端不因外部 writer 关闭而 EOF。
- registry 写入时加跨进程锁，避免多个 wrapper 同时启动导致记录丢失。
- stale session cleanup 用 process alive 检测二次确认。

必须重写的 VoxFlow 差异：

- home 目录从 `~/.agent-yes` 改成 `~/Library/Application Support/VoxFlow/AgentRouter/`。
- `PidRecord` 改成 `AgentSessionCard`。
- `pid` 不能作为路由主键，必须新增 `agent_id`。
- `fifo_file` / input channel 要挂到 `agent_id`，不是只挂 pid。
- `status` 只保留 `active / exited / stale`；暂不引入 idle/busy。
- `send` 只做“写入文本 + Enter”，不做 auto-yes、auto-retry 或 prompt pattern。
- CLI 命令改成 `voxflow` canonical 和 `vox flow ...` 用户 shim。
- 日志只保存 dispatch log、summary 和 provider refs，不复制 agent 输出全文。

必须删除或不引入的 agent-yes 逻辑：

- auto-yes。
- auto-retry。
- prompt pattern 自动匹配。
- Ctrl+Y 审批逻辑。
- `/auto` 模式。
- swarm / p2p / remote / web console。
- Docker / cloud / pairing / desktop remote。
- 自动安装或修改 Claude/Codex 配置的额外逻辑。
- 任何会修改用户任务语义的 prompt 注入。
- 任何让 agent 互相派活的能力。

最终实现应是 “Agent-Yes transparent core lite”，不是 agent-yes 的 fork 产品。

实现时建议顺序：

1. 先读 `pty_spawner.rs`，抽出最小 PTY spawn / resize / writer / cleanup。
2. 再读 `fifo.rs`，抽出 input channel 生命周期。
3. 再读 `pid_store.rs`，把 JSONL registry 改造成 Agent card registry。
4. 最后参考 `messaging.rs` 和 `cli.rs` 接出 `list/send/run`。
5. 每一步都用 fake agent 做自动化验证，不接真实 CLI 做硬验收。

### wrapper 风险

wrapper 的主要风险和处理方式：

| 风险 | 处理 |
| --- | --- |
| TUI 行为被破坏 | 使用真实 PTY；保留 raw mode、颜色、resize、Ctrl-C/Ctrl-D |
| child 退出后 registry 残留 | wrapper 退出清理；Router list 时二次 stale 检测 |
| send 写入时 child 不在输入态 | P1/P2 不判断 idle/busy；只保证写入指定 PTY，后续再做 CLI-specific busy |
| 误投到普通 shell | 只投喂 wrapper 注册过的 Agent session；普通 shell 不注册不投喂 |
| 多 session 同名 | 准确命名仍需唯一；多命中进入 HUD 确认 |
| app 退出后 helper 残留 | app 管理 router；session wrapper 可随终端独立存在，但 stale 要可清理 |
| 权限/登录态问题 | 不作为自动化硬验收，只做手工 smoke |

## Agent Session Card

每个 wrapper 启动后注册一张 session card。

建议字段：

```json
{
  "agent_id": "uuid",
  "wrapper_pid": 12345,
  "child_pid": 12346,
  "cli": "codex",
  "command": ["codex"],
  "cwd": "/Users/counter/workspace/project",
  "repo_root": "/Users/counter/workspace/project",
  "repo_name": "project",
  "branch": "feature/button-color",
  "terminal": "Ghostty",
  "tty": "/dev/ttys007",
  "input_channel": "...",
  "status": "active",
  "log_ref": "...",
  "self_summary": {
    "label": "前端",
    "summary": "处理页面按钮样式",
    "topics": ["前端", "按钮", "页面样式"],
    "phase": "editing",
    "expires_at": "..."
  },
  "provider_session_refs": [
    {
      "provider": "codex",
      "kind": "session_id",
      "value": "..."
    }
  ],
  "started_at": "...",
  "updated_at": "..."
}
```

`agent_id` 是 VoxFlow Router 拥有的路由身份，不能用 pid 替代，也不能直接等同于 Codex/Claude 自己的会话 ID。provider session ID 可能启动后才出现，可能因 resume/fork/clear 改变，也可能不同 CLI 暴露方式不同。因此设计上使用一对多映射：

```text
Agent session agent_id
  ├─ wrapper pid / child pid
  ├─ input channel
  ├─ aliases
  └─ provider_session_refs[]
       ├─ codex session id
       ├─ claude session id
       └─ codebuddy transcript/log ref
```

Router 用 `agent_id` 做投喂目标，用 provider session reference 做恢复、日志索引、每日统计和诊断。

### card 更新来源

Agent card 由多路信号合成，但每种信号权限不同：

| 来源 | 写入内容 | 可否覆盖 alias | 频率 |
| --- | --- | --- | --- |
| wrapper 启动 | pid、cwd、repo、branch、cli、tty、input channel | 否 | 启动/退出 |
| Router dispatch | 最近投喂、状态、失败原因 | 否 | 每次 dispatch |
| 用户确认 | alias、展示名 | 是，用户数据最高优先级 | 用户操作 |
| MCP summary | label、summary、topics、phase、TTL | 否 | 低频 |
| provider indexer | session id、transcript/log ref | 否 | 低频/按需 |

active cards 必须在每次语音 dispatch 前实时读取，不能使用长期缓存做最终决策。

## Agent Router Core

Router Core 负责把“会话”变成“可被投喂的队员”。

职责：

- `list_agents`：列出当前可用 Agent session。
- `resolve_agent`：把用户说的目标解析到某个 Agent session。
- `send_message`：向目标 session 写入指令，并按需提交。
- `learn_alias`：用户确认后记住“目标短语 -> agent_id”。
- `append_dispatch_log`：记录投喂日志。
- `record_summary_ref`：保存 agent 输出摘要或日志引用。

P1/P2 的 resolver 先不用模型。匹配信号包括：

- 准确队员名。
- 用户确认过的 alias。
- `agent_id`。
- CLI 名称。
- repo 名 / cwd / branch。
- 最近投喂内容。
- 最近活跃 session。

用户确认过的 alias 是用户维护数据。`update_self_summary`、日志索引、模型 resolver 都不能覆盖用户确认过的 alias，只能提供候选或辅助匹配信号。

### TargetResolver 分层

Resolver 每次 dispatch 都运行，但不是每次都调用模型。

```text
输入：ASR 文本 + active cards
  ↓
IntentParser 保守拆 target_phrase / message
  ↓
ExactNameResolver：准确命名 / alias 命中
  ↓
RuleResolver：agent_id、cli、repo、cwd、branch、recent target
  ↓
如果唯一且高置信：direct-send
  ↓
如果不唯一：返回 candidates 给 HUD
  ↓
如果用户设置允许：ModelResolver 只做结构化和候选重排
  ↓
仍不确定：不发送
```

ModelResolver 输入必须是受限结构：

```json
{
  "utterance": "前端，把按钮改成白色",
  "parsed_target_phrase": "前端",
  "parsed_message": "把按钮改成白色",
  "candidate_agents": [
    {
      "agent_id": "...",
      "display_name": "前端",
      "cli": "codex",
      "repo_name": "web",
      "branch": "feature/button",
      "user_aliases": ["前端"],
      "summary": "处理页面按钮样式"
    }
  ]
}
```

ModelResolver 输出只能是候选排序和置信度：

```json
{
  "target_agent_id": "...",
  "message": "把按钮改成白色",
  "confidence": 0.82,
  "reason": "utterance mentions exact alias"
}
```

禁止模型输出直接触发 alias 学习。禁止模型绕过 Router 发送。

## 存储

产品化后存储目录建议为：

```text
~/Library/Application Support/VoxFlow/AgentRouter/
```

建议布局：

```text
sessions/
aliases.json
dispatch-log.jsonl
summaries.jsonl
fifo/
router.sock
```

保存策略：

- 投喂日志默认保存全文 30 天，包含目标、消息、提交状态和错误；设置里可清空或关闭。
- 用户确认过的 alias 必须持久化。
- agent 输出原文不由 Router 长期复制保存。
- Router 保存 agent 日志引用、摘要和统计信息。
- 后续每日统计基于 dispatch log、session metrics、summary 和 log_ref 生成。
- 允许索引 Codex、Claude、CodeBuddy 等 CLI 的本地历史/日志引用，但默认只读取 session id、project、timestamp、日志路径或 transcript 引用，不复制完整输出。
- P1/P2 不做持久 output ring buffer；后续若为 resolver 使用短期输出提示，只保留小型内存 ring buffer，不落盘。

### 隐私边界

- dispatch log 保存的是用户发出的指令，不是 agent 输出全文。
- provider indexer 只保存引用，不复制完整 transcript。
- 用户可在设置页清空或关闭调度记录。
- clipboard 不参与 Vibe Coding 指挥中心流程。
- 如果后续需要每日统计，基于 dispatch log、summary、provider refs 和 session metrics 生成。

## 状态

P1/P2 只需要：

- `active`：wrapper 仍在运行。
- `exited`：会话正常退出。
- `stale`：registry 中存在但进程已不可用。

`idle/busy` 暂不做。它表示 agent 是否正在等待输入，但需要 CLI-specific 状态识别，后续再考虑。

## VoxFlow 语音层

语音层放到 P3，不进入 P1/P2。P3 由 VoxFlow.app 自动调用 bundled `voxflow` helper / Router socket；用户不需要手动启动 router 或配置 MCP。

流程：

```text
按住 Vibe Coding 指挥中心热键
  ↓
监听中 HUD 读取 active cards，显示：前端 / 后端 / 数据库
  ↓
说：“前端，把按钮改成白色”
  ↓
ASR 得到文本
  ↓
IntentParser 拆出 target 和 message
  ↓
RuleResolver 准确命中“前端”
  ↓
HUD 展示 100% 直接发送
  ↓
Router send submit=true
```

Agent Dispatch 应进入 `VoiceTaskMode.agentDispatch`，作为新的语音任务模式记录历史、失败和统计。

### IntentParser 与 Resolver

IntentParser 只负责把 ASR 文本保守拆成 `target_phrase` 和 `message`，不负责最终决定发送目标。第一版支持明确句式：

```text
<目标>，<消息>
<目标>：<消息>
给<目标>说<消息>
让<目标><消息>
叫<目标><消息>
```

Resolver 每次 Vibe Coding 指挥中心语音调度都会运行，但模型不是每次调用：

```text
RuleResolver 每次运行
  ↓
准确命名唯一队员：100% 直接发送
  ↓
规则未命中或不唯一：HUD 展示候选
  ↓
用户设置允许时：调用模型 resolver 做候选重排
  ↓
仍不确定：提示找不到明确队员
```

模型 resolver 只能做 target/message 结构化和候选重排，不能直接发送，也不能学习 alias。建议阈值：

```text
LLM confidence >= 0.85 且候选唯一：HUD 展示可取消后发送
0.60 - 0.85：HUD 展示候选等待确认
< 0.60：提示找不到明确队员
```

首次 alias 学习必须来自用户确认。

### App 接入点

现有 VoxFlow 分层里，建议接入点如下：

| 模块 | 改动 |
| --- | --- |
| `Sources/VoxFlowDomain/Voice/VoiceTaskMode.swift` | 增加 `agentDispatch` |
| `Sources/VoxFlowDomain/Voice/VoiceAction.swift` | 增加对应 action |
| `Sources/VoxFlowApp/FeatureBridges/VoiceTaskCoordinator.swift` | 增加 Agent Dispatch 录音入口和任务记录 |
| `Sources/VoxFlowApp/HotKey/HotKeyRoutingPolicy.swift` | 增加第三类快捷键路由 |
| `Sources/VoxFlowApp/ViewModels/SettingsViewModel.swift` | 增加设置项、默认值和文案 |
| `Sources/VoxFlowApp/Views/SettingsRootView.swift` | 增加 Vibe Coding 指挥中心设置卡片 |
| 新增 Router client | 通过 local socket 调 `list/resolve/send` |
| 新增 HUD presentation model | 管理 listening / exact / ambiguous / success / failure 状态 |
| `Tests/VoxFlowAppTests/...` | 增加 parser、settings、HUD、VoiceTask 测试 |

实现时必须保持现有 `Agent Compose / 帮我说` 的 ADR-011：不注入、不回车、不自动发送。Vibe Coding 指挥中心是新的独立模式，不能改变“帮我说”。

## MCP Facade

MCP 是 Agent session 的自报身份通道，不是终端输入机制，也不是多 agent 调度系统。真正投喂仍由 VoxFlow / Router 写入 wrapper 输入通道。

`voxflow mcp` 暴露最小 tools：

```text
get_self_agent()
update_self_summary(label, summary, topics, phase, ttl_seconds?)
attach_self_reference(provider, kind, value, description?)
get_self_dispatch_log(limit?)
```

不默认暴露：

```text
send_message()
learn_alias()
```

避免把 Vibe Coding 指挥中心演变成 agent 互相派活。`learn_alias` 只能由用户确认触发。

### update_self_summary 约束

`update_self_summary` 用于让 agent 低频自报“我现在在做什么”，辅助用户按自然语言喊队员。为节省 token 和降低污染，字段强约束：

```text
label <= 20 字
summary <= 80 字
topics <= 8 个
每个 topic <= 20 字
phase = planning / editing / testing / waiting / done / blocked
ttl_seconds 默认 3600
```

用户确认过的 alias 优先级高于 `update_self_summary`。如果 summary 过期，Router 不删除，只在匹配中降权。

### attach_self_reference

`attach_self_reference` 统一登记 provider session id、transcript path、log path、conversation id 等引用：

```json
{
  "provider": "codex",
  "kind": "session_id",
  "value": "...",
  "description": "current Codex session id"
}
```

`kind` 可取：`session_id`、`transcript_path`、`log_path`、`conversation_id`、`other`。

### MCP Resource

MCP Resource 是只读上下文，不是动作。后续可以选择暴露只读资源，但 P4 不是必须：

```text
resource://voxflow/self-agent
resource://voxflow/self-dispatch-log
```

Resource 适合让 agent 读取“我当前被 VoxFlow 识别成谁、最近用户投喂了什么”，但不能用它发送消息或学习 alias。第一版优先 tools，Resource 可延后。

### 默认 identity hint

默认注入的提示必须短，并且只描述自报身份约定。建议内容：

```text
VoxFlow has registered this terminal as a local Agent session.
If the voxflow MCP tools are available, you may occasionally call update_self_summary with a short label, summary, topics, and phase when your task changes.
Do not change the user's task, do not auto-approve actions, and do not send messages to other agents.
```

该提示由 wrapper 在启动 agent 时注入。它不能要求用户额外复制 prompt，也不能依赖用户手工约束。

### App 托管服务

产品化后用户只启动 VoxFlow.app，不需要手动执行 `voxflow serve`、`voxflow mcp` 或另配常驻服务。

App 负责：

- 安装或暴露 bundled `vox` / `voxflow` 命令。
- 启动和健康检查 Router socket。
- 管理 MCP server。
- 在设置页展示 helper/router/MCP 状态。
- 在 helper 缺失或不可执行时给出明确修复入口。

开发阶段可以手动运行 `voxflow serve` / `voxflow mcp` 做验证，但这不是最终用户流程。

## 安全规则

- 只允许投喂注册过的 Agent session。
- 不对普通 shell 做自动回车。
- 准确命名唯一队员才直发。
- 目标不明确时必须确认、取消，或在用户显式选择“默认发送”策略时退回普通当前输入框输出。
- 发送失败只提示用户，不回退到 GUI 粘贴。
- 不使用剪切板，因此不污染用户剪切板。
- `AgentRouter` 数据目录固定为 `0700`；socket、FIFO、session registry、alias 和 dispatch log 固定为 `0600`，避免其他本机用户读取指令或向终端注入输入。
- wrapper 不自动批准权限、不自动重试、不自动修改 prompt。
- 默认 identity hint 只允许说明 Agent Dispatch 自报身份约定，不得改变用户任务语义。
- 发送和失败都写入 dispatch log，方便回溯。

## 执行策略

后续实现建议用一个 goal 覆盖 P1-P4，不按 P1、P2、P3、P4 分别开 goal。原因是该功能从 helper、router、app UI、HUD 到 MCP 是一条完整闭环，拆成多个 goal 容易在中间状态反复验收、反复解释和消耗 token。

执行约束：

- P1-P4 一次性作为完整目标推进，但内部按下面任务列表小步实现。
- 不要一步一提交；全部功能完成、文档和验证收口后再做一次最终提交。
- 不要每完成一个小任务就跑全量验收；只在一个大功能点完成后跑对应单测或轻量验证。
- TDD 以“大功能点”为单位：先补该功能点的失败测试，再做最小实现，最后在该功能点完成后运行相关单测。
- 只有在跨模块集成完成后，才运行最终总验收。
- 如果某项验收失败，先判断是否与本次功能相关；不要为了无关既有失败反复尝试。
- 自动化验收最多重试一次同类失败；第二次仍失败时记录阻塞原因、命令、错误摘要和下一步建议，避免无限消耗 token。
- 真实 Codex / Claude / CodeBuddy 体验只做 manual smoke，不作为 agent 自动验收阻塞项。
- 自动化硬验收只依赖 fake agent / echo agent，不依赖真实 CLI 登录态、TUI 行为、权限弹窗或外部服务状态。
- 测试文件、测试 suite 和测试方法统一使用行为命名，不使用 `P1`、`P2`、`P3`、`P4` 作为前缀；分期只用于文档组织，不进入测试名称。

## 分期任务

P1-P4 是产品分层，不是交付拆分。实际实现时按顺序推进，但最终以完整 Vibe Coding 指挥中心闭环作为一次交付。

### P1：透明 Rust Wrapper

- [x] 建立 Rust helper crate / target，产物 canonical 名为 `voxflow`。
- [x] 阅读 `/tmp/agent-yes-review/rs/src/pty_spawner.rs`，抽取 PTY spawn / resize / writer / process group cleanup 设计。
- [x] 阅读 `/tmp/agent-yes-review/rs/src/fifo.rs`，抽取 FIFO / named pipe input channel 生命周期设计。
- [x] 阅读 `/tmp/agent-yes-review/rs/src/pid_store.rs`，抽取 JSONL registry、跨进程锁和 stale cleanup 设计。
- [x] 阅读 `/tmp/agent-yes-review/rs/src/messaging.rs` 和 `rs/src/cli.rs`，抽取 `send/list/run` 命令组织方式。
- [x] 建立 VoxFlow 自己的 `pty.rs`、`input.rs`、`session.rs`、`router.rs`、`ipc.rs`，不要直接保留 agent-yes 产品语义。
- [x] 增加 `vox` shim，支持 `vox flow ...` 用户命令。
- [x] 实现 `voxflow <command>` 启动任意 CLI agent。
- [x] 实现 `voxflow run -- <command...>`，处理内置子命令冲突。
- [x] 实现 `vox flow codex` 转发到 `voxflow codex`。
- [x] 实现 `vox flow --claude` 转发到 `voxflow claude`。
- [x] 实现 `vox flow --codebuddy` 转发到 `voxflow codebuddy`。
- [x] 使用 PTY 启动 child process，保持 TTY 行为、颜色、窗口尺寸和 Ctrl-C/Ctrl-D 等交互。
- [x] 监听 terminal resize，并同步到 child PTY。
- [x] wrapper 退出时清理 child process、input channel 和 session registry。
- [x] 为每个会话生成 `agent_id`，登记 wrapper pid、child pid、cwd、repo、branch、cli、tty、terminal、started_at。
- [x] 实现 session registry 文件布局和 stale session 清理。
- [x] 实现 wrapper 输入通道，支持写入文本并自动提交 Enter。
- [x] 实现 `voxflow list`，输出 active / exited / stale session。
- [x] 实现 `voxflow send <target> <message>`，支持按 agent_id、cli、alias 候选发送。
- [x] 实现启动 banner，显示当前 `agent_id`、命令、cwd 和可喊名称。
- [x] 实现 window title 更新或状态变化提示，但不改终端 TUI 内容。
- [x] 增加 wrapper 单元测试：命令解析、shim 转发、registry 生命周期、stale 清理、send 写入。
- [x] 增加 wrapper smoke：用 fake agent 验证 `list/send/auto-enter/exit cleanup`。

### P2：Router Core

- [x] 定义 Agent card 数据结构和 JSON/schema 版本。
- [x] 实现 active cards 实时查询 API。
- [x] 实现 `resolve_agent` 的规则 resolver。
- [x] 实现准确命名唯一队员的 100% direct-send 规则。
- [x] 实现归一化：大小写、全半角、数字 `1/一`、常见空白和标点。
- [x] 实现未命中、多命中、空 message、session 不可用的结构化结果。
- [x] 实现 alias 存储和 `learn_alias`，仅允许用户确认后写入。
- [x] 确保用户确认过的 alias 优先级高于 summary、model 和 log signal。
- [x] 实现 dispatch log：目标、消息、提交状态、失败原因、时间、provider refs。
- [x] 实现 summary/log_ref 存储，但不复制 agent 输出全文。
- [x] 实现 provider session refs：`session_id`、`transcript_path`、`log_path`、`conversation_id`、`other`。
- [x] 实现 local socket API：`list_agents`、`resolve_agent`、`send_message`、`learn_alias`、`append_dispatch_log`。
- [x] 实现 failure reason enum，覆盖 exited、stale、input channel missing、ambiguous、not found、write failed。
- [x] 实现 `voxflow resolve <target>` 调试命令。
- [x] 实现 `voxflow serve`，供 VoxFlow.app 管理 router/socket。
- [x] 增加 Router 单元测试：准确命名、归一化、多命中、alias 优先级、dispatch log、failure reason。
- [x] 增加 Router socket 集成测试：list/resolve/send 全链路。

### P3：VoxFlow 语音集成

- [x] 将 Rust helper 和 `vox` shim 接入 app bundle 打包。
- [x] 实现 VoxFlow.app 自动启动 / 健康检查 / 重启 router，不要求用户另开常驻服务。
- [x] 新增 `VoiceTaskMode.agentDispatch`。
- [x] 新增对应 `VoiceAction.agentDispatch` 或等价 action。
- [x] 新增 Vibe Coding 指挥中心开关，开启后复用现有语音输入快捷键。
- [x] 实现 Agent Dispatch 录音入口，不影响“语音转录”和“帮我说”。
- [x] 实现 IntentParser：支持 `<目标>，<消息>`、`<目标>：<消息>`、`给<目标>说<消息>`、`让<目标><消息>`、`叫<目标><消息>`。
- [x] 在开始监听时实时读取 active cards，供 HUD 预览。
- [x] 实现监听中 HUD：显示当前可喊队员列表。
- [x] 实现准确命中 HUD：显示目标、消息、`100% 直接发送`。
- [x] 实现歧义确认 HUD：显示候选队员和选择入口。
- [x] 实现发送成功 toast。
- [x] 实现发送失败 toast。
- [x] 实现 Router socket client，调用 `resolve_agent` 和 `send_message`。
- [x] 实现模型 resolver fallback，只在规则低置信度且用户设置允许时调用。
- [x] 确保准确命名唯一队员时不调用模型。
- [x] 实现设置页单列竖向滚动的 “Vibe Coding 指挥中心” 卡片。
- [x] 设置页显示三行提示语：`vox flow codex`、`vox flow --claude`、`vox flow --codebuddy`。
- [x] 设置页提供“注册命令”和“复制示例”入口。
- [x] 实现“注册命令”按钮：检查 helper、写入用户 CLI bin 目录、检查 PATH、提示是否需要重开终端。
- [x] 设置页展示注册命令、发送策略和 MCP 自报身份开关。
- [x] 实现独立 Vibe Coding 队员面板：展示 active/exited/stale sessions、cwd/repo/branch、summary、最近投喂和 provider refs。
- [x] 队员面板支持复制启动命令、管理 alias、清理 stale sessions、查看最近 dispatch log。
- [x] 记录 agentDispatch 历史、失败、统计和调度日志引用。
- [x] 增加 App 集成单元测试：IntentParser、direct-send 决策、设置项默认值、VoiceTask 记录。
- [x] 增加 UI/presentation 测试：设置页文案、注册命令状态、HUD 状态模型、队员面板状态、候选确认状态。

### P4：MCP 自报身份增强

- [x] 实现 `voxflow mcp` stdio MCP server。
- [x] 暴露 `get_self_agent()`。
- [x] 暴露 `update_self_summary(label, summary, topics, phase, ttl_seconds?)`。
- [x] 暴露 `attach_self_reference(provider, kind, value, description?)`。
- [x] 暴露 `get_self_dispatch_log(limit?)`。
- [x] 不默认暴露 `send_message()`。
- [x] 不默认暴露 `learn_alias()`。
- [x] 实现 summary 字段长度和 enum 校验。
- [x] 实现 summary TTL 和过期降权。
- [x] 实现 default identity hint 注入，提示 agent 低频自报身份。
- [x] 确保 identity hint 不修改用户任务、不诱导自动审批、不诱导 agent 互相派活。
- [x] VoxFlow.app 自动管理 MCP server 或 helper，不要求用户单独运行。
- [x] 将 MCP 开关接入设置页。
- [x] 增加 MCP 单元测试：tool schema、字段校验、TTL、alias 优先级。
- [x] 增加 MCP smoke：模拟 MCP client 调用 self-report tools 并更新 Agent card。

## 验收标准

验收只在大功能点或最终集成时执行，不在每个小任务完成后重复执行。最终总体验收前，先运行对应单元测试；若单元测试已明确失败，不继续做真实终端 smoke 以免浪费 token。

验收分三层：

- **自动化硬验收**：只依赖 fake agent / echo agent、Router socket、HUD 状态模型和设置页 presentation，不依赖真实 Codex / Claude / CodeBuddy。
- **真实 CLI 手工 smoke**：Codex / Claude / CodeBuddy 只检查能启动、不明显破坏原始 TUI、wrapper banner/list 记录正常；失败或无法验证时记录原因，不阻塞自动化验收。
- **用户确认项**：原始体验是否可接受、真实语音投喂是否符合直觉、HUD 是否打扰工作流，由用户最终确认。

### P1 验收

- 自动化：`voxflow run -- <fake-agent>` 能启动 fake agent。
- 自动化：`voxflow list` 能看到 fake agent 的 active / exited / stale session。
- 自动化：`voxflow send <target> <message>` 能写入 fake agent 并自动回车。
- 自动化：发送失败时返回结构化错误，不使用剪切板、不尝试 GUI 粘贴。
- 手工 smoke：`vox flow codex` 能启动 Codex，原始 TUI 交互体验不明显变化。
- 手工 smoke：`vox flow --claude` 能启动 Claude，原始 TUI 交互体验不明显变化。
- 手工 smoke：`vox flow --codebuddy` 能启动 CodeBuddy，原始 TUI 交互体验不明显变化。

### P2 验收

- Router 每次 dispatch 前能实时读取 active cards。
- 准确命名唯一队员时，resolver 返回 100% direct-send。
- 未命中或多命中时，resolver 返回候选或 ambiguous，不自动发送。
- 用户确认过的 alias 会持久化，并且优先级高于 summary/model/log signal。
- dispatch log 默认记录发送指令、目标、提交状态、失败原因和时间。
- Router 不长期复制保存 agent 输出全文，只保存引用、摘要和统计字段。

### P3 验收

- 设置页采用单列竖向滚动，新增 “Vibe Coding 指挥中心” 卡片。
- 设置页显示三行提示语：`vox flow codex`、`vox flow --claude`、`vox flow --codebuddy`。
- 设置页有“注册命令”和“复制示例”入口。
- “注册命令”能写入用户 CLI bin 目录并正确提示 PATH 状态。
- App 队员面板能展示 active/exited/stale sessions 和最近 dispatch 信息。
- 监听中 HUD 能预览 active cards：例如“前端 / 后端 / 数据库”。
- 用户说“前端，把按钮改成白色”时，归一化后准确命中“前端”，不调用模型，直接发送。
- 用户说“把按钮改成白色”时，HUD 展示候选确认，不直接发送。
- 发送成功和失败都有 HUD toast。
- `VoiceTaskMode.agentDispatch` 能记录历史、失败和统计。

### P4 验收

- 自动化：模拟 MCP client 能看到 `voxflow mcp` 暴露的自报身份 tools。
- 自动化：模拟 MCP client 可调用 `update_self_summary` 更新当前工作摘要。
- 自动化：`attach_self_reference` 可登记 provider session id / transcript path / log path。
- 自动化：MCP tools 不暴露默认跨 agent 发送能力。
- 自动化：VoxFlow.app 能自动管理 MCP，不要求用户手动启动独立服务。
- 手工 smoke：Codex / Claude / CodeBuddy 接入 MCP 后能看到自报身份 tools；该项不作为自动化阻塞项。
