# 第三方许可

本文记录 VoxFlow 复制或大量改写的第三方源码。

## Easydict

- 上游项目：tisfeng/Easydict
- 上游 URL：https://github.com/tisfeng/Easydict
- 上游 commit：1376005e8455783d2db162cb7029f14cde932a9f
- 许可证：GPL-3.0
- 结构化搬运文件：
  - `Easydict/Swift/Utility/EventMonitor/Workflow/SelectionWorkflow.swift`
  - `Easydict/Swift/Utility/SystemUtility/SystemUtility.swift`
  - `Easydict/Swift/Feature/ActionManager/ActionManager.swift`
- 本地目标路径：
  - `Sources/VoxFlowApp/SelectionActions/SelectionTextProvider.swift`
  - `Sources/VoxFlowApp/SelectionActions/SelectionActionDispatcher.swift`
  - `Sources/VoxFlowApp/SelectionActions/SelectionResultViewModel.swift`
- 复制 / 改写行为：
  - AX selected text 优先读取。
  - AX 失败或为空时进入强制复制 fallback。
  - 支持 shortcut copy 与 menu copy 的顺序策略。
  - 当前前台应用为 VoxFlow 自身时跳过强制复制 fallback。
  - fallback 读取后恢复用户原剪贴板内容。
  - 系统适配层拆出快捷键 Copy、Menu Copy、前台 App 判断和 Copy action 可用性检查。
  - 选中文本进入动作后，结果可复制、替换原文或插入下一行，失败时按 VoxFlow 结果面板策略降级。
- 未原样搬运原因：
  - Easydict 依赖 SelectedTextKit、AXManager、Defaults、PasteboardManager 和应用内单例配置，直接复制会绕过 VoxFlow 现有 `VoxFlowTextInsertion`、快捷键、设置和 AppKit adapter 边界。
  - Easydict ActionManager 绑定 Easydict 翻译/润色 UI、服务选择和单例状态；VoxFlow 保留动作编排语义，改接 `TextTransformService`、`TextInserting` 和 Text Result Panel。
- 验证：
  - `swift test --filter SelectionTextProviderTests`
  - `swift test --filter SelectionResultViewModelTests`

## PopClip Extensions

- 上游项目：pilotmoon/PopClip-Extensions
- 上游 URL：https://github.com/pilotmoon/PopClip-Extensions
- 上游 commit：9be40b0c21052e5d491fbcd1e2432c9f50be60d8
- 许可证：MIT（仓库 `LICENSE.txt`，README 声明所有源码使用 MIT License）
- 结构化参考文件：
  - `source/OpenAIChat.popclipext/Config.ts`
  - `contrib/SmartTranslate.popclipext/Config.ts`
- 本地目标路径：
  - `Sources/VoxFlowApp/SelectionActions/SelectionAction.swift`
  - `Sources/VoxFlowApp/SelectionActions/SelectionResultViewModel.swift`
  - `Sources/VoxFlowApp/TextTransform/TextTransformService.swift`
- 复制 / 改写行为：
  - selected text -> action -> copy / replace / append 的单一职责动作模型。
  - “目标语言相同则润色，否则翻译”的 prompt 策略。
- 未原样搬运原因：
  - 上游是 PopClip extension TypeScript 配置，依赖 PopClip 的 extension runtime、options schema 和宿主输出 API，不能直接运行在 VoxFlow Swift/AppKit 进程。
  - VoxFlow 只搬运 action/output mode 结构和 prompt 策略，具体 Swift 枚举、结果面板按钮、流式转换和写回逻辑按现有架构实现；未复制 PopClip TypeScript 源码。
- 验证：
  - `swift test --filter SelectionResultViewModelTests`
  - `swift test --filter TextTransformServiceTests`

## Selection Actions planned sources

后续划词动作实现继续优先检查 `docs/third-party-selection-actions.md`，优先搬运许可证兼容的 P0 来源。每次新增复制 / 改写第三方源码时，必须在本文件追加上游项目、commit、许可证、文件清单、本地目标路径和不原样搬运原因。

## Mashangxie iOS Keyboard

iOS 输入法原型和中文输入链路位于 `Apps/VoxFlowiOS/`。完整 iOS 第三方声明维护在
`Apps/VoxFlowiOS/THIRD_PARTY_NOTICES.md`；本节记录主仓库许可证索引里的摘要，确保 App
内“开源许可证”链接可以覆盖 iOS 端参考/搬运来源。

### Dictus iOS

- 上游项目：getdictus/dictus-ios
- 上游 URL：https://github.com/getdictus/dictus-ios
- 上游 commit：7264b1d892adfddd1d9cf3a5f7c4debb37b00019
- 许可证：MIT
- 版权：Copyright (c) 2026 PIVI Solutions
- 本地目标路径：
  - `Apps/VoxFlowiOS/Keyboard/`
  - `Apps/VoxFlowiOS/Shared/`
  - `Apps/VoxFlowiOS/VoxFlowiOS/Views/`
  - `Apps/VoxFlowiOS/VoxFlowiOS/Dictation/`
- 复制 / 改写行为：
  - Keyboard Extension UI、键盘状态机、App Group / Darwin notification 桥接、录音 overlay、日志和设置页外壳。
  - 本地改动主要替换 ASR provider 桥接、品牌主题、本地化、中文键盘入口和云端凭证 dev 注入。

### Hamster

- 上游项目：imfuxiao/Hamster
- 上游 URL：https://github.com/imfuxiao/Hamster
- 上游 commit：65693706d01fc6c19ed6071968e542b0a2ef3f36
- 许可证：MIT
- 版权：Copyright (c) 2025 xiao.fu
- 本地目标路径：
  - `Apps/VoxFlowiOS/ChineseInput/Upstream/HamsterKit/`
  - `Apps/VoxFlowiOS/ChineseInput/Upstream/HamsterKeyboardKit/`
  - `Apps/VoxFlowiOS/ChineseInput/Sources/`
- 复制 / 改写行为：
  - T9 拼音映射、候选模型、RimeContext 相关结构、中文 26 键 / 9 键布局参考和 Rime schema 部署思路。
  - 本地改动将 Hamster 中文输入能力接入 Dictus 风格键盘壳层。

### LibrimeKit / Rime native bundle

- 上游项目：amorphobia/LibrimeKit
- 上游 URL：https://github.com/amorphobia/LibrimeKit
- native bundle 来源：https://github.com/amorphobia/LibrimeKit/releases/download/v0.1.0/Frameworks.tgz
- 本地目标路径：
  - `Apps/VoxFlowiOS/ChineseInput/Frameworks/`
  - `Apps/VoxFlowiOS/ChineseInput/RimeKitObjC/`
  - `Apps/VoxFlowiOS/ChineseInput/Upstream/RimeKit/`
- 复制 / 改写行为：
  - iOS 端 Rime 原生运行时桥接和 xcframework 依赖，用于中文 26 键、9 键和候选词。
- 依赖许可证摘要：
  - `librime`：BSD-3-Clause
  - `boost_atomic`、`boost_filesystem`、`boost_regex`、`boost_system`：Boost Software License
  - `libglog`：BSD-3-Clause
  - `libleveldb`：BSD-3-Clause
  - `libmarisa`：BSD-style license
  - `libopencc`：Apache-2.0
  - `libyaml-cpp`：MIT

发布前需要按最终嵌入的二进制依赖重新审计完整 license text，并同步到 App 内许可证说明。

### Rime Ice Schema Data

- 上游项目：iDvel/rime-ice
- 上游 URL：https://github.com/iDvel/rime-ice
- 上游 revision：846e5fcae56f0e3f4dcd8570319ffaf377e15471
- 许可证：GPL-3.0
- 本地目标路径：
  - `Apps/VoxFlowiOS/ChineseInput/Resources/Schemas/`
- 复制 / 改写行为：
  - `rime_ice.schema.yaml`、`rime_ice.dict.yaml`、`t9.schema.yaml`、依赖 schema、词典、Lua helper、OpenCC 和 emoji 资源。
  - iOS 端默认中文 26 键使用雾凇拼音；9 键使用上游 `t9.schema.yaml` 继承雾凇词典并通过 Rime speller algebra 处理数字输入。

## sadopc/ScreenCapture

- 上游项目：sadopc/ScreenCapture
- 上游 URL：https://github.com/sadopc/ScreenCapture
- 上游 commit：081cb96b5c9f4bf72ace9187205009c92ab15f8c
- 许可证：MIT
- 版权：Copyright (c) 2026 Serdar Albayrak
- 复制 / 改写文件：
  - `ScreenCapture/Models/Annotation.swift`
  - `ScreenCapture/Features/Annotations/AnnotationTool.swift`
  - `ScreenCapture/Services/ImageExporter.swift`
- 本地目标路径：
  - `Sources/VoxFlowScreenshotKit/Annotations/AnnotationDocument.swift`
  - `Sources/VoxFlowScreenshotKit/Annotations/AnnotationTools.swift`
  - `Sources/VoxFlowScreenshotKit/Annotations/AnnotationRenderer.swift`

后续可能复制 / 改写的候选文件：

- `ScreenCapture/Features/Capture/CaptureManager.swift`
- `ScreenCapture/Features/Capture/DisplaySelector.swift`
- `ScreenCapture/Features/Capture/ScreenDetector.swift`
- `ScreenCapture/Features/Capture/SelectionOverlayWindow.swift`
- `ScreenCapture/Features/Preview/AnnotationCanvas.swift`
- `ScreenCapture/Features/Preview/PreviewContentView.swift`
- `ScreenCapture/Features/Preview/PreviewViewModel.swift`
- `ScreenCapture/Features/Preview/PreviewWindow.swift`
- `ScreenCapture/Features/Annotations/AnnotationTool.swift`
- `ScreenCapture/Features/Annotations/ArrowTool.swift`
- `ScreenCapture/Features/Annotations/FreehandTool.swift`
- `ScreenCapture/Features/Annotations/RectangleTool.swift`
- `ScreenCapture/Features/Annotations/TextTool.swift`
- `ScreenCapture/Models/Annotation.swift`
- `ScreenCapture/Models/DisplayInfo.swift`
- `ScreenCapture/Models/ExportFormat.swift`
- `ScreenCapture/Models/Screenshot.swift`
- `ScreenCapture/Models/Styles.swift`
- `ScreenCapture/Services/ImageExporter.swift`
- `ScreenCapture/Extensions/CGImage+Extensions.swift`
- `ScreenCapture/Extensions/NSImage+Extensions.swift`
- `ScreenCapture/Extensions/View+Cursor.swift`

MIT 许可证文本：

```text
MIT License

Copyright (c) 2026 Serdar Albayrak (albayrak.serdar8@gmail.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## tokuhirom/ShotShot

- 上游项目：tokuhirom/ShotShot
- 上游 URL：https://github.com/tokuhirom/ShotShot
- 上游 commit：c600d978c3ba1cce72c26e8af19e3bca155d0e15
- 许可证：MIT
- 复制 / 改写文件：
  - `shotshot/Features/Capture/SelectionOverlay.swift`
  - `shotshot/Features/Capture/CaptureManager.swift`
  - `shotshot/Features/Editor/AnnotationCanvas.swift`
  - `shotshot/Features/Editor/EditorViewModel.swift`
- 本地目标路径：
  - `Sources/VoxFlowScreenshotKit/Selection/SelectionWindowTargetResolver.swift`
  - `Sources/VoxFlowScreenshotKit/Selection/SelectionOverlayController.swift`
  - `Sources/VoxFlowScreenshotKit/Annotations/AnnotationDocument.swift`
  - `Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift`
  - `Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorViewModel.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScreenCaptureWindowExclusion.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScreenCaptureFrameProvider.swift`

## sw33tLie/macshot

- 上游项目：sw33tLie/macshot
- 上游 URL：https://github.com/sw33tLie/macshot
- 上游 commit：b8ebcb454f957fda011821fbf9c104580592d135
- 许可证：GPLv3
- GPLv3 范围行为署名：VoxFlow 明确把这些借用的交互语义记录为 GPLv3 派生行为。本地文件保留显式源码注释，便于后续编辑时看清边界。
- 本地 GPLv3 范围目标：
  - `Sources/VoxFlowScreenshotKit/Selection/SelectionOverlayController.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotHUDPanel.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotPreviewPanel.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotStitcher.swift`
- 复制 / 改写行为：
  - `macshot/UI/Overlay/OverlayView.swift` 的 `F` 键全屏选择行为。
  - `macshot/UI/Overlay/OverlayView.swift` 的 `Tab` 键窗口吸附开关行为。
  - `macshot/UI/Overlay/OverlayView.swift` 的标注套索 / 框选多选行为。
  - `macshot/Capture/ScrollCaptureController.swift` 的目标应用激活、手动滚动捕获、滚动中即时采样、节流后 pending 补帧、停滚后 settled 补帧、Vision 位移拼接、sticky header / scrollbar 排除和停止清理行为。
  - `macshot/UI/Overlay/ScrollCaptureHUDView.swift` 的独立 HUD 停止控件行为。
  - `macshot/UI/Overlay/ScrollCapturePreviewPanel.swift` 的选区旁实时长图预览行为。
  - `macshot/UI/Overlay/OverlayView.swift` 的滚动捕获期间 overlay 透传和 mouseMoved 抑制行为，避免目标 app hover 状态影响拼接。
- 修改说明：
  - VoxFlow 保留自有的 controller/window 抽象，只改写按键驱动的交互语义。
  - VoxFlow 在所有 overlay 窗口之间同步窗口目标开关，保证多屏捕获一致性。
  - 带修饰键的 `F`/`Tab` 事件会被忽略，避免与系统或 app 快捷键冲突。
  - VoxFlow 用选择工具的空白拖动做框选，Shift 拖动扩展当前选区。
  - VoxFlow 支持用户手动滚动，也保留一个简化的自动滚动按钮；自动滚动模拟滚轮不再移动鼠标位置，以符合 VoxFlow 当前交互要求。
  - VoxFlow 将完成后的长图接入既有 `InteractiveScreenshotCaptureResult`，继续复用 OCR、翻译、复制和保存链路。

### Scroll Capture Optimization Follow-up

- Copied / adapted behavior:
  - settled frame capture using CPU-backed frame comparison;
  - continuous match-failure tracking;
  - sticky header exclusion;
  - scrollbar/right-margin exclusion;
  - synthetic auto-scroll button behavior;
  - auto-scroll stop-on-zero-shift behavior.
- Local target files:
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotController.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotStitcher.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotHUDPanel.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotAutoScroller.swift`
  - `Sources/VoxFlowScreenshotKit/Capture/ScrollingScreenshotFrameAnalysis.swift`

## xocialize/qwen3-asr-mlx-swift（Confucius4-R2T2 本机流式 runtime）

- 上游项目：xocialize/qwen3-asr-mlx-swift
- 上游 URL：https://github.com/xocialize/qwen3-asr-mlx-swift
- 上游 commit：`7c8768ead04c886489e62929f2c23902b99631ab`（2026-10-01）
- 许可证：MIT（Copyright (c) 2026 xocialize）
- 引入方式：整体 vendored 到项目内隔离包 `Packages/VoxFlowR2T2Core`，不是 SwiftPM 远程依赖
- 许可证与归属文件：
  - `Packages/VoxFlowR2T2Core/LICENSE`
  - `Packages/VoxFlowR2T2Core/NOTICE`
  - `Packages/VoxFlowR2T2Core/PROVENANCE.md`（上游来源、本地全部改动、整改理由）
- 本地改动：
  - 包定义：`swift-tools-version` 6.2 → 6.1；`mlx-swift` 收敛到项目现有 `0.31.4`；丢弃上游 `qwen3asr-gates` 可执行 target。
  - 命名：module / product / 目录 `Qwen3ASR` → `VoxFlowR2T2Core`（上游同名 module 与项目既有 `speech-swift` 冲突）。
  - 源码：仅 `R2T2Stream.finish()` 的尾部冲刷条件与诊断 `steps` 的记录上限两处，其余与上游逐字节一致；细节见 `PROVENANCE.md`。
  - 新增 `R2T2StreamPolicy`（把上述两处决策抽成可脱离模型权重测试的纯函数）。
- 打包：`LICENSE` / `NOTICE` 经 `make build` / `make build-native` / `make build-dev` 复制到 `VoxFlow.app/Contents/Resources/ThirdPartyNotices/VoxFlowR2T2Core-{LICENSE,NOTICE}.txt`。
- 上游衍化来源（上游 `NOTICE` 原文声明）：
  - Blaizzy/mlx-audio-swift（MIT，Copyright (c) 2025 Prince Canuma）
  - netease-youdao/Confucius4-R2T2 `r2t2/r2t2_asr.py`、`example.py`、`ws_server.py`（Apache-2.0，Copyright 2026 The NetEase Youdao team）
- 与权重许可的关系：以上只覆盖**推理代码**。`mlx-community/Confucius4-R2T2-8bit` 权重适用 **NetEase Youdao Model Use License Agreement**，不由本项目再分发；`LICENSE`、`MODEL_LICENSE_zh`、`NOTICE` 由 ModelStore 随权重下载到用户本机，见 `docs/resource-ownership.md`。
- 验证：
  - `make test-r2t2-core`
  - `swift test --filter VoxFlowProviderR2T2Tests`
  - `make build-dev`（确认 `Contents/Resources/ThirdPartyNotices/` 已生成）

## k2-fsa/sherpa-onnx（本地 ASR 运行时，含 FireRedASR2-AED 接入）

- 上游项目：k2-fsa/sherpa-onnx
- 上游 URL：https://github.com/k2-fsa/sherpa-onnx
- 许可证：Apache License 2.0（`https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/master/LICENSE`，2026-10-05 取回校验）
- 引入方式：
  - 预编译静态库 `Vendor/sherpa-onnx.xcframework/macos-arm64_x86_64/`（`libsherpa-onnx.a`、`libonnxruntime.a`、`Headers/`），由 `Package.swift` 的 `CSherpaOnnx` target 通过 `-LVendor/sherpa-onnx.xcframework/macos-arm64_x86_64 -lsherpa-onnx` 链接。归档内可检出的最高版本标记为 `1.13.3`，仓库内没有独立版本清单文件。
  - C 桥接层 `Vendor/CSherpaOnnx/CSherpaOnnx.c` + `include/vox-sherpa.h` 是本项目自有的薄封装（`VoxSherpaModelConfig` → `SherpaOnnxOfflineRecognizerConfig`），不是上游文件。
- 使用范围：`VoxFlowProviderFunASR`、`VoxFlowProviderParaformer`、`VoxFlowProviderSenseVoice`、`VoxFlowProviderFireRedASR` 四个本机 Provider；此外 App 壳层仍保留已停止使用的 `SherpaOnnxRecognizer`/`SherpaBatchASREngine` 历史路径。
- 本地改动（FireRedASR2-AED 接入新增，仅追加、不改动既有分支）：
  - `vox-sherpa.h`：新增 `VOX_SHERPA_FIRE_RED_ASR_CTC = 3`、`VOX_SHERPA_FIRE_RED_ASR = 4` 两个模型类型枚举值（原有 0/1/2 不变）。
  - `CSherpaOnnx.c`：新增两个 `switch` 分支，分别填充 `model_config.fire_red_asr_ctc.{model,tokens}` 与 `model_config.fire_red_asr.{encoder,decoder,tokens}`；既有 `VOX_SHERPA_FUNASR_NANO` / `VOX_SHERPA_PARAFORMER` / `VOX_SHERPA_SENSE_VOICE` 分支未改动。
- 验证：
  - `make architecture-check`
  - `xcrun swift build --target VoxFlowProviderFireRedASR`
  - `swift test --filter VoxFlowProviderFireRedASRTests`

## FireRedASR2-AED 权重的完整性与磁盘门槛

- 归档自身 sha256：`43015b3f1643a5688b4821e8ed323473d38b798c4ec291471fe00df1bcfc4f1c`（838,589,068 B），在解包**之前**校验。
- 解包产物逐文件 size + sha256：见 `FireRedASRModel.componentDigests`，由共享的 `ModelIntegrityValidator` 在 `ModelAtomicInstaller` 换入前校验。
- 磁盘门槛：归档 + 解包结果需**同时**存在，即 `FireRedASRManifestCatalog.requiredDiskBytes`（≈2.07 GB）。空间不足时在发起任何网络请求之前失败，复用 `ModelDownloadError.insufficientDisk` 的既有文案。
- 内存门槛：`FireRedASRManifestCatalog.minimumMemoryBytes = 16 GB`，由 `FireRedASRRuntimePreflight` 拦截；不足时 Provider 报结构化 `.hardwareUnsupported`，不加载权重。

## FireRedASR2-AED 权重（上游 FireRedTeam）

- 上游模型仓库：https://www.modelscope.cn/models/FireRedTeam/FireRedASR2-AED
- 上游代码仓库：https://github.com/FireRedTeam/FireRedASR
- 许可证：Apache License 2.0（`https://raw.githubusercontent.com/FireRedTeam/FireRedASR/main/LICENSE`，2026-10-05 取回校验，为标准 Apache-2.0 全文）
- 分发方式：**既不再分发也不再打包**。权重由用户在设置页显式发起下载后，经 `FireRedASRManifestCatalog`（固定 URL + 逐组件 sha256）与 `FireRedASRModelStoreDownloader`（下载 → 归档 sha256 → 解包 → 逐组件校验 → 原子换入）安装到 `~/Library/Application Support/VoxFlow/models/fireredasr-aed-int8/<版本目录>/`；进入 App bundle 或仓库的只有 URL、文件大小与 hash 常量。
- 本项目使用的资产：`sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2`
  - 来源：`https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2`
  - SHA-256：`43015b3f1643a5688b4821e8ed323473d38b798c4ec291471fe00df1bcfc4f1c`（838,589,068 B）
  - 解包后必需文件：`encoder.int8.onnx`（817,286,833 B，`54048d66b6e8f3c80ea7ce95efe794587b0fd81d7271651d0decd3803852ae82`）、`decoder.int8.onnx`（417,291,928 B，`b840ce7196ae4a14d05ae84bbf56082b6b61ccec5610fda907dddbcea37354ff`）、`tokens.txt`（79,172 B，`1bc613de2112d257e61a349c3e72d1b1a9cf19c33d3ca954197ad2171e5ea07b`）
  - 该 tar.bz2 **不包含任何 LICENSE / NOTICE 文件**，唯一的说明文件是 107 B 的 `README.md`，内容只是「Model files are converted from <ModelScope 链接>」。因此「FireRedASR2-AED 权重适用 Apache-2.0」目前是基于上游代码仓库许可证的推断，不是权重资产自带声明。
- 与代码许可的关系：`FireRedTeam/FireRedASR` 代码仓库的 Apache-2.0 只覆盖上游代码；权重资产的许可条款需要在发布前单独确认（见下）。
- 发布前待确认：权重资产的实际许可条款与再分发条件。若结论是无法随 App 分发，当前实现不受影响（权重由用户在运行时自行下载）；若结论是需要在应用内展示许可，则需要在设置页补充归属展示。
- 详见 `docs/fireredasr-integration-research.md`（选型、实测数据与拒绝的备选路线）。
