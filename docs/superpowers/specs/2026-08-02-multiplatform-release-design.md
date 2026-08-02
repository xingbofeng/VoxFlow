# VoxFlow 三平台发布设计

## 目标

将现有 macOS 与 iOS 实现、`feat/windows-v1-dictation` 的 Windows 实现收敛为同一条产品发布线。GitHub CI 与 Release 必须为 macOS、Windows、iOS 生成明确可下载的安装产物，落地页和五份 README 必须同时展示三个平台。

本次不引入 `feat/windows-file-transcription` 中的旧 OpenSpec 文档，也不把 iOS 改造成 App Store/TestFlight 发布。

## 合并边界

- 以当前 `origin/main` 为基线。
- 引入 `feat/windows-v1-dictation` 的 Windows 应用、测试、打包脚本与必要的共享 `agent-cli` 变更。
- 不引入 `feat/windows-file-transcription` 独有的 `openspec/changes/add-windows-file-transcription/` 文档。
- 冲突按当前 main 的 macOS/iOS 行为为基线解决；Windows 专用实现不得改变现有 macOS/iOS 运行时边界。

## 版本与资产契约

`Sources/VoxFlowApp/Resources/Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion` 继续作为唯一版本事实来源。`prepare-release` 同步更新 Release notes、落地页元数据和五份 README；`release-check` 校验所有平台资产命名与下载链接。

同一个 `v<version>` GitHub Release 包含：

- `VoxFlow-<version>-macOS.dmg`
- `VoxFlow-<version>-windows-x64-setup.exe`
- `VoxFlow-<version>-windows-x64-portable.zip`
- `Mashangxie-<version>-iOS.ipa`
- 每个二进制资产对应的 `.sha256`

`docs/release.json` 从单个 macOS `assetName` 扩展为按 `macos`、`windows`、`ios` 分组的资产对象。落地页脚本只消费这一份平台资产契约，不再自行拼接单平台事实。

## CI 与 Release 架构

普通 push/PR CI 使用平台独立 job：

- macOS runner 执行 Swift 测试、Release 构建和现有签名契约检查，并上传 DMG 或构建产物。
- Windows runner 执行 .NET/Rust 测试、Release 构建、Inno Setup 打包，上传安装版 EXE 与 Portable ZIP。
- macOS runner 构建 iOS device archive；没有发布签名 secrets 的 PR 生成未签名验证 IPA，有 secrets 的受信发布上下文生成 Ad Hoc IPA。

Release workflow 由 tag 或手动输入触发，先从 plist 校验版本，再并行构建三个平台。各 job 只负责构建、签名、验证和上传临时 artifact；最终 publish job 必须等待全部平台成功，下载所有 artifact，生成 SHA-256，并一次性创建或更新同一个 GitHub Release。任一平台失败时不发布残缺 Release。发布成功后再触发落地页部署。

## iOS Ad Hoc 签名

iOS Release job 使用 Apple Distribution `.p12`、密码、Team ID，以及主 App 和键盘扩展各自的 Ad Hoc provisioning profile。两个 profile 必须覆盖：

- App：`com.mashangxie.ios`
- Keyboard extension：`com.mashangxie.ios.keyboard`
- App Group：`group.com.mashangxie.ios`

workflow 在临时 keychain 中导入证书和 profiles，通过 `xcodebuild archive` 与 `xcodebuild -exportArchive` 生成 IPA。发布前检查嵌套键盘扩展签名、application identifier、App Group entitlement、profile 类型及产物名称。IPA 仅保证可安装到 provisioning profile 已登记 UDID 的设备。

建议的 GitHub Actions secret 名称为：

- `MASHANGXIE_IOS_DISTRIBUTION_P12_BASE64`
- `MASHANGXIE_IOS_DISTRIBUTION_P12_PASSWORD`
- `MASHANGXIE_IOS_TEAM_ID`
- `MASHANGXIE_IOS_APP_PROFILE_BASE64`
- `MASHANGXIE_IOS_KEYBOARD_PROFILE_BASE64`

## 落地页与 README

落地页保留现有视觉语言，下载区域改为三个平台卡片或按钮：macOS DMG、Windows 安装版/Portable、iOS IPA。每个平台明确系统要求、处理器架构和安装限制；iOS 必须注明“仅限已登记设备的 Ad Hoc 安装”，不能暗示任意 iPhone 可直接安装。

`README.md`、`README.zh-CN.md`、`README.zh-TW.md`、`README.ja.md`、`README.ko.md` 同步增加：

- macOS / Windows / iOS 支持矩阵；
- 三个平台的 Release 下载入口；
- Windows 安装版与 Portable 区别；
- iOS Ad Hoc IPA 的设备限制和安装步骤；
- 各平台已实现能力的准确说明，避免把桌面专用功能写成 iOS 已支持。

## 错误处理与安全

- 发布 secrets 仅注入签名步骤，不输出内容，不在 dry-run 命令中展开。
- 缺少任一 iOS 发布 secret 时，Release workflow 立即失败并指出缺少的 secret 名称；普通 PR CI 不因此失败，而是走未签名结构验证。
- Release publish 前核对资产集合，不允许缺少某个平台或 checksum。
- Windows 只能由 `windows-latest` runner 作为权威构建验证；macOS 本地检查不能替代 WPF/Installer CI。
- 现有 macOS 签名 secrets 与 iOS Distribution secrets 分开管理，避免证书身份混用。

## 验证与验收

- 发布元数据测试先覆盖三平台 JSON schema、文件名、URL、版本一致性，再修改脚本实现。
- Windows 合并后运行其静态治理检查；完整 .NET/WPF/Rust/Installer 验证由 Windows CI 完成。
- iOS 同时保留未签名 IPA 结构测试，并新增已签名 IPA 的证书、profile、entitlements 和嵌套扩展校验。
- macOS 运行 `swift test`、`make debug`、`make build` 与现有签名检查。
- README 与落地页运行多语言/发布元数据检查，并通过浏览器在桌面和移动尺寸验证三个平台下载入口。
- 最终以 GitHub Actions 成功记录和同一 GitHub Release 中完整的四个安装资产及其 checksum 作为发布完成证据。
