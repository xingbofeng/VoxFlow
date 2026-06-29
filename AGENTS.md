# VoxFlow — AGENTS.md

## 项目概览

VoxFlow（码上写）是一款原生 macOS 菜单栏语音输入工具。按住快捷键说话，松开后文字回到当前光标所在位置。中文显示名"码上写"，英文品牌名"VoxFlow"。

它的定位是"语音键盘"，不是语音助手：不接管窗口，不自动发送内容，不把用户带到另一个输入框。核心体验围绕全局听写、稳定文本插入、本地优先数据、可选 LLM 保守纠错，以及多 ASR Provider（Apple Speech、Qwen3-ASR、Whisper、FunASR、SenseVoice 等）展开。

技术栈：Swift 6 + SwiftUI/AppKit + SwiftPM，最低支持 macOS 15。主要依赖包括 FluidAudio、WhisperKit/argmax-oss-swift、Sherpa-ONNX vendor runtime、Qwen3 MLX worker/托管 Python runtime 相关脚本，以及 `agent-cli/` 下的 Rust AI Coding 助手 helper/router。

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

### 菜单栏图标 / StatusKit 缓存排查

当菜单栏图标消失、错位，且改 Bundle ID 后暂时恢复时，优先按 macOS 状态栏缓存问题处理，不要只改图标资源或反复 bump Bundle ID。

已知相关缓存层：

- App defaults：`~/Library/Preferences/com.voxflow.app*.plist` 中的 `NSStatusItem Preferred Position ...`、`NSStatusItem Visible ...`、`NSStatusItem VisibleCC ...`
- LaunchServices 注册库：由 `lsregister` 管理，可能残留 `.build/`、`/Applications/`、`~/.Trash/`、已挂载 DMG 中的旧 `VoxFlow.app` / `VoiceInput.app`
- IconServices 图标缓存：`$(getconf DARWIN_USER_CACHE_DIR)/com.apple.iconservices*`，以及系统级 `/Library/Caches/com.apple.iconservices.store`
- StatusKit / Control Center 私有状态：`~/Library/StatusKit`、`~/Library/Group Containers/group.com.apple.controlcenter`

常规清理优先使用 `make run-dev` 或 `make run`，它会执行 `prelaunch-cleanup`，覆盖本项目已知的 LaunchServices 反注册和 status item defaults 清理。如果仍不恢复，再做深度清理：

```bash
pkill -x VoxFlow 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
killall iconservicesagent 2>/dev/null || true

rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/com.apple.iconservices"
rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/com.apple.iconservicesagent"

killall cfprefsd 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
killall iconservicesagent 2>/dev/null || true
```

如果 `~/Library/StatusKit` 或 `~/Library/Group Containers/group.com.apple.controlcenter` 读写时报 `Operation not permitted`，这是 TCC 隐私保护，不是普通 Unix 权限。先在 System Settings → Privacy & Security → Full Disk Access 给当前终端 / Codex / iTerm / Ghostty 授权，并完全重启该终端。授权后才可清理：

```bash
pkill -x VoxFlow 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

rm -rf "$HOME/Library/StatusKit"
rm -rf "$HOME/Library/Group Containers/group.com.apple.controlcenter"

killall cfprefsd 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
```

注意：清理 `StatusKit` / `group.com.apple.controlcenter` 会重置部分 macOS 菜单栏和控制中心布局，只在普通 `prelaunch-cleanup`、LaunchServices 重建、IconServices 用户缓存清理都无效时使用。不要删除 `~/Library/Application Support/VoxFlow/`，那里是用户数据。

## 验证清单

完成高风险或发布前改动时，按顺序执行：

1. `swift test` — 全部测试通过（0 unexpected failures）
2. `make debug` — Debug 构建无 warning（`-warnings-as-errors`）
3. `make build` — Release 构建通过
4. 重要行为改动遵循 TDD：先写失败测试 → 最小实现 → 重构

如果全量门禁被当前工作树中无关迁移问题阻塞，必须明确报告具体命令、错误文件/行号、是否与本次改动相关，并至少完成本次改动的针对性测试或静态检查。

小 bug 修复不强制新增测试，也不要求默认跑完整门禁；根据风险选择最小验证即可，例如静态检查、局部构建、手工检查或复现路径验证。典型小 bug 包括提示文案、toast 可见性、轻量布局微调、明显的一行逻辑修正等。不要为了满足形式化 TDD 而新增低价值测试。

## 品牌约定

- 构建产物：`VoxFlow.app`，安装包：`VoxFlow-<version>-macOS.dmg`
- Bundle ID：`com.voxflow.app`
- SwiftPM executable product / target / module：`VoxFlowApp`
- App 源码目录：`Sources/VoxFlowApp/`
- App 测试目录：`Tests/VoxFlowAppTests/`
- 用户数据目录：`~/Library/Application Support/VoxFlow/`
- 主数据库：`voxflow.sqlite`
- SQLite schema 快照：`Sources/VoxFlowApp/Persistence/AppDatabaseSchema.sql`
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
Sources/VoxFlowScreenshotKit/    # 截图采集、标注、滚动截图和截图窗口展示
Packages/VoxFlowVoiceCorrectionKit/ # 易错词纠错引擎、benchmark fixtures 和独立测试
agent-cli/                      # AI Coding 助手 Rust helper/router 源码，构建产物为 bundled voxflow 与 vox shim
Tests/VoxFlowAppTests/          # App target 测试
Tests/VoxFlowProviders/VoxFlowProvider*Tests/ # Provider target 测试
Tests/VoxFlow*Tests/            # 其他独立模块测试
Tests/VoxFlowScreenshotKitTests/ # 截图采集与标注模块测试
Resources/                      # AppIcon.icns + iconset
Vendor/                         # 打包所需的本地 runtime/vendor 资源
docs/                           # GitHub Pages 落地页、隐私政策、设计/资源文档
scripts/                        # 构建、ASR benchmark、架构检查等开发脚本
tools/                          # 辅助验证工具；不放 agent CLI
.github/
  workflows/                    # ci.yml、pages.yml、release.yml
  release-notes/                # 当前版本 release notes
Makefile                        # 构建入口
Package.swift                   # SwiftPM 定义（Swift 6.0）
CONTEXT.md                      # 领域术语、模块边界表、ADR
```

AI Coding 助手 的 CLI 源码只维护 Rust 版本：根目录 `agent-cli/`。旧 Python 版 `vf-agent` / `agent-cli` 参考 helper 已删除；仓库内剩余 Python 文件只用于 ASR benchmark、架构检查或易错词 JiWER 交叉验证，不参与 App 运行时，也不作为用户 CLI 分发。

## 架构规则

### SQLite 与迁移

- 表结构快照统一维护在 `Sources/VoxFlowApp/Persistence/AppDatabaseSchema.sql`。
- 新增或修改表、索引、列的默认建表定义时，先更新 `AppDatabaseSchema.sql`，再让 `AppDatabase.swift` 的 migration 通过 bundled schema 幂等执行。
- 不再新增 `initialSchemaSQL`、`voiceCorrectionSQL` 这类内联建表常量；只有必要的数据回填、清理或一次性转换逻辑可以留在 migration 代码里。
- SQLite repository 负责 CRUD SQL；schema SQL 负责结构定义，测试应覆盖 bundled schema 能创建/补齐对应表结构。

### 核心分层

| 层 | 职责 | 禁止 |
|---|---|---|
| `AppDelegate` | 菜单构建、权限引导、快捷键入口、HUD 回调 | 音频处理、状态机、持久化 |
| `DictationOrchestrator` | 录制生命周期、ASR 回调、超时兜底、文本管线、注入、历史保存 | 菜单、权限、视图布局 |
| `VoiceTaskCoordinator` | 统一入口：dictation / agentCompose 两种模式，推进 VoiceTask 记录 | 菜单、视图、音频引擎 |
| `TextProcessingPipeline` | 可选 LLM 修正 → 易错词确定性替换 → fallback / 插入前处理 | ASR、音频、注入 |
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
- 小 bug 修复不需要强制补测试；只有涉及核心流程、数据持久化、跨模块契约、回归风险高或用户可观察行为复杂时，才优先补针对性测试。
- 不要无限堆测试。新增测试必须覆盖真实行为、边界、回归风险或架构约束；低价值用例不需要写，避免拖慢 `swift test` 和日常迭代。
- UI / Presentation 测试优先测试可抽离的 presentation model、ViewModel、路由策略、状态机和用户可观察行为；不要为了固定 SwiftUI 具体写法而写源码字符串快照测试。
- 禁止新增“读取 `Sources/.../*.swift` 后 `source.contains(...)` / 正则匹配实现细节”的测试，除非它是明确的架构边界检查或发布/打包契约检查，且没有更直接的行为测试方式。
- 禁止新增扫全仓库、扫 Markdown、扫 OpenSpec 文档的品牌/文案/实现细节测试；这类检查容易误伤历史文档和方案草稿。
- 读文件类测试应限于真实产物或 fixture 行为，例如 SQLite schema、资源 bundle、热词导出文件、发布元数据 fixture、生成的字幕/SRT 等。
- 如果为了防回归必须保护某个 UI 细节，优先把判断逻辑下沉到可测试的小模型或策略对象；确实只能人工/截图验证的，不要用脆弱源码断言替代。

## 多语言与本地化

- App 可见文案必须走 `L10n.localize(...)` 和 `Sources/VoxFlowApp/Resources/*/Localizable.strings`；`VoxFlowScreenshotKit` 可见文案使用 `Sources/VoxFlowScreenshotKit/Resources/*/ScreenshotKit.strings`。不要在 SwiftUI/AppKit UI 中新增硬编码中文、英文或其他语言文案。
- 新增或修改可见文案时，必须同步维护五种语言：`en`、`zh-Hans`、`zh-Hant`、`ja`、`ko`。如果短期无法提供完整高质量翻译，至少使用清晰可读的英文 fallback，禁止提交由 key 拆词生成的半翻译文案。
- 禁止将 `title`、`subtitle`、`placeholder`、`stats`、`current_agents`、`recent_dispatches` 等 key 片段直接翻成可见文案，例如 `AI 编程 当前 助手 标题`、`截图 媒体 stats`、`Settings Task ... Title`、`Recording Hud Action Copy`。这类文案必须重写成面向用户的自然语言。
- 不要把 BartyCrouch `defaultToKeys` 改回 `true`。缺失 key 应在检查中失败，而不是自动把 key 填成 value。
- 修改 `.strings` 后运行 `make i18n-check`。该命令会执行 BartyCrouch key/语法检查和 `scripts/check-localization.py` 的项目级文案质量扫描。
- 修改英文源文案或新增 key 后，如需更新类型安全访问代码，运行 `make gen-l10n` 并检查 `Sources/VoxFlowApp/Generated/L10n.swift`、`Sources/VoxFlowScreenshotKit/Generated/L10n.swift` 是否只包含预期变化。
- 文案修复优先改资源文件，不要为了绕过本地化问题在 View 层拼接字符串；带参数文案使用 format key，确保各语言保留相同 `%@` / `%d` 占位符语义。

## CI / CD

| Workflow | 触发 | 做什么 |
|---|---|---|
| `ci.yml` | push / PR to main | `swift test` + `make build` + 签名验证 |
| `pages.yml` | push to main | 部署 `docs/` 到 GitHub Pages |
| `release.yml` | 手动 / tag | 构建 DMG + 上传 Release |

### 发布流水线约定

- 发布流程必须逐步收敛到"一键准备 + CI 自动发布 + CI 强校验"：本地只输入版本号/build、确认 release notes 和 review diff，构建、打包、hash、GitHub Release 上传、GitHub Pages 部署交给脚本和 CI。
- 版本元数据必须有单一可信来源。当前阶段以 `Sources/VoxFlowApp/Resources/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion` 为源；`docs/script.js` 与 `docs/release.json` 由发布脚本同步生成/更新，CI 通过 `make release-check` 校验一致性。
- 不要手动分散修改发布版本号。涉及发版时，应通过 `make prepare-release VERSION=<x.y.z> BUILD=<n>`（或等价脚本）统一更新：
  - `Info.plist` 版本号与 build；
  - `.github/release-notes/v<x.y.z>.md`（不存在时从模板生成）；
  - `docs/` 落地页下载链接、release note 展示和版本元数据；
  - `README.md` / `README_EN.md` 中的 DMG 文件名；
  - 其他由 release check 维护的版本引用。
- 发布前必须提供 `make release-check`（或等价脚本）校验版本一致性；CI 的 `ci.yml` 和 `release.yml` 应运行该检查，确保 plist、release notes、落地页、README、DMG asset 命名和 tag 规则一致。
- 人工必须确认的内容：目标版本号/build、release notes 面向用户的真实描述、`prepare-release` 产生的 diff、发版时机和 tag 推送。
- 可自动化的内容：版本号落盘、落地页/README 下载信息更新、release notes 模板生成、一致性校验、测试、构建、DMG 打包、sha256 生成、GitHub Release 创建与资产上传、GitHub Pages 部署。
- 应用内更新检测必须依赖上述发布流水线保证 GitHub Release、落地页下载链接、`docs/release.json`、DMG 文件名和 App 内版本一致；不要让更新检测各自维护另一套版本事实。生产检查优先读取 GitHub Pages 静态 `release.json`，并允许回退解析已部署的 `docs/script.js` release 对象，避免 GitHub API rate limit 影响本地检查。

## 文件改动禁区

以下文件/路径包含有意保留或受架构约束的名称，**不要随意"修正"、迁移或删除**：

- `Makefile CURRENT_BUNDLE_ID` / `DEV_BUNDLE_ID` — `CURRENT_BUNDLE_ID=com.voxflow.app` 仅用于正式构建，`DEV_BUNDLE_ID=com.voxflow.app.dev` 仅用于 `build-dev` / `run-dev` 隔离 LaunchServices、TCC 权限和状态栏身份
- `LanguageManager.swift` — UserDefaults key `VoiceInput_SelectedLanguage`
- `DatabaseQueue.swift` — DispatchQueue label
- `VOICEINPUT_TEST_*` 环境变量 — 兼容既有 live/smoke 测试开关，除非成体系迁移测试和 CI，否则不要零散改名
- `docs/PRIVACY.md`、`docs/resource-ownership.md` 等文档 — 记录实际磁盘路径、资源归属和历史兼容说明，修改前先核对代码现状
