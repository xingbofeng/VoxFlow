# VoxFlow — AGENTS.md

## 项目概览

VoxFlow（随声写）是一款 macOS 菜单栏语音输入工具。按住快捷键说话，松开后文字出现在光标位置。中文显示名"随声写"，英文品牌名"VoxFlow"。

技术栈：Swift 6 + SwiftUI + SwiftPM，最低支持 macOS 14。唯一外部依赖为 FluidAudio（本地 ASR）。

## 构建与运行

| 命令 | 用途 |
|---|---|
| `make build` | Release 构建 + 打包 `.app`（Universal Binary，arm64 + x86_64） |
| `make run` | prelaunch-cleanup → build → 启动 app（日常开发用这个） |
| `make debug` | Debug 构建，开启 `-warnings-as-errors` |
| `make test` / `swift test` | 运行全部测试 |
| `make install` | 安装到 `/Applications/VoxFlow.app` |
| `make dmg` | 生成 DMG 安装包 |
| `make clean` | 清理构建产物 |

**不要用 `swift run` 代替 `make run`**——权限、签名、资源加载行为不同。

## 验证清单

完成任何改动前，按顺序执行：

1. `swift test` — 全部测试通过（0 unexpected failures）
2. `make debug` — Debug 构建无 warning（`-warnings-as-errors`）
3. `make build` — Release 构建通过
4. 行为改动遵循 TDD：先写失败测试 → 最小实现 → 重构

## 品牌约定

- 构建产物：`VoxFlow.app`，安装包：`VoxFlow-<version>-macOS.dmg`
- Bundle ID：`com.xingbofeng.VoxFlow`
- Legacy Bundle ID `com.voiceinput.app` **仅**用于偏好迁移、LaunchServices 清理和状态栏缓存清理（`Makefile prelaunch-cleanup`、`ProductBrand.legacyBundleIdentifier`、`LegacyConfigurationMigrator`）
- Swift 模块名仍为 `VoiceInputApp`（与目录名 `Sources/VoiceInputApp/` 一致），改名是独立工程
- 用户数据目录 `~/Library/Application Support/VoiceInput/` 和数据库 `voiceinput.sqlite` **不改名**，避免丢失用户数据
- Keychain service `com.xingbofeng.VoiceInput.credentials` **不改名**，避免丢失 API Key

## 项目结构

```
Sources/VoiceInputApp/     # 主源码（113 个 Swift 文件）
  Resources/               # Info.plist、图片资源
Tests/VoiceInputAppTests/  # 测试（87 个测试文件）
Resources/                 # AppIcon.icns + iconset
docs/                      # GitHub Pages 落地页 + 隐私政策
.github/
  workflows/               # ci.yml、pages.yml、release.yml
  release-notes/           # 当前版本 release notes
Makefile                   # 构建入口
Package.swift              # SwiftPM 定义（Swift 6.0）
CONTEXT.md                 # 领域术语、模块边界表、ADR
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

### 关键设计决策（详见 CONTEXT.md）

- **粘贴注入**（ADR-001）：文本通过剪贴板 + Command-V 注入，不用 Accessibility value mutation
- **CJK 输入源切换**（ADR-002）：粘贴前临时切换到 ABC/US，完成后恢复
- **Final + 超时兜底**（ADR-003）：15 秒内无 final result 则取最新 partial
- **LLM 可选且保守**（ADR-004）：未配置时跳过，API 失败回退原文
- **Agent Compose 只复制**（ADR-011）：不注入、不模拟回车、不自动发送

## 测试约定

- 测试文件位于 `Tests/VoiceInputAppTests/`，与源文件一一对应（如 `Foo.swift` → `FooTests.swift`）
- 使用 `@testable import VoiceInputApp`
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

以下文件/路径包含有意保留的旧名称，**不要随意"修正"为 VoxFlow**：

- `ApplicationSupportPaths.swift` — 用户数据目录 `VoiceInput`
- `CredentialStore.swift` — Keychain service name
- `ProductBrand.swift` — `legacyName`、`legacyBundleIdentifier`
- `LanguageManager.swift` — UserDefaults key `VoiceInput_SelectedLanguage`
- `DatabaseQueue.swift` — DispatchQueue label
- `Makefile LEGACY_BUNDLE_ID` — 清理逻辑
- `docs/PRIVACY.md`、`docs/TECHNICAL_DESIGN.md` — 记录实际磁盘路径
