# 从源码构建

VoxFlow 是原生 macOS App，使用 Swift 6、SwiftUI/AppKit、SwiftPM、本地 ASR runtime，以及用于 AI Coding 助手的 Rust helper。

## 环境要求

- macOS 15 或更高版本
- Xcode 16.4 或兼容 Swift 6 工具链
- Rust 工具链，用于 `agent-cli/`
- 用于运行时验证的麦克风

## 常用命令

请使用 Makefile 入口，不要用 `swift run` 替代。打包后的 App 行为依赖签名、资源、helper、LaunchServices 注册和 runtime assets。

```bash
make run-dev      # 日常开发：Debug、本机架构、打包并启动 .app
make build-dev    # Debug 本机架构构建和打包，不启动
make run-native   # Native Release 启动
make build-native # Native Release 构建
make build        # Release app 构建
make debug        # Debug 构建并 warnings-as-errors
make test         # 运行测试
make install      # 安装到 /Applications
make dmg          # 构建 DMG
```

开发清理已经分级：

```bash
make run-dev          # 启动前只停止 VoxFlow 自家进程
make clean-ls-cache   # 显式清理 LaunchServices/status item 缓存
make reset-dev-state  # 进程清理 + LaunchServices/status item 缓存清理
```

## 源码结构

```text
Sources/VoxFlowApp/             # App 壳层、UI、生命周期 glue、composition root
Sources/VoxFlowDomain/          # 领域模型和任务状态
Sources/VoxFlowAudio/           # 音频采集和帧处理
Sources/VoxFlowASRCore/         # ASR provider/session/event 协议
Sources/VoxFlowProviders/       # Provider runtime targets
Sources/VoxFlowModelStore/      # 模型 manifest、安装状态、repair/prewarm
Sources/VoxFlowTextInsertion/   # 剪切板事务和文本插入
Sources/VoxFlowScreenshotKit/   # 截图采集、标注、OCR 窗口
Packages/VoxFlowVoiceCorrectionKit/ # 易错词引擎和 fixtures
agent-cli/                      # AI Coding 助手 Rust helper/router
Tests/                          # Swift 测试
Resources/                      # App 图标和资源
Vendor/                         # 本地 runtime/vendor 资源
docs/                           # 文档和 GitHub Pages 站点
scripts/                        # 构建、benchmark、架构检查脚本
```

## 验证

较完整的本地验证：

```bash
swift test
make debug
make build
make i18n-check
make architecture-check
```

小修可以跑聚焦测试和局部构建；但涉及存储、凭据、输出、ASR 选择、本地化或 App 启动的改动，应包含针对性测试，并至少跑 `make debug`。

## 关键路径

- App 产物：`VoxFlow.app`
- Bundle ID：`com.voxflow.app`
- Dev Bundle ID：`com.voxflow.app.dev`
- 用户数据：`~/Library/Application Support/VoxFlow/`
- 主数据库：`voxflow.sqlite`
- 凭据文件：`~/Library/Application Support/VoxFlow/credentials.json`
