# 码上写 iOS 开发入口

码上写 iOS 端是一个真实 Keyboard Extension 项目。主 App 负责录音、Provider 配置和状态桥接；`MashangxieKeyboard` 负责第三方键盘 UI、中文输入和语音入口。

## 初始化

```bash
brew install xcodegen
make ios-bootstrap
```

`make ios-bootstrap` 会生成：

- `Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj`
- `Apps/VoxFlowiOS/Generated/DevCloudCredentials.plist`

`Generated/` 和 `build/` 是本地生成物，已经在仓库根 `.gitignore` 中忽略。

## Rime / 雾凇词库资源

`ChineseInput/Resources/Schemas/` 不提交到仓库。它来自 `iDvel/rime-ice` 的固定 revision：

```text
846e5fcae56f0e3f4dcd8570319ffaf377e15471
```

`make ios-bootstrap` 会先运行 `Apps/VoxFlowiOS/Scripts/bootstrap-rime-ice-schemas.sh`，下载到 `.build/ios-rime-ice/` 缓存，再把运行时需要的 schema、词典、Lua 和 OpenCC 资源复制到 `ChineseInput/Resources/Schemas/`。上游文档、截图、recipes、`.github/` 和 `others/` 不会进入 App bundle。

CI 也走同一个 bootstrap 入口。不要在 Xcode build phase 里临时联网下载词库；否则本地、CI 和打包产物会不一致。

## Dev Cloud 凭证

不要把真实密钥写入源码或提交到仓库。开发模式下通过环境变量生成本地 plist：

```bash
export MASHANGXIE_DEV_TENCENT_APP_ID=...
export MASHANGXIE_DEV_TENCENT_SECRET_ID=...
export MASHANGXIE_DEV_TENCENT_SECRET_KEY=...
export MASHANGXIE_DEV_ALIYUN_API_KEY=...
export MASHANGXIE_DEV_VOLCENGINE_APP_ID=...
export MASHANGXIE_DEV_VOLCENGINE_ACCESS_TOKEN=...
export MASHANGXIE_DEV_VOLCENGINE_SECRET_KEY=...
make ios-bootstrap
```

缺少凭证的云端 Provider 会在 App 内置灰，不应该进入“重试”错误态。

## 常用命令

```bash
make ios-test-sim
make ios-ui-test-sim
make ios-build-sim
make ios-run-sim
make ios-ipa
make ios-clean
```

CI 在 iOS 相关路径变化时运行 `make ios-test-sim`。UI 测试依赖模拟器键盘切换状态，默认保留为本地验收命令。

## 分发与签名形态

源码只维护一套 App + Keyboard Extension。正式分发使用 Apple Developer Program 的 Ad Hoc 签名：

```bash
MASHANGXIE_DEVELOPMENT_TEAM=<team-id> \
MASHANGXIE_APP_PROFILE_SPECIFIER=<app-profile-name> \
MASHANGXIE_KEYBOARD_PROFILE_SPECIFIER=<keyboard-profile-name> \
make ios-ipa
```

生成版本化的 `dist/ios/Mashangxie-<version>-iOS.ipa`。该 IPA 已使用 Ad Hoc provisioning profiles 签名，可安装到两个 profile 已登记的 UDID 设备，并包含：

```text
Payload/Mashangxie.app
Payload/Mashangxie.app/PlugIns/MashangxieKeyboard.appex
```

打包后会自动运行 `Apps/VoxFlowiOS/Scripts/verify-ios-ipa-contract.sh --signed`，检查 app、keyboard extension、Rime/ChineseInput runtime frameworks、嵌入式 profiles、签名和 App Group entitlements。App Group 的运行时可用性仍必须在真机上通过诊断页验证。

只做本地结构检查、不用于安装时，可使用：

```bash
make ios-ipa-unsigned
```

该命令生成 `dist/ios/Mashangxie-unsigned.ipa`，不会伪装成可安装发布包。

## 目录边界

- `VoxFlowiOS/`：主 App，沿用 Dictus App UI 结构，只替换 Provider 桥接层。
- `Keyboard/`：Keyboard Extension，保留 Dictus/Giella 键盘 UI，中文符号/数字面板在这里实现。
- `ChineseInput/`：Rime、雾凇拼音、Hamster T9/Rime 相关代码和资源。
- `Shared/`：App Group、共享状态、日志和跨 target 常量。
- `*Tests/`：iOS target 的单元测试、集成测试和 UI 测试。
