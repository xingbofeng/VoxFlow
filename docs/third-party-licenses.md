# 第三方许可

本文记录 VoxFlow 复制或大量改写的第三方源码。

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
- 上游 commit：34c9999625cfe9e8999c00358b3c172dfc00380c
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
  - `macshot/Capture/ScrollCaptureController.swift` 的手动滚动捕获、连续采样、Vision 位移拼接和停止清理行为。
  - `macshot/UI/Overlay/ScrollCaptureHUDView.swift` 的独立 HUD 停止控件行为。
  - `macshot/UI/Overlay/ScrollCapturePreviewPanel.swift` 的选区旁实时长图预览行为。
- 修改说明：
  - VoxFlow 保留自有的 controller/window 抽象，只改写按键驱动的交互语义。
  - VoxFlow 在所有 overlay 窗口之间同步窗口目标开关，保证多屏捕获一致性。
  - 带修饰键的 `F`/`Tab` 事件会被忽略，避免与系统或 app 快捷键冲突。
  - VoxFlow 用选择工具的空白拖动做框选，Shift 拖动扩展当前选区。
  - VoxFlow 仅保留用户手动滚动模式，不复制 macshot 的自动滚动按钮和模拟滚轮行为。
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
