# VoxFlow — AGENTS.md

## 项目概览

VoxFlow（随声写）是一款原生 macOS 菜单栏语音输入工具。按住快捷键说话，松开后文字回到当前光标所在位置。中文显示名"随声写"，英文品牌名"VoxFlow"。

它的定位是"语音键盘"，不是语音助手：不接管窗口，不自动发送内容，不把用户带到另一个输入框。核心体验围绕全局听写、稳定文本插入、本地优先数据、可选 LLM 保守纠错，以及多 ASR Provider（Apple Speech、Qwen3-ASR、Whisper、FunASR、SenseVoice 等）展开。

技术栈：Swift 6 + SwiftUI/AppKit + SwiftPM，最低支持 macOS 14。主要依赖包括 FluidAudio、WhisperKit/argmax-oss-swift、Sherpa-ONNX vendor runtime，以及 Qwen3 MLX worker/托管 Python runtime 相关脚本。

## 构建与运行

| 命令 | 用途 |
|---|---|
| `make build` | Release 构建 + 打包 `.app`（Universal Binary，arm64 + x86_64） |
| `make run-dev` | prelaunch-cleanup → Debug 本机架构构建 → 打包并启动 app（日常开发优先用这个） |
| `make build-dev` | Debug 本机架构构建 + 打包 `.app`，不启动 |
| `make run-native` | prelaunch-cleanup → Release 本机架构构建 → 打包并启动 app |
| `make build-native` | Release 本机架构构建 + 打包 `.app`，不启动 |
| `make run` | prelaunch-cleanup → Universal Release build → 启动 app（发布前或兼容性验证用） |
| `make debug` | Debug 构建，开启 `-warnings-as-errors` |
| `make test` / `swift test` | 运行全部测试 |
| `make install` | 安装到 `/Applications/VoxFlow.app` |
| `make dmg` | 生成 DMG 安装包 |
| `make clean` | 清理构建产物 |

**不要用 `swift run` 代替 `make run-dev` / `make run`**——权限、签名、资源加载、worker 打包、LaunchServices 注册和状态栏缓存清理行为不同。

## 验证清单

完成任何改动前，按顺序执行：

1. `swift test` — 全部测试通过（0 unexpected failures）
2. `make debug` — Debug 构建无 warning（`-warnings-as-errors`）
3. `make build` — Release 构建通过
4. 行为改动遵循 TDD：先写失败测试 → 最小实现 → 重构

如果全量门禁被当前工作树中无关迁移问题阻塞，必须明确报告具体命令、错误文件/行号、是否与本次改动相关，并至少完成本次改动的针对性测试或静态检查。

## 品牌约定

- 构建产物：`VoxFlow.app`，安装包：`VoxFlow-<version>-macOS.dmg`
- Bundle ID：`com.voxflow.app`
- Legacy Bundle ID `com.voiceinput.app` **仅**用于明确的旧偏好/LaunchServices/状态栏缓存清理语境（如 `Makefile prelaunch-cleanup`、`ProductBrand.legacyBundleIdentifier`、相关测试 fixture）
- SwiftPM executable product / target / module：`VoxFlowApp`
- App 源码目录：`Sources/VoxFlowApp/`
- App 测试目录：`Tests/VoxFlowAppTests/`
- 用户数据目录：`~/Library/Application Support/VoxFlow/`
- 主数据库：`voxflow.sqlite`
- Keychain service：`com.voxflow.app.credentials`

## 项目结构

```
Sources/VoxFlowApp/             # App 壳层、UI、装配、macOS lifecycle glue
Sources/VoxFlowDomain/          # 领域模型、任务状态、输出结果、品牌常量
Sources/VoxFlowAudio/           # 音频帧、采集、转换、endpoint / flush
Sources/VoxFlowASRCore/         # Provider / Session / Event 协议
Sources/VoxFlowModelStore/      # 模型 manifest、下载、校验、安装状态
Sources/VoxFlowTextInsertion/   # 剪贴板事务、输入源切换、文本插入
Sources/VoxFlowProviders/VoxFlowProvider*/ # 各 ASR Provider runtime / descriptor / session/client，保持独立 SwiftPM target
Tests/VoxFlowAppTests/          # App target 测试
Tests/VoxFlowProviders/VoxFlowProvider*Tests/ # Provider target 测试
Tests/VoxFlow*Tests/            # 其他独立模块测试
Resources/                      # AppIcon.icns + iconset
docs/                           # GitHub Pages 落地页、隐私政策、设计/资源文档
.github/
  workflows/                    # ci.yml、pages.yml、release.yml
  release-notes/                # 当前版本 release notes
Makefile                        # 构建入口
Package.swift                   # SwiftPM 定义（Swift 6.0）
CONTEXT.md                      # 领域术语、模块边界表、ADR
```

## 架构规则

### 核心分层

| 层 | 职责 | 禁止 |
|---|---|---|
| `AppDelegate` | 菜单构建、权限引导、快捷键入口、HUD 回调 | 音频处理、状态机、持久化 |
| `DictationOrchestrator` | 录制生命周期、ASR 回调、超时兜底、文本管线、注入、历史保存 | 菜单、权限、视图布局 |
| `VoiceTaskCoordinator` | 统一入口：dictation / agentCompose 两种模式，推进 VoiceTask 记录 | 菜单、视图、音频引擎 |
| `TextProcessingPipeline` | 替换规则 → LLM 修正 → fallback | ASR、音频、注入 |
| `OutputService` | 模式感知输出选择（注入 vs 复制） | ASR、提示词构建 |
| `PromptBuilder` / `AgentPromptBuilder` | 纯 prompt 拼装，不持有 repository、不发网络请求 | 持久化、网络 |
| `TextInjector` | 输入源切换 + 粘贴 + 剪贴板恢复 | 识别或 LLM |
| `Sources/VoxFlowProviders/VoxFlowProvider*` | Provider descriptor、runtime/session/client、模型 readiness、provider-specific smoke；每个 Provider 保持独立 target | AppKit UI、菜单、全局快捷键、其他 Provider 的运行时 |
| `VoxFlowModelStore` | 模型 manifest、内容寻址、原子安装、安装状态、repair/prewarm/canary | 具体 Provider UI |
| `VoxFlowTextInsertion` | 文本插入 contract、剪贴板事务、快速粘贴、模拟输入 | ASR、LLM、历史持久化 |

### 关键设计决策（详见 CONTEXT.md）

- **粘贴注入**（ADR-001）：文本通过剪贴板 + Command-V 注入，不用 Accessibility value mutation
- **CJK 输入源切换**（ADR-002）：粘贴前临时切换到 ABC/US，完成后恢复
- **Final + 超时兜底**（ADR-003）：15 秒内无 final result 则取最新 partial
- **LLM 可选且保守**（ADR-004）：未配置时跳过，API 失败回退原文
- **Agent Compose 只复制**（ADR-011）：不注入、不模拟回车、不自动发送

## 测试约定

- App 测试文件位于 `Tests/VoxFlowAppTests/`；独立模块测试位于对应 `Tests/VoxFlow*Tests/`
- App 测试使用 `@testable import VoxFlowApp`；模块测试导入对应 target
- Mock 类命名：`Fake*`（行为模拟）或 `Capturing*`（记录调用）
- UserDefaults suite name 使用 `UUID()` 隔离，避免测试间串扰
- 环境变量前缀 `VOICEINPUT_TEST_*` 用于需要真实 API 的集成测试（默认跳过）

## CI / CD

| Workflow | 触发 | 做什么 |
|---|---|---|
| `ci.yml` | push / PR to main | `swift test` + `make build` + 签名验证 |
| `pages.yml` | push to main | 部署 `docs/` 到 GitHub Pages |
| `release.yml` | 手动 / tag | 构建 DMG + 上传 Release |

## 文件改动禁区

以下文件/路径包含有意保留或受架构约束的名称，**不要随意"修正"、迁移或删除**：

- `Sources/VoxFlowDomain/Branding/ProductBrand.swift` — `legacyBundleIdentifier` 仅用于旧 bundle 清理/测试断言
- `Makefile LEGACY_BUNDLE_ID` / `LEGACY_APP_NAME` — 仅用于 LaunchServices、旧状态栏 defaults 和残留 app 注册清理
- `LanguageManager.swift` — UserDefaults key `VoiceInput_SelectedLanguage`
- `DatabaseQueue.swift` — DispatchQueue label
- `VOICEINPUT_TEST_*` 环境变量 — 兼容既有 live/smoke 测试开关，除非成体系迁移测试和 CI，否则不要零散改名
- `docs/PRIVACY.md`、`docs/resource-ownership.md` 等文档 — 记录实际磁盘路径、资源归属和历史兼容说明，修改前先核对代码现状
