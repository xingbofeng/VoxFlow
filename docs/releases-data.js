window.VOXFLOW_RELEASES = [
  {
    "tag_name": "v1.14.0",
    "name": "VoxFlow 1.14.0",
    "body": "# VoxFlow 1.14.0\n\n## 更新摘要\n\n- 扩展本地 Agent Provider：除了 Codex，现在可以检测并选择 Opencode、Claude Code、CodeBuddy 和 Pi Agent，并为 Agent Compose 选择对应模型。\n- 纠错链路更保守可靠：新增普通听写专用的 LLM 纠错保护，避免模型把口述内容扩写成回答、丢掉 URL / 版本号 / 路径等关键 token。\n- 词汇表与热词策略继续完善：热词只维护正确写法，Provider 热词能力、命中统计和删除屏蔽表更清晰，减少误学习和重复加入。\n- 设置页重新整理为语音、文本、截图、划词助手、智能工作台、模型和通用入口，模型页也拆出本地 Agent 与自定义 LLM Provider。\n\n## 细节\n\n- 功能：新增通用本地 Agent CLI 适配层，支持检测 CLI 可用性、拉取模型列表、执行本地 Agent runtime，并记录输出、失败原因和生成 artifact。\n- 功能：LLM Provider 设置新增本地 Agent Provider 区域，可分别启用 Opencode、Claude Code、CodeBuddy、Pi Agent 和 Codex，并同步到 Agent Compose 使用。\n- 功能：普通听写 LLM 纠错新增 refinement guard 诊断，首页详情可展示接受/拒绝原因、相似度、fallback 来源和受保护 token 类型。\n- 功能：热词、文本替换和 ASR Provider 热词能力矩阵补齐领域定义，Groq ASR 可复用已有 Groq LLM Provider 的 API Key。\n- 修复：Agent Dispatch 复用文本处理链路时可显式跳过普通听写纠错保护，避免任务指令被当成普通听写结果误判。\n- 修复：本地模型流式预览和空闲资源释放改为读取设置仓库，Qwen3 本地模型可在空闲时释放共享缓存。\n- 体验：设置页侧边栏和模型页重新分组，减少旧版设置中模型、纠错、快捷键和隐私入口交叉分散的问题。\n- 体验：README、官网、应用内更新元数据和静态最近版本 fallback 同步到 1.14.0。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.14.0\n- `CFBundleVersion`：25\n- DMG：`VoxFlow-1.14.0-macOS.dmg`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.14.0",
    "published_at": "2026-07-03T00:00:00Z"
  },
  {
    "tag_name": "v1.13.0",
    "name": "VoxFlow 1.13.0",
    "body": "# VoxFlow 1.13.0\n\n## 更新摘要\n\n- 新增 Codex Runtime Agent 工作流：语音指令可以直接交给本机 Codex 执行，支持页面总结、文件生成和过程事件回写。\n- 升级 LLM / Agent Provider 设置：Codex Runtime 可检测、选择模型，并可作为文本纠错和 Agent Compose 的执行提供方。\n- 改进工作台资产与任务详情：历史记录、Agent 执行轨迹、诊断导出和 HUD 状态展示更完整。\n- 官网迁移到 `mashangxie.app`，README、官网元数据和应用内更新检测地址同步更新。\n\n## 细节\n\n- 功能：接入 Codex app-server runtime，新增受控工作区、屏幕上下文截图、事件归一化、token 用量和失败原因记录。\n- 功能：Agent Dispatch / Agent Compose 会保留文本处理 trace，任务详情页可展示 LLM 修正、Agent 输出和执行轨迹。\n- 功能：LLM Provider 设置新增 Codex Runtime 检测、模型列表刷新、启用后可作为默认 LLM Provider 的能力。\n- 修复：Agent Dispatch 确认前补齐文本处理流程，避免发给助手的内容绕过纠错和上下文处理。\n- 体验：首页资产列表、历史详情、HUD 浮层和多语言文案更新，便于区分语音、截图、录屏、剪贴板与 Agent 资产。\n- 体验：官网 canonical / OG / 更新检测从 GitHub Pages 切换到 `https://mashangxie.app/`。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.13.0\n- `CFBundleVersion`：24\n- DMG：`VoxFlow-1.13.0-macOS.dmg`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.13.0",
    "published_at": "2026-07-01T17:36:38Z"
  },
  {
    "tag_name": "v1.12.1",
    "name": "VoxFlow 1.12.1",
    "body": "# VoxFlow 1.12.1\n\n## 更新摘要\n\n- 新增火山云豆包流式语音识别支持，可配置 App ID、Access Token 和 Secret Key 后用于实时云端听写。\n- 新增本地搜索能力，可在命令面板中快速查找本机文件、最近文件和相关操作。\n- 优化云端 ASR 配置入口、权限提示和菜单状态，让在线识别服务的启用状态更清楚。\n\n## 细节\n\n- 功能：接入火山云豆包流式语音识别 2.0，并补齐配置保存、连接测试、菜单选择和 ASR Provider 状态展示。\n- 功能：命令面板新增本地文件搜索、最近文件、文件元数据展示和搜索缓存。\n- 修复：修正火山云服务入口链接和连接测试协议，避免已开通服务仍提示不可用。\n- 体验：更新 README、官网下载元数据和 App 内版本号到 1.12.1。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.12.1\n- `CFBundleVersion`：23\n- DMG：`VoxFlow-1.12.1-macOS.dmg`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.12.1",
    "published_at": "2026-07-01T02:06:59Z"
  }
];
