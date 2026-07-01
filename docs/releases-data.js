window.VOXFLOW_RELEASES = [
  {
    "tag_name": "v1.12.1",
    "name": "VoxFlow 1.12.1",
    "body": "# VoxFlow 1.12.1\n\n## 更新摘要\n\n- 新增火山云豆包流式语音识别支持，可配置 App ID、Access Token 和 Secret Key 后用于实时云端听写。\n- 新增本地搜索能力，可在命令面板中快速查找本机文件、最近文件和相关操作。\n- 优化云端 ASR 配置入口、权限提示和菜单状态，让在线识别服务的启用状态更清楚。\n\n## 细节\n\n- 功能：接入火山云豆包流式语音识别 2.0，并补齐配置保存、连接测试、菜单选择和 ASR Provider 状态展示。\n- 功能：命令面板新增本地文件搜索、最近文件、文件元数据展示和搜索缓存。\n- 修复：修正火山云服务入口链接和连接测试协议，避免已开通服务仍提示不可用。\n- 体验：更新 README、官网下载元数据和 App 内版本号到 1.12.1。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.12.1\n- `CFBundleVersion`：23\n- DMG：`VoxFlow-1.12.1-macOS.dmg`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.12.1",
    "published_at": "2026-07-01T02:06:59Z"
  },
  {
    "tag_name": "v1.12.0",
    "name": "VoxFlow 1.12.0",
    "body": "# VoxFlow 1.12.0\n\n## 更新摘要\n\n- 新增风格级输出格式控制，可为日常、聊天、邮件、编程等风格分别设置句末标点、大小写、语气和表情倾向；帮助页新增交流群入口，方便查看加入方式。\n- 新增风格自动匹配与同 App 上下文轮次，VoxFlow 可以结合当前应用和最近转写历史，更稳地选择合适风格。\n- 新增文本差异对比视图，首页转写详情可以直接查看识别原文、最终文本以及每一步处理到底改了哪里。\n- 新增默认关闭的崩溃日志能力，支持用户授权后自动上报崩溃，并可手动发送最近的系统崩溃报告。\n\n## 细节\n\n- 功能：增加输出格式弹窗、风格自动匹配配置、路由缓存、Context Rounds、崩溃报告服务和 Sentry dSYM 上传流程。\n- 修复：补齐危险本地化格式化检查，减少格式化参数不匹配导致的 UI 崩溃风险。\n- 体验：README 下载文件名、官网下载元数据和 App 内版本号已同步到 1.12.0；README 增加用户群入口。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.12.0\n- `CFBundleVersion`：22\n- DMG：`VoxFlow-1.12.0-macOS.dmg`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.12.0",
    "published_at": "2026-06-30T18:05:31Z"
  },
  {
    "tag_name": "v1.11.0",
    "name": "VoxFlow 1.11.0",
    "body": "# VoxFlow 1.11.0\n\n## 更新摘要\n\n- 新增确定性文本处理能力，优化数字、空格、标点、填充词和长句整理，未启用 LLM 时也能获得更稳定的转写结果。\n- 优化 AI 编程、截图 OCR、上下文增强和应用风格识别链路，让语音输入在不同目标 App 中更贴近当前场景。\n- 清理历史 Bundle ID 与菜单栏状态项缓存逻辑，修复菜单栏图标在 macOS 状态栏重排后可能消失的问题。\n\n## 细节\n\n- 功能：新增 `VoxFlowPromptKit` 与 `VoxFlowTextProcessing`，拆分提示词构建和确定性文本处理逻辑。\n- 修复：收敛旧 Bundle ID、旧状态栏 autosave 名称和历史测试保护，改用稳定的 `VoxFlowMenuBarItem` 菜单栏身份。\n- 体验：更新设置、首页、历史详情、截图 OCR 与文本插入相关流程，减少误触发和不稳定状态。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.11.0\n- `CFBundleVersion`：21\n- DMG：`VoxFlow-1.11.0-macOS.dmg`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.11.0",
    "published_at": "2026-06-29T20:55:06Z"
  }
];
