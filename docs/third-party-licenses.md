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
