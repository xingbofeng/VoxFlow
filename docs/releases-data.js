window.VOXFLOW_RELEASES = [
  {
    "tag_name": "v1.18.0",
    "name": "VoxFlow 1.18.0",
    "body": "# VoxFlow 1.18.0\n\n## 更新摘要\n\n- 新增本地流式识别 Provider **X-ASR-zh-en**：中英混合口述，边说边出字，适合连续听写与即时反馈。\n- 修复本地 agent 进程偶发读到空输出的问题：模型列表与 CLI 检测不再偶发为空。\n\n## 细节\n\n- 功能：新增 X-ASR-zh-en 本地 Provider（中英混合流式识别），可在设置页与菜单栏切换；识别走原生流式解码，预览与最终文本来自同一路识别，模型下载、校验、修复、预热与卸载复用既有模型管理流程，权重不进安装包。\n- 注意：X-ASR-zh-en 模型约 586 MB，仅支持 Apple Silicon（M 系列）、macOS 15 及以上、8 GB 及以上内存的设备，首次使用前需先下载模型。\n- 修复：本地 agent 进程（AI 编程助手的模型列表与 CLI 检测）偶发读到空输出——根因是子进程退出瞬间输出读取存在竞态；现改为读者线程读到 EOF 的确定性并发排空，并确保父进程写端及时关闭，输出完整可读。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.18.0\n- `CFBundleVersion`：29\n- macOS DMG：`VoxFlow-1.18.0-macOS.dmg`\n- Windows 安装包：`VoxFlow-1.18.0-windows-x64-setup.exe`\n- Windows 便携包：`VoxFlow-1.18.0-windows-x64-portable.zip`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.18.0",
    "published_at": "2026-10-06T09:44:49Z"
  },
  {
    "tag_name": "v1.17.0",
    "name": "VoxFlow 1.17.0",
    "body": "# VoxFlow 1.17.0\n\n## 更新摘要\n\n- 新增本地语音识别模型 **Confucius4-R2T2**：边说边出字，适合连续口述和需要即时反馈的场景。\n- 新增本地语音识别模型 **FireRedASR2-AED**：主打中文准确率与方言覆盖，并支持录音期间的实时预览。\n- 悬浮窗实时文本重写显示逻辑：长句不再丢掉最后说出的字，始终显示最新内容。\n- 修复整段无语音时把 `<sil>` 当成正文上屏的问题。\n\n## 细节\n\n- 功能：新增两个本地 ASR Provider，可在设置页与菜单栏切换；两者的模型下载、校验、修复、预热与卸载都复用既有模型管理流程，权重不进安装包。\n- 功能：Confucius4-R2T2 走原生流式解码，预览与最终文本来自同一路识别；FireRedASR2-AED 是离线自回归模型，预览由「按至少 1 秒新音频节流」的重解得到，而最终文本仍由整段重解产出，因此开启预览不会改变识别结果。\n- 功能：设置页「本地模型实时预览」开关现在同样作用于 FireRedASR2-AED（默认开启）。\n- 修复：悬浮窗实时文本改为按行测量，长中文句子不再因为字符数上限被裁掉尾部——此前被裁掉的恰好是最新说出的字。\n- 修复：识别结果里的 `<sil>`、`<unk>` 这类功能性 token 会被剥离，不再作为正文插入。\n- 体验：Provider 名称统一为 `FireRedASR2-AED` 与 `Confucius4-R2T2`；模型体积在未下载时显示为「下载时检测」，不再展示可能误导的估值。\n- 注意：FireRedASR2-AED 模型约 1.24 GB，常驻内存较高，需要 16 GB 及以上内存，首次使用前需先下载模型。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.17.0\n- `CFBundleVersion`：28\n- macOS DMG：`VoxFlow-1.17.0-macOS.dmg`\n- Windows 安装包：`VoxFlow-1.17.0-windows-x64-setup.exe`\n- Windows 便携包：`VoxFlow-1.17.0-windows-x64-portable.zip`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.17.0",
    "published_at": "2026-10-05T21:29:57Z"
  },
  {
    "tag_name": "v1.16.0",
    "name": "VoxFlow 1.16.0",
    "body": "# VoxFlow 1.16.0\n\n## 更新摘要\n\n- Windows x64 现提供官方安装包和便携包，可与 macOS 版本从同一发布页下载。\n- 官网和五种语言 README 已同步本次 macOS、Windows 安装包及其下载入口。\n- 发布流程会校验官网、Release 资产和安装包版本一致，避免错误平台或旧文件继续出现在下载页。\n\n## 细节\n\n- 功能：Windows 发布产物包含每用户安装包与免安装便携包，便于按使用场景选择。\n- 修复：发布任务会清理同一标签下不属于当前平台声明的旧资产，并在上传后核对远端资产集合。\n- 体验：macOS 和 Windows 下载入口统一使用当前版本号；未配置 iOS 签名时不会展示或发布 IPA。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.16.0\n- `CFBundleVersion`：27\n- macOS DMG：`VoxFlow-1.16.0-macOS.dmg`\n- Windows 安装包：`VoxFlow-1.16.0-windows-x64-setup.exe`\n- Windows 便携包：`VoxFlow-1.16.0-windows-x64-portable.zip`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.16.0",
    "published_at": "2026-10-04T04:57:26Z"
  }
];
