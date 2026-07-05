# iOS LiveContainer V1 预览与验收

本文件记录 VoxFlow iOS V1 的三条预览路径、已知限制和验收步骤。V1 不发布到 App Store / TestFlight，仅通过 LiveContainer 在真机预览，配合 iOS Simulator 做电脑端快速验证。

## 目标

- 在不支付 Apple Developer Program 年费的前提下，让真机可以运行 VoxFlow iOS V1。
- 保留 macOS 行为不变；共享 ASR runtime 跨平台复用。
- 主验收路径是云实时 ASR（腾讯、阿里、火山）；Apple Speech 作为 baseline，不作为 LiveContainer 唯一成功路径。

## 三条预览路径

| 路径 | 用途 | 限制 |
|---|---|---|
| Simulator + Mac 麦克风 | 快速验证录音权限、UI 状态、云 ASR partial/final | Simulator 音频行为与真机不同；无 `AVAudioSession` 中断 |
| Simulator + 固定音频注入 | 可重复验收云 ASR 输出，对比腾讯/阿里/火山差异 | 需要 BlackHole 2ch 等虚拟音频设备 |
| 真机 + LiveContainer | 最终环境验收：麦克风、网络、凭证文件、云 ASR、复制 | LiveContainer 对部分系统能力有限制，见下文 |

## 1. Simulator + Mac 麦克风

### 1.1 前置条件

- macOS 15+（与项目一致）
- 使用与 Makefile 全局 `DEVELOPER_DIR` 相同的 Xcode；默认是 `~/Applications/Xcode-16.4.0.app`
- 该 Xcode 需安装匹配的 iOS Simulator runtime。切换 Xcode 时请统一覆盖 `VOXFLOW_DEVELOPER_DIR`，不要只给 iOS 单独换工具链。
- `xcodegen`：`brew install xcodegen`

### 1.2 构建并运行

```bash
make ios-run-sim
```

如需让 macOS 与 iOS 都统一使用另一套 Xcode：

```bash
make ios-run-sim VOXFLOW_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

该命令会：

1. 通过 `xcodegen` 生成 `Apps/VoxFlowiOS/VoxFlowiOS.xcodeproj`
2. 在 iOS Simulator 上构建 `VoxFlowiOS.app`
3. 安装到默认 Simulator（`iPhone 16 Pro` / iOS `18.5`，可通过 `IOS_SIMULATOR_NAME` / `IOS_SIMULATOR_OS` 覆盖）
4. 启动 App 和 Simulator

### 1.3 麦克风权限

Simulator 使用 Mac 麦克风作为音频源。首次启动 App 并点按"开始"时：

1. iOS Simulator 弹出麦克风权限对话框，选择 Allow
2. macOS 可能再次弹出 Mac 麦克风权限对话框，授权给 Simulator
3. 之后 App 应进入 `recording` 状态，云 ASR 开始返回 partial 文本

### 1.4 已知 Simulator 行为差异

- `AVAudioSession.interruptionNotification` 在 Simulator 上不会自然触发；中断逻辑只能在真机验证
- `AVAudioSession.routeChangeNotification` 在 Simulator 上拔插耳机时可能不触发
- Speech 识别权限对话框在 Simulator 上行为与真机一致，但识别准确率可能因 Mac 麦克风质量受限

## 2. Simulator + 固定音频注入

### 2.1 推荐路径：BlackHole 2ch

[BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) 是开源虚拟音频设备，可将 macOS 音频输出路由为输入。

#### 安装

1. 使用 Homebrew 安装：`brew install --cask blackhole-2ch`
2. 安装后重启 Mac；安装的 pkg 驱动需要管理员授权
3. 打开"音频 MIDI 设置"，创建"多输出设备"：
   - 包含 Mac 内置输出 + BlackHole 2ch
   - 设为系统默认输出
4. 在 iOS Simulator 中，输入设备自动使用 Mac 默认输入；将 Mac 输入设备设为 BlackHole 2ch

#### 播放固定测试音频

```bash
# 使用 afplay 播放 wav/mp3
afplay /path/to/test-audio.wav
```

播放期间在 VoxFlow iOS App 中点按"开始"，App 会通过 BlackHole 接收播放音频并送入云 ASR。

### 2.2 替代路径：Mac 麦克风

如果 BlackHole 安装受阻（需要管理员授权），退回 Mac 麦克风：

- 用同一台 Mac 同时播放测试音频和录音，会有少量回声
- 适合快速冒烟，不适合精确对比三家云 ASR 输出

### 2.3 替代路径：fake audio tests

如果虚拟音频设备和 Mac 麦克风都不可用，使用仓库内 fake audio 测试：

- `Tests/VoxFlowMobileCoreTests/MobileDictationSessionTests.swift` 用 fake recorder + fake engine 验证状态机
- `Tests/VoxFlowASRRuntimeTests/` 用 fake client 验证云 ASR runtime 消息拼接

### 2.4 固定测试音频

仓库暂未内置固定测试音频。推荐使用：

- 中文：`测试语音/今天天气不错适合出门散步` 录制 5-10 秒 wav
- 英文：`the quick brown fox jumps over the lazy dog` 录制 5-10 秒 wav
- 日文/韩文：类似短句

未来可在 `tools/ios-test-audio/` 中加入固定 fixture，配合 `make ios-asr-bench` 做可重复对比。

## 3. 真机 + LiveContainer

### 3.1 前置条件

- 已越狱或已安装 [LiveContainer](https://github.com/khanhduytran0/LiveContainer) 的 iOS 设备
- 设备 iOS 版本 ≥ 17.0
- 设备可访问至少一个云 ASR Provider 的服务端点
- iOS 26 及以上需要在 LiveContainer 设置中启用 JIT-Less：
  1. 安装 `LiveContainer + SideStore`
  2. 在内置 SideStore 中登录 Apple ID
  3. 安装并连接 `LocalDevVPN`
  4. 在 SideStore `My Apps` 中刷新 `LiveContainer`
  5. 回到 LiveContainer 设置，选择"从 SideStore 导入证书"
  6. 在"免 JIT 模式诊断"中确认 App Group、证书数据、证书密码、证书状态均为可用

### 3.2 构建 IPA

```bash
make ios-ipa
```

该命令会：

1. 生成 Xcode 项目
2. 在 `generic/platform=iOS` 设备配置下构建 Release 未签名 `.app`
3. 打包为未签名 IPA：`dist/ios/VoxFlowiOS.ipa`

V1 IPA 不做代码签名、不做 entitlements 处理。LiveContainer 接受未签名 IPA 作为宿主 App。

### 3.3 导入 LiveContainer

1. 将 `dist/ios/VoxFlowiOS.ipa` 传到 iOS 设备（AirDrop、iCloud Drive 或 LiveContainer 自带的文件导入）。本机可直接使用 iCloud Drive 路径：`iCloud Drive/VoxFlow/VoxFlowiOS.ipa`
2. 在 LiveContainer 中选择"导入 IPA"，选择 VoxFlowiOS.ipa
3. LiveContainer 安装完成后，App 页会出现 VoxFlow 条目；在 LiveContainer 内点"启动"
4. 如果桌面出现 VoxFlow 图标但提示"无法验证其完整性"，不要用该桌面入口验收，改从 LiveContainer App 页启动

### 3.4 真机验收步骤

按以下顺序验证 V1 主链路：

1. **启动 App**：底部 Tab 显示"听写 / 诊断 / 设置"
2. **填凭证**：进入"设置 → 云服务凭证 → 腾讯云实时 ASR"，填写 AppID / SecretId / SecretKey，点按"保存"
3. **选 Provider**：在"设置 → ASR 服务"选择"腾讯云实时 ASR"
4. **选语言**：在"设置 → 识别语言"选择"简体中文"
5. **回到听写页**：点按"开始"，授权麦克风权限
6. **说话**：实时文本区显示 partial 文本
7. **点按"停止"**：等待 final 文本出现
8. **点按"复制"**：final 文本复制到系统剪贴板
9. **粘贴验证**：切换到备忘录或其他 App，粘贴，确认文本正确

### 3.5 LiveContainer 已知限制

| 能力 | LiveContainer 行为 | V1 应对 |
|---|---|---|
| 麦克风权限 | 通常可用，但权限对话框可能由宿主 App 呈现 | 启动时检查 `AVAudioSession.recordPermission`；拒绝时引导用户去系统设置 |
| Speech 识别权限 | 可能不可用或行为异常 | Apple Speech 标记为 baseline；云 ASR 为主路径 |
| 网络访问 | 通常可用，但可能受宿主 App 网络配置影响 | 诊断页显示网络失败；用户可切换 Wi-Fi/蜂窝验证 |
| 文件持久化 | App sandbox 路径可能异常 | 凭证文件写到 `Application Support/VoxFlow/credentials.json`；如失败退回 `NSTemporaryDirectory` |
| 系统剪贴板 | 通常可用 | 复制失败时显示 toast 错误 |
| 后台运行 | 受宿主 App 后台限制 | V1 不做后台录音；切后台时自动停止 |
| iOS 26 JIT-Less | 未配置时启动 guest app 会提示 `JITLess mode is required since iOS 26` | 通过内置 SideStore、LocalDevVPN 和证书导入完成 JIT-Less 诊断 |
| SideStore 刷新 | 未连接 LocalDevVPN 时会提示 `No Wi-Fi and/or LocalDevVPN` | 安装并连接 LocalDevVPN，再执行 `Refresh All` |
| 桌面 guest 图标 | 可能提示"无法验证其完整性" | V1 验收从 LiveContainer App 页启动 |

### 3.6 重新导入 IPA

升级到新版本 VoxFlowiOS.ipa 时：

1. 在 LiveContainer 中长按 VoxFlow 图标，选择"卸载"
2. 重新导入新 IPA
3. 凭证文件会丢失（不同 sandbox），需重新填写

## 4. 诊断页说明

App 内"诊断"页提供以下信息：

- **Provider 可用性**：每个 Provider 的状态（Ready / Missing credentials / Permission denied / Permission not determined / Env limited）
- **运行环境**：平台（Simulator / Device）、容器（Native / LiveContainer）、Locale
- **录音器**：最近的 `setActive(false)` 错误（如有）
- **时间线**：本次会话的音频、网络、ASR、权限事件，最多保留 200 条

诊断页不收集任何遥测，不发送到服务端。

## 5. 凭证安全说明

V1 凭证以明文 JSON 保存在 App sandbox：

```
<Application Support>/VoxFlow/credentials.json
```

- 仅用于个人测试 key
- 不要填写高权限生产 key
- 不做 Keychain 加密、导入导出或服务端代理
- 卸载 App 或重新导入 IPA 会清除凭证
- 后续版本会引入 Keychain 或 token broker

设置页"云服务凭证"区域会持续显示此警告。

## 6. 已知阻塞与未验证项

| 项目 | 状态 | 说明 |
|---|---|---|
| Simulator 构建/启动 | 已验证 | 当前统一工具链使用 `~/Applications/Xcode-16.4.0.app`；已安装 iOS 18.5 Simulator runtime，并通过 `make ios-run-sim` 启动 `iPhone 16 Pro`。 |
| Simulator + Mac 音频 + 三家云 ASR | 已验证 | 已将本机恢复后的腾讯云、阿里云、火山云凭证写入 iOS Simulator sandbox；诊断页显示三家云 Provider 均可用；分别完成开始录音、Mac `say` 音频输入、停止录音、final 文本输出和复制/分享按钮启用。 |
| LiveContainer IPA 构建 | 已验证 | `make ios-ipa` 使用 `generic/platform=iOS` 产出 `iphoneos` arm64 未签名 IPA：`dist/ios/VoxFlowiOS.ipa`。 |
| 真机 LiveContainer 验收 | 已验证 | 2026-07-06 用户在 iPhone 16 Pro / iOS 26.5 上完成：iLoader 安装 `LiveContainer + SideStore`、LocalDevVPN 连接、JIT-Less 证书导入、VoxFlow IPA 导入、App 启动、语音识别权限和麦克风权限授权、听写页录音、final 文本输出。随后填写腾讯云、阿里云、火山云凭证并完成用户验收。 |
| 固定测试音频 | 已验证替代路径 | 仓库已有 `TestResources/ASRSmoke/Audio/zh_short.wav` 用于 provider live tests；UI 侧本次使用 Mac `say` 作为可复现音频输入。 |
| BlackHole 2ch 路径 | 文档化 | 安装需要管理员授权；未在本次实现中验证 |
| Apple Speech 在 LiveContainer | 已验证 | LiveContainer 宿主弹出 Speech 与 Microphone 权限；授权后听写页出现 final 文本。云 ASR 仍为 V1 主验收路径。 |

## 7. 后续轨道（不在 V1 范围）

- iOS 系统级键盘 / Keyboard Extension
- 任意 App 文本注入
- App Store / TestFlight 发布
- Keychain 凭证加密、导入导出、服务端 token broker
- 历史记录、SQLite 持久化、多设备同步
- Qwen3 / Whisper / FunASR / SenseVoice 本地模型 Provider
- Agent Compose、截图/OCR、文件转写
