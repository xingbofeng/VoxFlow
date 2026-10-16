window.VOXFLOW_RELEASES = [
  {
    "tag_name": "v1.18.1",
    "name": "VoxFlow 1.18.1",
    "body": "# VoxFlow 1.18.1\n\n## 更新摘要\n\n- 工程维护版本：应用功能与 1.18.0 保持一致，主要改进发布流水线与 CI 测试稳定性，无需急于更新。\n- 发布流水线提速：Windows 与 macOS 发布构建引入 Rust 运行时、vcpkg 与 NuGet 构建缓存，后续版本发布耗时更短。\n\n## 细节\n\n- 发布流水线：Tesseract 原生库改走 vcpkg 二进制缓存（命中时直接解包预编译包，仅脚本或依赖基线变化才重新编译）；agent 运行时与 helper 的 Rust 构建缓存化；测试流水线按模块分片并行执行。\n- 稳定性：修复 CI 中 iOS 模拟器键盘剪贴板桥接测试偶发超时（异步回调等待窗口与固定回调延迟不匹配），仅影响 CI，不影响应用行为。\n\n## 发布元数据\n\n- `CFBundleShortVersionString`：1.18.1\n- `CFBundleVersion`：30\n- macOS DMG：`VoxFlow-1.18.1-macOS.dmg`\n- Windows 安装包：`VoxFlow-1.18.1-windows-x64-setup.exe`\n- Windows 便携包：`VoxFlow-1.18.1-windows-x64-portable.zip`\n",
    "html_url": "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.18.1",
    "published_at": "2026-10-06T14:11:02Z"
  },
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
  }
];
