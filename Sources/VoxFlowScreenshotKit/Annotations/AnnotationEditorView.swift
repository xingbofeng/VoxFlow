import AppKit
import CoreGraphics
import SwiftUI

public enum AnnotationEditorTool: Equatable, Sendable {
    case select
    case pen
    case ellipse
    case rectangle
    case arrow
    case dotMarker
    case numberedMarker
    case text
    case mosaic
}

public struct AnnotationEditorView: View {
    @ObservedObject private var viewModel: AnnotationEditorViewModel
    private let onComplete: (CGImage) -> Void
    private let onCancel: () -> Void
    private let onError: (Error) -> Void

    @State private var selectedTool: AnnotationEditorTool = .select
    @State private var dragMode: AnnotationDragMode = .none
    @State private var lastDragImagePoint: CGPoint?
    @State private var marqueeSelectionRect: CGRect?
    @State private var mosaicBrushPreviewPoint: CGPoint?
    private static let toolbarItemSize: CGFloat = SelectionToolbarPresentation.default.itemSize
    private static let mosaicBrushSize: CGFloat = 40

    public init(
        viewModel: AnnotationEditorViewModel,
        onComplete: @escaping (CGImage) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.onError = onError
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            imagePreview
                .padding(18)

            toolbar
                .padding(.bottom, 18)
        }
        .frame(minWidth: 640, minHeight: 320)
        .background(.clear)
        .focusable()
        .onExitCommand {
            cancel()
        }
        .onKeyPress(.return) {
            complete()
            return .handled
        }
        .onKeyPress(.delete) {
            viewModel.deleteSelectedElement()
            return .handled
        }
        .onKeyPress { key in
            handleKeyboardShortcut(key)
        }
    }

    private var imagePreview: some View {
        GeometryReader { geometry in
            let projection = AnnotationCanvasProjection(
                imageSize: imageSize,
                containerSize: geometry.size
            )
            ZStack(alignment: .topLeading) {
                Image(nsImage: NSImage(cgImage: viewModel.image, size: imageSize))
                    .resizable()
                    .frame(width: projection.fittedImageRect.width, height: projection.fittedImageRect.height)
                    .position(x: projection.fittedImageRect.midX, y: projection.fittedImageRect.midY)

                AnnotationElementOverlay(document: viewModel.document, projection: projection, selectedTool: selectedTool)

                AnnotationMarqueeSelectionOverlay(rect: marqueeSelectionRect, projection: projection)

                MosaicBrushPreviewOverlay(
                    point: mosaicBrushPreviewPoint,
                    brushSize: Self.mosaicBrushSize,
                    projection: projection
                )

                textEditingOverlay(projection: projection)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: selectedTool.minimumGestureDistance)
                    .onChanged { value in
                        handleDragChanged(value, projection: projection)
                    }
                    .onEnded { value in
                        handleDragEnded(value, projection: projection)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updateMosaicBrushPreview(at: location, projection: projection)
                case .ended:
                    mosaicBrushPreviewPoint = nil
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
        }
        .aspectRatio(imageSize, contentMode: .fit)
    }

    @ViewBuilder
    private func textEditingOverlay(projection: AnnotationCanvasProjection) -> some View {
        if let draft = viewModel.textEditingDraft {
            let editorSize = textEditorSize(for: draft)
            let viewPoint = projection.viewPoint(fromImagePoint: draft.position)
            IMEAwareTextEditor(
                text: Binding(
                    get: { viewModel.textEditingDraft?.displayText ?? "" },
                    set: { viewModel.updateTextEditingDisplayText($0) }
                ),
                displayText: Binding(
                    get: { viewModel.textEditingDraft?.displayText ?? "" },
                    set: { viewModel.updateTextEditingDisplayText($0) }
                ),
                font: NSFont(name: draft.style.fontName, size: draft.style.fontSize * projection.scale)
                    ?? .systemFont(ofSize: draft.style.fontSize * projection.scale),
                textColor: draft.style.color.nsColor,
                onCommit: viewModel.commitTextEditing,
                onCancel: viewModel.cancelTextEditing
            )
            .frame(width: editorSize.width * projection.scale, height: editorSize.height * projection.scale)
            .position(
                x: viewPoint.x + editorSize.width * projection.scale / 2,
                y: viewPoint.y + editorSize.height * projection.scale / 2
            )
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value, projection: AnnotationCanvasProjection) {
        guard viewModel.textEditingDraft == nil,
              let imageStart = projection.imagePoint(fromViewPoint: value.startLocation),
              let imagePoint = projection.imagePoint(fromViewPoint: value.location) else {
            return
        }

        if dragMode == .none {
            switch selectedTool {
            case .select:
                let isShiftSelecting = NSEvent.modifierFlags.contains(.shift)
                if let selected = selectedElement(),
                   !isShiftSelecting,
                   let handle = resizeHandleHitTest(element: selected, viewPoint: value.startLocation, projection: projection) {
                    viewModel.beginUndoGroup()
                    dragMode = .resizing(handle)
                } else if let hitID = viewModel.document.hitTestElement(at: imageStart) {
                    if isShiftSelecting {
                        viewModel.toggleElementSelection(id: hitID)
                        dragMode = .selectingEmpty
                    } else {
                        if !viewModel.document.selectedElementIDs.contains(hitID) {
                            viewModel.selectElement(id: hitID)
                        }
                        viewModel.beginUndoGroup()
                        dragMode = .moving
                        lastDragImagePoint = imageStart
                    }
                } else {
                    marqueeSelectionRect = CGRect(origin: imageStart, size: .zero)
                    dragMode = .marqueeSelecting(isShiftSelecting)
                }
            case .text:
                dragMode = .drawing
            default:
                viewModel.selectElement(id: nil)
                dragMode = .drawing
            }
        }

        if selectedTool == .mosaic {
            mosaicBrushPreviewPoint = imagePoint
        }

        switch dragMode {
        case .moving:
            guard let lastDragImagePoint else { return }
            viewModel.moveSelectedElement(by: CGSize(
                width: imagePoint.x - lastDragImagePoint.x,
                height: imagePoint.y - lastDragImagePoint.y
            ), recordsUndo: false)
            self.lastDragImagePoint = imagePoint
        case .resizing(let handle):
            viewModel.resizeSelectedElement(handle: handle, to: imagePoint, recordsUndo: false)
        case .marqueeSelecting:
            let normalizedRect = normalizedRect(from: imageStart, to: imagePoint)
            marqueeSelectionRect = normalizedRect
        case .none, .drawing, .selectingEmpty:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, projection: AnnotationCanvasProjection) {
        defer {
            dragMode = .none
            lastDragImagePoint = nil
            marqueeSelectionRect = nil
        }
        guard let imageStart = projection.imagePoint(fromViewPoint: value.startLocation),
              let imageEnd = projection.imagePoint(fromViewPoint: value.location) else {
            if selectedTool == .mosaic {
                mosaicBrushPreviewPoint = nil
            }
            return
        }
        if selectedTool == .mosaic {
            mosaicBrushPreviewPoint = imageEnd
        }
        let constrainedEnd = AnnotationDragConstraint.constrainedEndPoint(
            start: imageStart,
            end: imageEnd,
            tool: selectedTool,
            isShiftPressed: NSEvent.modifierFlags.contains(.shift)
        )

        switch selectedTool {
        case .select:
            switch dragMode {
            case .marqueeSelecting(let isShiftSelecting):
                let marqueeRect = normalizedRect(from: imageStart, to: imageEnd)
                viewModel.selectElements(in: marqueeRect, extendingSelection: isShiftSelecting)
            case .selectingEmpty:
                viewModel.selectElement(id: nil)
            default:
                break
            }
        case .text:
            if dragMode == .drawing {
                viewModel.beginTextEditing(at: imageEnd)
            }
        default:
            if dragMode == .drawing {
                addAnnotation(from: imageStart, to: constrainedEnd)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolButton(.select, systemName: "cursorarrow", help: ScreenshotL10n.ScreenshotKit.Toolbar.select)
            toolButton(.pen, systemName: "pencil.tip", help: ScreenshotL10n.ScreenshotKit.Toolbar.pen)
            toolButton(.ellipse, systemName: "circle", help: ScreenshotL10n.ScreenshotKit.Toolbar.circle)
            toolButton(.rectangle, systemName: "rectangle", help: ScreenshotL10n.ScreenshotKit.Toolbar.rectangle)
            toolButton(.arrow, systemName: "arrow.up.right", help: ScreenshotL10n.ScreenshotKit.Toolbar.arrow)
            toolButton(.dotMarker, systemName: "smallcircle.filled.circle", help: ScreenshotL10n.ScreenshotKit.Toolbar.pointMarker)
            toolButton(.numberedMarker, systemName: "1.circle", help: ScreenshotL10n.ScreenshotKit.Toolbar.numberedMarker)
            toolButton(.text, systemName: "t.square", help: ScreenshotL10n.ScreenshotKit.Toolbar.text)
            toolButton(.mosaic, systemName: "checkerboard.rectangle", help: ScreenshotL10n.ScreenshotKit.Toolbar.mosaic)
            Divider().frame(height: 18)
            colorButton
            lineWidthButton
            fontSizeButton
            commandButton(systemName: "doc.on.doc", help: ScreenshotL10n.ScreenshotKit.Toolbar.copy, action: viewModel.copySelectedElement)
            commandButton(systemName: "doc.on.clipboard", help: ScreenshotL10n.ScreenshotKit.Toolbar.paste) {
                viewModel.pasteCopiedElement()
            }
            commandButton(systemName: "plus.square.on.square", help: ScreenshotL10n.ScreenshotKit.Toolbar.duplicate) {
                viewModel.duplicateSelectedElement()
            }
            commandButton(systemName: "square.and.arrow.down", help: ScreenshotL10n.ScreenshotKit.Toolbar.download, action: download)
            commandButton(systemName: "arrow.uturn.backward", help: ScreenshotL10n.ScreenshotKit.Toolbar.undo, action: viewModel.undo)
            commandButton(systemName: "arrow.uturn.forward", help: ScreenshotL10n.ScreenshotKit.Toolbar.redo, action: viewModel.redo)
            commandButton(systemName: "xmark", help: ScreenshotL10n.ScreenshotKit.Toolbar.cancel, action: cancel)
            commandButton(systemName: "checkmark", help: ScreenshotL10n.ScreenshotKit.Toolbar.complete, action: complete)
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.primary)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.green.opacity(0.28), lineWidth: 1)
        )
    }

    private func toolButton(
        _ tool: AnnotationEditorTool,
        systemName: String,
        help: String
    ) -> some View {
        Button {
            selectedTool = tool
            if tool != .mosaic {
                mosaicBrushPreviewPoint = nil
            }
        } label: {
            Image(systemName: systemName)
                .frame(width: Self.toolbarItemSize, height: Self.toolbarItemSize)
        }
        .help(help)
    }

    private func commandButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: Self.toolbarItemSize, height: Self.toolbarItemSize)
        }
        .help(help)
    }

    private var colorButton: some View {
        styleStateButton(help: ScreenshotL10n.ScreenshotKit.Toolbar.color, action: cycleColor) {
            Circle()
                .fill(viewModel.currentStyle.color.swiftUIColor)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 0.5))
                .frame(width: Self.toolbarItemSize, height: Self.toolbarItemSize)
        }
    }

    private var lineWidthButton: some View {
        styleStateButton(help: ScreenshotL10n.ScreenshotKit.Toolbar.lineWidth, action: cycleLineWidth) {
            Text("\(Int(viewModel.currentStyle.lineWidth))")
                .font(.system(size: 13, weight: .bold))
                .frame(width: Self.toolbarItemSize, height: Self.toolbarItemSize)
        }
    }

    private var fontSizeButton: some View {
        styleStateButton(help: ScreenshotL10n.ScreenshotKit.Toolbar.fontSize, action: cycleFontSize) {
            Text(Self.fontSizeLabel(for: viewModel.currentTextStyle.fontSize))
                .font(.system(size: 13, weight: .bold))
                .frame(width: Self.toolbarItemSize, height: Self.toolbarItemSize)
        }
    }

    private func styleStateButton(
        help: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action, label: label)
            .help(help)
    }

    private var imageSize: CGSize {
        CGSize(width: viewModel.image.width, height: viewModel.image.height)
    }

    private func cycleColor() {
        let palette: [ScreenshotAnnotationColor] = [.voxGreen, .red, .white, .black]
        let currentIndex = palette.firstIndex(of: viewModel.currentStyle.color) ?? 0
        viewModel.setAnnotationColor(palette[(currentIndex + 1) % palette.count])
    }

    private func cycleLineWidth() {
        let widths: [CGFloat] = [6, 8, 10]
        let currentIndex = widths.firstIndex(of: viewModel.currentStyle.lineWidth) ?? 0
        viewModel.setLineWidth(widths[(currentIndex + 1) % widths.count])
    }

    private func cycleFontSize() {
        let sizes = Self.fontSizeOptions
        let currentIndex = sizes.firstIndex(of: viewModel.currentTextStyle.fontSize) ?? 0
        viewModel.setFontSize(sizes[(currentIndex + 1) % sizes.count])
    }

    /// 与 SelectionOverlayController.popoverFontSizes / popoverFontSizeLabels 保持同步。
    static let fontSizeOptions: [CGFloat] = [14, 24, 32]
    static var fontSizeOptionLabels: [String] {
        [
            ScreenshotL10n.ScreenshotKit.Annotation.Font.small,
            ScreenshotL10n.ScreenshotKit.Annotation.Font.medium,
            ScreenshotL10n.ScreenshotKit.Annotation.Font.large,
        ]
    }

    static func fontSizeLabel(for size: CGFloat) -> String {
        if let idx = fontSizeOptions.firstIndex(where: { abs($0 - size) < 0.01 }) {
            return fontSizeOptionLabels[idx]
        }
        return fontSizeOptionLabels[0]
    }

    private func handleKeyboardShortcut(_ key: KeyPress) -> KeyPress.Result {
        let modifiers = key.modifiers
        let character = key.characters.lowercased()
        guard modifiers.contains(.command),
              !character.isEmpty else {
            return .ignored
        }

        switch character {
        case "c":
            viewModel.copySelectedElement()
            return .handled
        case "v":
            viewModel.pasteCopiedElement()
            return .handled
        case "d":
            viewModel.duplicateSelectedElement()
            return .handled
        case "z":
            if modifiers.contains(.shift) {
                viewModel.redo()
            } else {
                viewModel.undo()
            }
            return .handled
        default:
            return .ignored
        }
    }

    private func download() {
        do {
            try viewModel.download()
        } catch {
            onError(error)
        }
    }

    private func cancel() {
        viewModel.cancel()
        onCancel()
    }

    private func complete() {
        do {
            onComplete(try viewModel.complete())
        } catch {
            onError(error)
        }
    }

    private func addAnnotation(from start: CGPoint, to end: CGPoint) {
        switch selectedTool {
        case .select:
            break
        case .pen:
            viewModel.add(.pen(FreehandAnnotationElement(points: [start, end], style: viewModel.currentStyle)))
        case .ellipse:
            viewModel.add(.ellipse(EllipseAnnotationElement(rect: normalizedRect(from: start, to: end), style: viewModel.currentStyle)))
        case .rectangle:
            viewModel.add(.rectangle(RectangleAnnotationElement(rect: normalizedRect(from: start, to: end), style: viewModel.currentStyle)))
        case .arrow:
            viewModel.add(.arrow(ArrowAnnotationElement(startPoint: start, endPoint: end, style: viewModel.currentStyle)))
        case .dotMarker:
            viewModel.add(.dotMarker(DotMarkerAnnotationElement(center: end, style: viewModel.currentStyle)))
        case .numberedMarker:
            let nextNumber = viewModel.document.elements.filter { $0.kind == .numberedMarker }.count + 1
            viewModel.add(.numberedMarker(NumberedMarkerAnnotationElement(center: end, number: nextNumber, style: viewModel.currentStyle)))
        case .text:
            viewModel.beginTextEditing(at: end)
        case .mosaic:
            viewModel.add(.mosaic(MosaicAnnotationElement(
                points: [start, end],
                brushSize: Self.mosaicBrushSize
            )))
        }
        if selectedTool != .select, selectedTool != .text {
            viewModel.selectElement(id: nil)
        }
    }

    private func updateMosaicBrushPreview(at viewPoint: CGPoint, projection: AnnotationCanvasProjection) {
        guard selectedTool == .mosaic,
              let imagePoint = projection.imagePoint(fromViewPoint: viewPoint) else {
            mosaicBrushPreviewPoint = nil
            return
        }
        mosaicBrushPreviewPoint = imagePoint
    }

    private func textEditorSize(for draft: TextEditingDraft) -> CGSize {
        let font = NSFont(name: draft.style.fontName, size: draft.style.fontSize)
            ?? .systemFont(ofSize: draft.style.fontSize)
        let displayText = draft.displayText.isEmpty ? ScreenshotL10n.ScreenshotKit.Annotation.Text.placeholder : draft.displayText
        let width = (displayText as NSString).size(withAttributes: [.font: font]).width + 28
        return CGSize(
            width: max(140, ceil(width)),
            height: max(36, ceil(draft.style.fontSize * 1.8))
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func selectedElement() -> AnnotationElement? {
        guard let selectedID = viewModel.document.selectedElementID else { return nil }
        return viewModel.document.elements.first { $0.id == selectedID }
    }

    private func resizeHandleHitTest(
        element: AnnotationElement,
        viewPoint: CGPoint,
        projection: AnnotationCanvasProjection
    ) -> AnnotationResizeHandle? {
        let handleSize: CGFloat = 16
        for (handle, point) in resizeHandles(for: element, projection: projection) {
            let rect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            if rect.contains(viewPoint) {
                return handle
            }
        }
        return nil
    }
}

enum AnnotationDragMode: Equatable {
    case none
    case drawing
    case moving
    case resizing(AnnotationResizeHandle)
    case selectingEmpty
    case marqueeSelecting(Bool)
}

public struct AnnotationCanvasProjection: Equatable, Sendable {
    public let imageSize: CGSize
    public let containerSize: CGSize

    public init(imageSize: CGSize, containerSize: CGSize) {
        self.imageSize = imageSize
        self.containerSize = containerSize
    }

    public var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return 1
        }
        return min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
    }

    public var fittedImageRect: CGRect {
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    public func imagePoint(fromViewPoint point: CGPoint) -> CGPoint? {
        guard fittedImageRect.contains(point) else {
            return nil
        }
        return CGPoint(
            x: (point.x - fittedImageRect.minX) / scale,
            y: (point.y - fittedImageRect.minY) / scale
        )
    }

    public func viewPoint(fromImagePoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: fittedImageRect.minX + point.x * scale,
            y: fittedImageRect.minY + point.y * scale
        )
    }

    public func viewRect(fromImageRect rect: CGRect) -> CGRect {
        CGRect(
            x: fittedImageRect.minX + rect.minX * scale,
            y: fittedImageRect.minY + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}

public enum AnnotationDragConstraint {
    public static func constrainedEndPoint(
        start: CGPoint,
        end: CGPoint,
        tool: AnnotationEditorTool,
        isShiftPressed: Bool
    ) -> CGPoint {
        guard isShiftPressed else { return end }

        switch tool {
        case .rectangle, .ellipse:
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            let side = max(abs(deltaX), abs(deltaY))
            return CGPoint(
                x: start.x + (deltaX < 0 ? -side : side),
                y: start.y + (deltaY < 0 ? -side : side)
            )
        case .arrow:
            return snapToNearest45Degrees(start: start, end: end)
        default:
            return end
        }
    }

    private static func snapToNearest45Degrees(start: CGPoint, end: CGPoint) -> CGPoint {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        guard deltaX != 0 || deltaY != 0 else { return end }

        let octant = Int(round(atan2(deltaY, deltaX) / (.pi / 4)))
        let distance = max(abs(deltaX), abs(deltaY))
        switch ((octant % 8) + 8) % 8 {
        case 0:
            return CGPoint(x: start.x + distance, y: start.y)
        case 1:
            return CGPoint(x: start.x + distance, y: start.y + distance)
        case 2:
            return CGPoint(x: start.x, y: start.y + distance)
        case 3:
            return CGPoint(x: start.x - distance, y: start.y + distance)
        case 4:
            return CGPoint(x: start.x - distance, y: start.y)
        case 5:
            return CGPoint(x: start.x - distance, y: start.y - distance)
        case 6:
            return CGPoint(x: start.x, y: start.y - distance)
        default:
            return CGPoint(x: start.x + distance, y: start.y - distance)
        }
    }
}

// IME-aware text editing adapted from tokuhirom/ShotShot (MIT), commit
// c600d978c3ba1cce72c26e8af19e3bca155d0e15. VoxFlow keeps the NSTextView
// bridge so Chinese/Japanese/Korean marked text is not lost during composition.
private struct IMEAwareTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var displayText: String
    let font: NSFont
    let textColor: NSColor
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 10000, height: 10000)
        textView.isFieldEditor = false
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        if context.coordinator.isFirstUpdate {
            nsView.string = text
            context.coordinator.isFirstUpdate = false
        }
        nsView.font = font
        nsView.textColor = textColor

        DispatchQueue.main.async {
            if nsView.window?.firstResponder != nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMEAwareTextEditor
        var isFirstUpdate = true
        private var didCancel = false

        init(_ parent: IMEAwareTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.displayText = textView.string
            parent.text = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            guard !didCancel,
                  let textView = notification.object as? NSTextView else {
                return
            }
            parent.text = textView.string
            parent.displayText = textView.string
            parent.onCommit()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.text = textView.string
                parent.displayText = textView.string
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                didCancel = true
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

private extension AnnotationEditorTool {
    var minimumGestureDistance: CGFloat {
        switch self {
        case .select, .dotMarker, .numberedMarker, .text:
            return 0
        default:
            return 2
        }
    }
}

private extension ScreenshotAnnotationColor {
    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

private struct AnnotationElementOverlay: View {
    let document: AnnotationDocument
    let projection: AnnotationCanvasProjection
    let selectedTool: AnnotationEditorTool

    var body: some View {
        Canvas { context, _ in
            for element in document.elements {
                draw(element, in: &context)
                if document.selectedElementIDs.contains(element.id) {
                    drawSelectionIndicator(for: element, in: &context)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ element: AnnotationElement, in context: inout GraphicsContext) {
        switch element {
        case .rectangle(let element):
            context.stroke(
                Path(projection.viewRect(fromImageRect: element.rect)),
                with: .color(element.style.color.swiftUIColor),
                lineWidth: element.style.lineWidth * projection.scale
            )
        case .ellipse(let element):
            context.stroke(
                Path(ellipseIn: projection.viewRect(fromImageRect: element.rect)),
                with: .color(element.style.color.swiftUIColor),
                lineWidth: element.style.lineWidth * projection.scale
            )
        case .mosaic(let element):
            let points = element.points.map(projection.viewPoint(fromImagePoint:))
            if points.count == 1, let point = points.first {
                let radius = element.brushSize * projection.scale / 2
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .color(.green.opacity(0.24))
                )
            } else if let first = points.first {
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(
                    path,
                    with: .color(.green.opacity(0.34)),
                    style: StrokeStyle(
                        lineWidth: element.brushSize * projection.scale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        case .dotMarker(let element):
            context.fill(
                Path(ellipseIn: projection.viewRect(fromImageRect: element.bounds)),
                with: .color(element.style.color.swiftUIColor)
            )
        case .numberedMarker(let element):
            let rect = projection.viewRect(fromImageRect: element.bounds)
            context.fill(Path(ellipseIn: rect), with: .color(element.style.color.swiftUIColor))
            context.draw(
                Text("\(element.number)").font(.system(size: max(8, element.radius * projection.scale), weight: .bold)).foregroundStyle(.white),
                at: CGPoint(x: rect.midX, y: rect.midY)
            )
        case .pen(let element):
            var path = Path()
            if let first = element.points.first {
                path.move(to: projection.viewPoint(fromImagePoint: first))
                for point in element.points.dropFirst() {
                    path.addLine(to: projection.viewPoint(fromImagePoint: point))
                }
            }
            context.stroke(path, with: .color(element.style.color.swiftUIColor), lineWidth: element.style.lineWidth * projection.scale)
        case .arrow(let element):
            var path = Path()
            path.move(to: projection.viewPoint(fromImagePoint: element.startPoint))
            path.addLine(to: projection.viewPoint(fromImagePoint: element.endPoint))
            context.stroke(path, with: .color(element.style.color.swiftUIColor), lineWidth: element.style.lineWidth * projection.scale)
        case .text(let element):
            context.draw(
                Text(element.content)
                    .font(.system(size: element.style.fontSize * projection.scale))
                    .foregroundStyle(element.style.color.swiftUIColor),
                at: projection.viewPoint(fromImagePoint: element.position),
                anchor: .topLeading
            )
        case .translatedOverlay(let element):
            // 译文覆盖：在编辑视图里按行画白底黑字，跟 AnnotationRenderer.renderTranslatedOverlay 视觉一致。
            for line in element.lines {
                let viewRect = projection.viewRect(fromImageRect: line.bounds)
                context.fill(Path(viewRect), with: .color(.white))
                let fontSize = max(8, viewRect.height * 0.8)
                context.draw(
                    Text(line.text)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(.black),
                    at: CGPoint(x: viewRect.midX, y: viewRect.midY),
                    anchor: .center
                )
            }
        }
    }

    private func drawSelectionIndicator(for element: AnnotationElement, in context: inout GraphicsContext) {
        guard selectedTool == .select else {
            return
        }
        guard element.kind != .mosaic else { return }
        let selectionRect = projection.viewRect(fromImageRect: element.bounds).insetBy(dx: -4, dy: -4)
        context.stroke(
            Path(selectionRect),
            with: .color(.green),
            style: StrokeStyle(lineWidth: 2, dash: [5, 3])
        )

        for (_, point) in resizeHandles(for: element, projection: projection) {
            let handleRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.fill(Path(handleRect), with: .color(.white))
            context.stroke(Path(handleRect), with: .color(.green), lineWidth: 1)
        }
    }
}

private struct AnnotationMarqueeSelectionOverlay: View {
    let rect: CGRect?
    let projection: AnnotationCanvasProjection

    var body: some View {
        Canvas { context, _ in
            guard let rect,
                  rect.width > 1,
                  rect.height > 1 else {
                return
            }
            let viewRect = projection.viewRect(fromImageRect: rect)
            context.fill(Path(viewRect), with: .color(.green.opacity(0.10)))
            context.stroke(
                Path(viewRect),
                with: .color(.green),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
        }
        .allowsHitTesting(false)
    }
}

private struct MosaicBrushPreviewOverlay: View {
    let point: CGPoint?
    let brushSize: CGFloat
    let projection: AnnotationCanvasProjection

    var body: some View {
        Canvas { context, _ in
            guard let point else {
                return
            }
            let center = projection.viewPoint(fromImagePoint: point)
            let radius = max(brushSize * projection.scale / 2, 1)
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(.green.opacity(0.16)))
            context.stroke(Path(ellipseIn: rect), with: .color(.green.opacity(0.78)), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

private func resizeHandles(
    for element: AnnotationElement,
    projection: AnnotationCanvasProjection
) -> [(AnnotationResizeHandle, CGPoint)] {
    switch element {
    case .arrow(let element):
        return [
            (.startPoint, projection.viewPoint(fromImagePoint: element.startPoint)),
            (.endPoint, projection.viewPoint(fromImagePoint: element.endPoint)),
        ]
    case .dotMarker(let element):
        return [
            (.endPoint, projection.viewPoint(fromImagePoint: CGPoint(x: element.center.x + element.radius, y: element.center.y)))
        ]
    case .numberedMarker(let element):
        return [
            (.endPoint, projection.viewPoint(fromImagePoint: CGPoint(x: element.center.x + element.radius, y: element.center.y)))
        ]
    case .pen, .mosaic:
        return []
    default:
        let bounds = element.bounds
        return [
            (.startPoint, projection.viewPoint(fromImagePoint: CGPoint(x: bounds.minX, y: bounds.minY))),
            (.endPoint, projection.viewPoint(fromImagePoint: CGPoint(x: bounds.maxX, y: bounds.maxY))),
            (.startXEndY, projection.viewPoint(fromImagePoint: CGPoint(x: bounds.minX, y: bounds.maxY))),
            (.endXStartY, projection.viewPoint(fromImagePoint: CGPoint(x: bounds.maxX, y: bounds.minY))),
        ]
    }
}
