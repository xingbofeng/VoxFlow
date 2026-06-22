import AppKit

// GPLv3-scoped behavior attribution:
// F full-screen selection, Tab window-targeting toggle, and marquee selection
// behavior are adapted from sw33tLie/macshot.
// Source: https://github.com/sw33tLie/macshot
// Upstream commit: 34c9999625cfe9e8999c00358b3c172dfc00380c
// License: GPLv3

public struct SelectionOverlayWindowConfiguration: Equatable, Sendable {
    public let display: ScreenshotDisplay
    public let snapshotImage: CGImage?
    public let snapshotScale: CGFloat
    public let isBorderless: Bool
    public let isFloating: Bool

    public init(
        display: ScreenshotDisplay,
        snapshotImage: CGImage? = nil,
        snapshotScale: CGFloat? = nil,
        isBorderless: Bool = true,
        isFloating: Bool = true
    ) {
        self.display = display
        self.snapshotImage = snapshotImage
        self.snapshotScale = max(snapshotScale ?? display.scale, 1)
        self.isBorderless = isBorderless
        self.isFloating = isFloating
    }
}

public struct ScrollingScreenshotCaptureResult: Equatable, @unchecked Sendable {
    public let image: CGImage

    public init(image: CGImage) {
        self.image = image
    }

    public static func == (
        lhs: ScrollingScreenshotCaptureResult,
        rhs: ScrollingScreenshotCaptureResult
    ) -> Bool {
        lhs.image.width == rhs.image.width &&
            lhs.image.height == rhs.image.height
    }
}

public struct ScrollingScreenshotRequest: Equatable, Sendable {
    public let selection: SelectionState
    public let display: ScreenshotDisplay

    public init(selection: SelectionState, display: ScreenshotDisplay) {
        self.selection = selection
        self.display = display
    }
}

public typealias ScrollingScreenshotCapturing = @MainActor (ScrollingScreenshotRequest) async -> ScrollingScreenshotCaptureResult?

enum SelectionOverlaySnapshotSampler {
    static func pixelPoint(
        forOverlayPoint point: CGPoint,
        snapshotScale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: floor(point.x * snapshotScale),
            y: floor(point.y * snapshotScale)
        )
    }
}

public enum SelectionOverlayResult: Equatable, Sendable {
    case cancelled
    case accepted(SelectionState)
    case acceptedAnnotated(SelectionState, AnnotationDocument)
    case acceptedScrolling(ScrollingScreenshotCaptureResult)
    case acceptedTextRecognition(SelectionState)
    case acceptedAnnotatedTextRecognition(SelectionState, AnnotationDocument)
    case acceptedTranslation(SelectionState)
}

public enum SelectionOverlayCompletionKind: Equatable, Sendable {
    case complete
    case textRecognition
    case translate
}

public struct AnnotationBrushPreview: Equatable, Sendable {
    public let center: CGPoint
    public let size: CGFloat

    public init(center: CGPoint, size: CGFloat) {
        self.center = center
        self.size = size
    }
}

public struct SelectionAnnotationOverlayState: Equatable, Sendable {
    public let document: AnnotationDocument
    public let translatedOverlay: TranslatedOverlayAnnotationElement?
    public let preview: AnnotationElement?
    public let brushPreview: AnnotationBrushPreview?
    public let activeRole: SelectionToolbarRole?
    public let currentStyle: ScreenshotAnnotationStyle
    public let currentFontSize: CGFloat
    public let inlineTranslationStatus: SelectionInlineTranslationStatus
    /// 当前正在展示 popover 的按钮（.color / .lineWidth / .fontSize），nil 表示无 popover。
    public let popoverRole: SelectionToolbarRole?

    public init(
        document: AnnotationDocument = AnnotationDocument(),
        translatedOverlay: TranslatedOverlayAnnotationElement? = nil,
        preview: AnnotationElement? = nil,
        brushPreview: AnnotationBrushPreview? = nil,
        activeRole: SelectionToolbarRole? = nil,
        currentStyle: ScreenshotAnnotationStyle = .default,
        currentFontSize: CGFloat = 14,
        inlineTranslationStatus: SelectionInlineTranslationStatus = .idle,
        popoverRole: SelectionToolbarRole? = nil
    ) {
        self.document = document
        self.translatedOverlay = translatedOverlay
        self.preview = preview
        self.brushPreview = brushPreview
        self.activeRole = activeRole
        self.currentStyle = currentStyle
        self.currentFontSize = currentFontSize
        self.inlineTranslationStatus = inlineTranslationStatus
        self.popoverRole = popoverRole
    }
}

public enum SelectionInlineTranslationStatus: Equatable, Sendable {
    case idle
    case loading
    case failed(String)
}

enum SelectionOverlayDisplayGeometry {
    static func localSelectionRect(
        for state: SelectionState,
        on display: ScreenshotDisplay
    ) -> CGRect {
        state.normalizedRect.offsetBy(
            dx: -display.frame.minX,
            dy: -display.frame.minY
        )
    }

    static func shouldDrawSelectionChrome(
        localSelectionRect: CGRect,
        visibleBounds: CGRect
    ) -> Bool {
        localSelectionRect.intersects(visibleBounds)
    }
}

public enum SelectionOverlayKey: Equatable, Sendable {
    case escape
    case `return`
    case tab
    case fullScreen
}

public enum SelectionOverlayWindowEvent: Sendable {
    case cancelRequested
    case completeRequested
    case windowTargetingToggleRequested
    case fullScreenRequested
    case doubleClick(CGPoint)
    case toolbarRole(SelectionToolbarRole)
    case windowTargetSelected(CGRect)
    case annotationBegan(CGPoint)
    case annotationChanged(CGPoint)
    case annotationEnded(CGPoint)
    case annotationHoverChanged(CGPoint?)
    case annotationSelectionRequested(CGPoint)
    case annotationToggleSelectionRequested(CGPoint)
    case annotationMoveBegan(CGPoint)
    case annotationMoveChanged(CGPoint)
    case annotationMoveEnded(CGPoint)
    case annotationResizeBegan(AnnotationResizeHandle, CGPoint)
    case annotationResizeChanged(CGPoint)
    case annotationResizeEnded(CGPoint)
    case deleteSelectedAnnotationRequested
    case annotationTextCommitted(CGPoint, String)
    case selectionBegan(CGPoint)
    case selectionChanged(CGPoint)
    case selectionEnded(CGPoint)
    /// 用户点击了 popover 中的某个选项（颜色/线宽/字号）。index 是选项在对应候选数组中的位置。
    case popoverOptionSelected(SelectionToolbarRole, Int)
    /// 用户点击了 popover 之外的区域，应关闭 popover。
    case popoverDismissed
}

@MainActor
final class SelectionOverlayPointerEventRouter {
    private let eventHandler: @MainActor (SelectionOverlayWindowEvent) -> Void

    init(eventHandler: @escaping @MainActor (SelectionOverlayWindowEvent) -> Void) {
        self.eventHandler = eventHandler
    }

    func mouseDown(atGlobalPoint point: CGPoint) {
        eventHandler(.selectionBegan(point))
    }

    func mouseDragged(atGlobalPoint point: CGPoint) {
        eventHandler(.selectionChanged(point))
    }

    func mouseUp(atGlobalPoint point: CGPoint) {
        eventHandler(.selectionEnded(point))
    }
}

enum SelectionOverlayCursorKind: Equatable {
    case crosshair
    case openHand
    case closedHand
    case horizontalResize
    case verticalResize
    case diagonalNorthwestSoutheast
    case diagonalNortheastSouthwest

    var isResize: Bool {
        switch self {
        case .horizontalResize, .verticalResize,
             .diagonalNorthwestSoutheast, .diagonalNortheastSouthwest:
            return true
        case .crosshair, .openHand, .closedHand:
            return false
        }
    }

    @MainActor
    var nsCursor: NSCursor {
        switch self {
        case .crosshair:
            return .crosshair
        case .openHand:
            return .openHand
        case .closedHand:
            return .closedHand
        case .horizontalResize:
            return .resizeLeftRight
        case .verticalResize:
            return .resizeUpDown
        case .diagonalNorthwestSoutheast:
            return SelectionOverlayDiagonalCursors.northwestSoutheast
        case .diagonalNortheastSouthwest:
            return SelectionOverlayDiagonalCursors.northeastSouthwest
        }
    }
}

@MainActor
private enum SelectionOverlayDiagonalCursors {
    static let northwestSoutheast = makeCursor(
        systemSymbolName: "arrow.up.left.and.arrow.down.right"
    )
    static let northeastSouthwest = makeCursor(
        systemSymbolName: "arrow.up.right.and.arrow.down.left"
    )

    private static func makeCursor(systemSymbolName: String) -> NSCursor {
        let image = NSImage(
            systemSymbolName: systemSymbolName,
            accessibilityDescription: nil
        ) ?? NSCursor.crosshair.image
        return NSCursor(
            image: image,
            hotSpot: CGPoint(x: image.size.width / 2, y: image.size.height / 2)
        )
    }
}

enum SelectionOverlayCursorResolver {
    static func cursorKind(
        at point: CGPoint,
        selectionState: SelectionState?,
        isMovingSelection: Bool,
        handleSize: CGFloat = 16
    ) -> SelectionOverlayCursorKind {
        if isMovingSelection {
            return .closedHand
        }
        guard let selectionState, selectionState.isValidSelection else {
            return .crosshair
        }
        let presentation = SelectionOverlayPresentation(
            state: selectionState,
            handleSize: handleSize
        )
        for (handle, rect) in zip(SelectionResizeHandle.allCases, presentation.resizeHandleRects) {
            guard rect.contains(point) else { continue }
            switch handle {
            case .left, .right:
                return .horizontalResize
            case .top, .bottom:
                return .verticalResize
            case .topLeft, .bottomRight:
                return .diagonalNorthwestSoutheast
            case .topRight, .bottomLeft:
                return .diagonalNortheastSouthwest
            }
        }
        return selectionState.normalizedRect.contains(point) ? .openHand : .crosshair
    }
}

@MainActor
public protocol SelectionOverlayWindowControlling: AnyObject {
    var savePanelHostWindow: NSWindow { get }
    func orderFront()
    func setVisibleForModalPresentation(_ isVisible: Bool)
    func updateSelection(_ state: SelectionState?)
    func updateAnnotationState(_ state: SelectionAnnotationOverlayState)
    func commitInlineTextEditing()
    func setWindowTargetingEnabled(_ isEnabled: Bool)
    func setAllowsTargetedSelectionReplacement(_ isEnabled: Bool)
    func setScrollCaptureActive(_ isActive: Bool, selection: SelectionState?)
    func close()
}

@MainActor
public protocol SelectionOverlayWindowMaking: AnyObject {
    func makeWindow(
        configuration: SelectionOverlayWindowConfiguration,
        eventHandler: @escaping @MainActor (SelectionOverlayWindowEvent) -> Void
    ) -> any SelectionOverlayWindowControlling
}

@MainActor
public final class SelectionOverlayController {
    private let windowFactory: any SelectionOverlayWindowMaking
    private let imageSaver: any ScreenshotSavePanelPresenting
    private let annotationRenderer: any AnnotationRendering
    private let inlineTranslator: (any InlineSelectionTranslating)?
    private let scrollingScreenshotCapture: ScrollingScreenshotCapturing
    private let toolbarPresentation: SelectionToolbarPresentation
    private let onResult: @MainActor (SelectionOverlayResult) -> Void
    private var windowRecords: [WindowRecord] = []
    private var activeSelection: ActiveSelection?
    private var currentSelectionState: SelectionState?
    private var annotationDocument = AnnotationDocument()
    private var activeAnnotationRole: SelectionToolbarRole?
    private var activeAnnotationTool: (any ScreenshotAnnotationTool)?
    private var activeBrushPreview: AnnotationBrushPreview?
    private var copiedAnnotationElements: [AnnotationElement] = []
    private var currentAnnotationStyle = ScreenshotAnnotationStyle.default
    private var currentAnnotationFontSize: CGFloat = 14
    private var currentTranslatedOverlay: TranslatedOverlayAnnotationElement?
    private var cachedTranslatedOverlay: TranslatedOverlayAnnotationElement?
    /// 当前正在展示 popover 的按钮（.color / .lineWidth / .fontSize），nil 表示无 popover。
    private var popoverRole: SelectionToolbarRole?
    private var activeAnnotationMovePoint: CGPoint?
    private var hasRecordedAnnotationMoveUndo = false
    private var activeAnnotationResizeHandle: AnnotationResizeHandle?
    private var hasRecordedAnnotationResizeUndo = false
    private var isWindowTargetingEnabled = true
    private var isIgnoringSelectionInteriorClick = false
    private var screenParametersObserver: Any?
    private var escapeEventTap: SelectionOverlayEscapeEventTap?
    private var activeSelectionMovePoint: CGPoint?
    private var selectionBounds: CGRect = .zero
    private var selectionScale: CGFloat = 1
    private var activeSelectionResizeHandle: SelectionResizeHandle?
    private var pendingTargetedSelectionStartPoint: CGPoint?
    private var currentSelectionOrigin: SelectionOrigin = .manual
    private var pointerDragSession: PointerDragSession?
    private var inlineTranslationTask: Task<Void, Never>?
    private var scrollingCaptureTask: Task<Void, Never>?
    private var inlineTranslationStatus: SelectionInlineTranslationStatus = .idle

    public init(
        windowFactory: any SelectionOverlayWindowMaking = AppKitSelectionOverlayWindowFactory(),
        imageSaver: any ScreenshotSavePanelPresenting = ScreenshotSavePanelPresenter(),
        annotationRenderer: any AnnotationRendering = AnnotationRenderer(),
        inlineTranslator: (any InlineSelectionTranslating)? = nil,
        toolbarPresentation: SelectionToolbarPresentation = .default,
        onResult: @escaping @MainActor (SelectionOverlayResult) -> Void = { _ in },
        scrollingScreenshotCapture: @escaping ScrollingScreenshotCapturing = DefaultScrollingScreenshotCapturer.capture
    ) {
        self.windowFactory = windowFactory
        self.imageSaver = imageSaver
        self.annotationRenderer = annotationRenderer
        self.inlineTranslator = inlineTranslator
        self.scrollingScreenshotCapture = scrollingScreenshotCapture
        self.toolbarPresentation = toolbarPresentation
        self.onResult = onResult
    }

    public func present(displays: [ScreenshotDisplay]) {
        present(frames: displays.map { ScreenshotDisplayFrame(display: $0, image: nil) })
    }

    public func present(frames: [ScreenshotDisplayFrame]) {
        close()
        isWindowTargetingEnabled = true
        resetAnnotations()
        let escapeEventTap = SelectionOverlayEscapeEventTap { [weak self] in
            self?.cancelSelection()
        }
        self.escapeEventTap = escapeEventTap
        escapeEventTap.start()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelSelection()
            }
        }
        selectionBounds = Self.unionFrame(for: frames.map(\.display.frame))
        selectionScale = max(frames.map(\.display.scale).max() ?? 1, 1)
        windowRecords = frames.map { frame in
            WindowRecord(
                display: frame.display,
                image: frame.image,
                window: windowFactory.makeWindow(
                    configuration: SelectionOverlayWindowConfiguration(
                        display: frame.display,
                        snapshotImage: frame.image
                    ),
                    eventHandler: { [weak self] event in
                        self?.handleWindowEvent(event, on: frame.display)
                    }
                )
            )
        }
        windowRecords.forEach { $0.window.orderFront() }
    }

    private static func unionFrame(for frames: [CGRect]) -> CGRect {
        guard var unionFrame = frames.first else {
            return .zero
        }
        for frame in frames.dropFirst() {
            unionFrame = unionFrame.union(frame)
        }
        return unionFrame
    }

    public func beginSelection(on displayID: CGDirectDisplayID, at point: CGPoint) {
        guard let record = windowRecords.first(where: { $0.display.id == displayID }) else {
            return
        }
        let selection = ActiveSelection(display: record.display, startPoint: point)
        activeSelection = selection
        currentSelectionOrigin = .manual
        let state = SelectionState(
            displayFrame: selectionBounds,
            displayScale: selectionScale,
            startPoint: point,
            currentPoint: point
        )
        currentSelectionState = state
        resetAnnotations()
        windowRecords.forEach {
            $0.window.setAllowsTargetedSelectionReplacement(false)
            $0.window.updateSelection(state)
        }
        pushAnnotationState()
    }

    public func updateSelection(to point: CGPoint) {
        guard let activeSelection else {
            return
        }
        let state = SelectionState(
            displayFrame: selectionBounds,
            displayScale: selectionScale,
            startPoint: activeSelection.startPoint,
            currentPoint: point
        )
        currentSelectionState = state
        currentSelectionOrigin = .manual
        windowRecords.forEach {
            $0.window.setAllowsTargetedSelectionReplacement(false)
            $0.window.updateSelection(state)
        }
    }

    public func handleKey(_ key: SelectionOverlayKey) {
        switch key {
        case .escape:
            cancelSelection()
        case .return:
            completeSelection(kind: .complete)
        case .tab:
            toggleWindowTargeting()
        case .fullScreen:
            guard let record = primaryWindowRecord() else { return }
            acceptFullDisplay(on: record.display)
        }
    }

    public func handleToolbarRole(
        _ role: SelectionToolbarRole,
        savePanelHostWindow: NSWindow? = nil
    ) {
        switch role {
        case .cancel:
            cancelSelection()
        case .complete:
            completeSelection(kind: .complete)
        case .textRecognition:
            completeSelection(kind: .textRecognition)
        case .translate:
            translateSelectionInlineOrComplete()
        case .scrollCapture:
            beginScrollingCapture()
        case .select:
            activeAnnotationRole = .select
            activeAnnotationTool = nil
            activeBrushPreview = nil
            pushAnnotationState()
        case .pen, .circle, .rectangle, .arrow, .dotMarker, .numberedMarker, .text, .mosaic:
            activeAnnotationRole = role
            activeAnnotationTool = makeAnnotationTool(for: role)
            activeBrushPreview = nil
            pushAnnotationState()
        case .undo:
            annotationDocument.undo()
            pushAnnotationState()
        case .redo:
            annotationDocument.redo()
            pushAnnotationState()
        case .color:
            popoverRole = (popoverRole == .color) ? nil : .color
            pushAnnotationState()
        case .lineWidth:
            popoverRole = (popoverRole == .lineWidth) ? nil : .lineWidth
            pushAnnotationState()
        case .fontSize:
            popoverRole = (popoverRole == .fontSize) ? nil : .fontSize
            pushAnnotationState()
        case .download:
            let hostWindow = savePanelHostWindow ?? primaryWindowRecord()?.window.savePanelHostWindow
            saveCurrentSelection(hostWindow: hostWindow)
        case .copy:
            copySelectedAnnotations()
        case .paste:
            pasteCopiedAnnotations()
            pushAnnotationState()
        case .duplicate:
            duplicateSelectedAnnotations()
            pushAnnotationState()
        }
    }

    public func handleDoubleClick(on displayID: CGDirectDisplayID, at point: CGPoint) {
        guard currentSelectionState?.normalizedRect.contains(point) == true else {
            return
        }
        completeSelection(kind: .complete)
    }

    public func close() {
        inlineTranslationTask?.cancel()
        inlineTranslationTask = nil
        scrollingCaptureTask?.cancel()
        scrollingCaptureTask = nil
        windowRecords.forEach { $0.window.setScrollCaptureActive(false, selection: nil) }
        escapeEventTap?.stop()
        escapeEventTap = nil
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        windowRecords.forEach { $0.window.close() }
        windowRecords.removeAll()
        activeSelection = nil
        currentSelectionState = nil
        isIgnoringSelectionInteriorClick = false
        activeSelectionMovePoint = nil
        activeSelectionResizeHandle = nil
        pendingTargetedSelectionStartPoint = nil
        currentSelectionOrigin = .manual
        pointerDragSession = nil
        popoverRole = nil
        inlineTranslationStatus = .idle
    }

    private func handleWindowEvent(_ event: SelectionOverlayWindowEvent, on display: ScreenshotDisplay) {
        switch event {
        case .cancelRequested:
            cancelSelection()
        case .completeRequested:
            completeSelection(kind: .complete)
        case .windowTargetingToggleRequested:
            toggleWindowTargeting()
        case .fullScreenRequested:
            acceptFullDisplay(on: display)
        case .doubleClick(let localPoint):
            let globalPoint = CGPoint(
                x: localPoint.x + display.frame.minX,
                y: localPoint.y + display.frame.minY
            )
            handleDoubleClick(on: display.id, at: globalPoint)
        case .toolbarRole(let role):
            let hostWindow = windowRecords
                .first(where: { $0.display.id == display.id })?
                .window.savePanelHostWindow
            handleToolbarRole(role, savePanelHostWindow: hostWindow)
        case .windowTargetSelected(let rect):
            acceptWindowTarget(rect, on: display)
        case .annotationBegan(let localPoint):
            beginAnnotation(at: localPoint, on: display)
        case .annotationChanged(let localPoint):
            updateAnnotation(to: localPoint, on: display)
        case .annotationEnded(let localPoint):
            endAnnotation(at: localPoint, on: display)
        case .annotationHoverChanged(let localPoint):
            updateAnnotationHover(to: localPoint, on: display)
        case .annotationSelectionRequested(let localPoint):
            selectAnnotation(at: localPoint, on: display)
        case .annotationToggleSelectionRequested(let localPoint):
            toggleAnnotationSelection(at: localPoint, on: display)
        case .annotationMoveBegan(let localPoint):
            beginAnnotationMove(at: localPoint, on: display)
        case .annotationMoveChanged(let localPoint):
            updateAnnotationMove(to: localPoint, on: display)
        case .annotationMoveEnded:
            endAnnotationMove()
        case .annotationResizeBegan(let handle, let localPoint):
            beginAnnotationResize(handle: handle, at: localPoint, on: display)
        case .annotationResizeChanged(let localPoint):
            updateAnnotationResize(to: localPoint, on: display)
        case .annotationResizeEnded:
            endAnnotationResize()
        case .deleteSelectedAnnotationRequested:
            deleteSelectedAnnotation()
        case .annotationTextCommitted(let localPoint, let text):
            commitTextAnnotation(text, at: localPoint, on: display)
        case .selectionBegan(let point):
            pointerDragSession = PointerDragSession(startedOnDisplayID: display.id)
            if let handle = selectionResizeHandle(at: point, on: display) {
                beginSelectionResize(handle: handle)
                return
            }
            guard shouldBeginSelection(at: point) else {
                if currentSelectionOrigin == .targeted {
                    pendingTargetedSelectionStartPoint = point
                    activeSelectionMovePoint = nil
                    isIgnoringSelectionInteriorClick = false
                    return
                }
                beginSelectionMove(at: point)
                return
            }
            isIgnoringSelectionInteriorClick = false
            activeSelectionMovePoint = nil
            activeSelectionResizeHandle = nil
            pendingTargetedSelectionStartPoint = nil
            beginSelection(on: display.id, at: point)
        case .selectionChanged(let point):
            guard pointerDragSession != nil else { return }
            if let handle = activeSelectionResizeHandle {
                updateSelectionResize(handle: handle, to: point, on: display)
                return
            }
            if let startPoint = pendingTargetedSelectionStartPoint {
                pendingTargetedSelectionStartPoint = nil
                let displayID = pointerDragSession?.startedOnDisplayID ?? display.id
                beginSelection(on: displayID, at: startPoint)
                updateSelection(to: point)
                return
            }
            if activeSelectionMovePoint != nil {
                updateSelectionMove(to: point, on: display)
                return
            }
            guard !isIgnoringSelectionInteriorClick else { return }
            updateSelection(to: point)
        case .selectionEnded(let point):
            guard pointerDragSession != nil else { return }
            defer { pointerDragSession = nil }
            if let handle = activeSelectionResizeHandle {
                updateSelectionResize(handle: handle, to: point, on: display)
                endSelectionResize()
                return
            }
            if pendingTargetedSelectionStartPoint != nil {
                pendingTargetedSelectionStartPoint = nil
                return
            }
            if activeSelectionMovePoint != nil {
                updateSelectionMove(to: point, on: display)
                endSelectionMove()
                return
            }
            guard !isIgnoringSelectionInteriorClick else {
                isIgnoringSelectionInteriorClick = false
                return
            }
            updateSelection(to: point)
            if let state = currentSelectionState, !state.isValidSelection {
                currentSelectionState = nil
                activeSelection = nil
                windowRecords.forEach { $0.window.updateSelection(nil) }
            }
        case .popoverOptionSelected(let role, let index):
            switch role {
            case .color:
                let colors: [ScreenshotAnnotationColor] = [.voxGreen, .red, .white, .black]
                if index >= 0 && index < colors.count {
                    currentAnnotationStyle.color = colors[index]
                    updateActiveToolStyle()
                }
            case .lineWidth:
                let widths: [CGFloat] = [6, 8, 10]
                if index >= 0 && index < widths.count {
                    currentAnnotationStyle.lineWidth = widths[index]
                    updateActiveToolStyle()
                }
            case .fontSize:
                let sizes: [CGFloat] = [14, 24, 32]
                if index >= 0 && index < sizes.count {
                    currentAnnotationFontSize = sizes[index]
                    updateActiveToolStyle()
                }
            default:
                break
            }
            popoverRole = nil
            pushAnnotationState()
        case .popoverDismissed:
            if popoverRole != nil {
                popoverRole = nil
                pushAnnotationState()
            }
        }
    }

    private func globalPoint(_ localPoint: CGPoint, on display: ScreenshotDisplay) -> CGPoint {
        CGPoint(
            x: localPoint.x + display.frame.minX,
            y: localPoint.y + display.frame.minY
        )
    }

    private func shouldBeginSelection(at point: CGPoint) -> Bool {
        guard let state = currentSelectionState,
              state.isValidSelection,
              state.normalizedRect.contains(point) else {
            return true
        }
        return false
    }

    private func selectionResizeHandle(at point: CGPoint, on display: ScreenshotDisplay) -> SelectionResizeHandle? {
        guard let state = currentSelectionState,
              state.isValidSelection,
              state.normalizedRect.intersects(display.frame) else {
            return nil
        }
        let presentation = SelectionOverlayPresentation(state: state, handleSize: 16)
        for (handle, rect) in zip(SelectionResizeHandle.allCases, presentation.resizeHandleRects) {
            if rect.contains(point) {
                return handle
            }
        }
        return nil
    }

    private func beginSelectionMove(at point: CGPoint) {
        activeSelectionMovePoint = point
        isIgnoringSelectionInteriorClick = false
    }

    private func updateSelectionMove(to point: CGPoint, on display: ScreenshotDisplay) {
        guard let previousPoint = activeSelectionMovePoint,
              let state = currentSelectionState else {
            return
        }
        let proposedOffset = CGSize(
            width: point.x - previousPoint.x,
            height: point.y - previousPoint.y
        )
        let offset = constrainedSelectionOffset(
            proposedOffset,
            for: state.normalizedRect,
            in: selectionBounds
        )
        guard offset != .zero else {
            activeSelectionMovePoint = point
            return
        }
        let movedState = state.movingSelection(by: offset)
        currentSelectionState = movedState
        activeSelectionMovePoint = point
        windowRecords.forEach { $0.window.updateSelection(movedState) }
    }

    private func constrainedSelectionOffset(
        _ offset: CGSize,
        for rect: CGRect,
        in bounds: CGRect
    ) -> CGSize {
        CGSize(
            width: max(bounds.minX - rect.minX, min(offset.width, bounds.maxX - rect.maxX)),
            height: max(bounds.minY - rect.minY, min(offset.height, bounds.maxY - rect.maxY))
        )
    }

    private func endSelectionMove() {
        activeSelectionMovePoint = nil
    }

    private func beginSelectionResize(handle: SelectionResizeHandle) {
        activeSelectionResizeHandle = handle
        activeSelectionMovePoint = nil
        pendingTargetedSelectionStartPoint = nil
        isIgnoringSelectionInteriorClick = false
    }

    private func updateSelectionResize(
        handle: SelectionResizeHandle,
        to point: CGPoint,
        on display: ScreenshotDisplay
    ) {
        guard let state = currentSelectionState else {
            return
        }
        let constrainedPoint = CGPoint(
            x: min(max(point.x, selectionBounds.minX), selectionBounds.maxX),
            y: min(max(point.y, selectionBounds.minY), selectionBounds.maxY)
        )
        let resizedState = state.resizingSelection(handle: handle, to: constrainedPoint)
        currentSelectionState = resizedState
        currentSelectionOrigin = .manual
        activeSelection = ActiveSelection(display: display, startPoint: resizedState.startPoint)
        windowRecords.forEach { record in
            record.window.setAllowsTargetedSelectionReplacement(false)
            record.window.updateSelection(resizedState)
        }
    }

    private func endSelectionResize() {
        activeSelectionResizeHandle = nil
    }

    private func cancelSelection() {
        close()
        onResult(.cancelled)
    }

    private func completeSelection(kind: SelectionOverlayCompletionKind) {
        windowRecords.forEach { $0.window.commitInlineTextEditing() }
        guard let state = currentSelectionState,
              state.isValidSelection else {
            return
        }
        close()
        let completionDocument = documentForCompletion()
        switch (kind, completionDocument.elements.isEmpty) {
        case (.complete, true):
            onResult(.accepted(state))
        case (.complete, false):
            onResult(.acceptedAnnotated(state, completionDocument))
        case (.textRecognition, true):
            onResult(.acceptedTextRecognition(state))
        case (.textRecognition, false):
            onResult(.acceptedAnnotatedTextRecognition(state, completionDocument))
        case (.translate, _):
            // 翻译按钮立即完成选区，annotation 文档不参与翻译流程
            onResult(.acceptedTranslation(state))
        }
    }

    private func documentForCompletion() -> AnnotationDocument {
        guard let currentTranslatedOverlay else {
            return annotationDocument
        }
        let elements = [.translatedOverlay(currentTranslatedOverlay)]
            + annotationDocument.elements.filter { $0.kind != .translatedOverlay }
        return AnnotationDocument(elements: elements)
    }

    private func translateSelectionInlineOrComplete() {
        windowRecords.forEach { $0.window.commitInlineTextEditing() }
        guard let state = currentSelectionState,
              state.isValidSelection else {
            return
        }
        if currentTranslatedOverlay != nil, inlineTranslationStatus == .idle {
            currentTranslatedOverlay = nil
            activeAnnotationRole = nil
            activeAnnotationTool = nil
            activeBrushPreview = nil
            popoverRole = nil
            pushAnnotationState()
            return
        }
        if let cachedTranslatedOverlay, inlineTranslationStatus == .idle {
            currentTranslatedOverlay = cachedTranslatedOverlay
            activeAnnotationRole = .translate
            activeAnnotationTool = nil
            activeBrushPreview = nil
            popoverRole = nil
            pushAnnotationState()
            return
        }
        if inlineTranslationStatus == .loading {
            inlineTranslationTask?.cancel()
            inlineTranslationTask = nil
            currentTranslatedOverlay = nil
            activeAnnotationRole = nil
            activeAnnotationTool = nil
            activeBrushPreview = nil
            inlineTranslationStatus = .idle
            popoverRole = nil
            pushAnnotationState()
            return
        }
        guard let inlineTranslator else {
            activeAnnotationRole = nil
            activeAnnotationTool = nil
            activeBrushPreview = nil
            popoverRole = nil
            inlineTranslationStatus = .failed("翻译服务未就绪")
            pushAnnotationState()
            return
        }
        guard let image = croppedImage(for: state) else {
            return
        }
        inlineTranslationTask?.cancel()
        activeAnnotationRole = .translate
        activeAnnotationTool = nil
        activeBrushPreview = nil
        inlineTranslationStatus = .loading
        popoverRole = nil
        pushAnnotationState()
        inlineTranslationTask = Task { @MainActor [weak self, inlineTranslator] in
            do {
                let overlay = try await inlineTranslator.translatedOverlay(for: image)
                guard !Task.isCancelled,
                      let self,
                      self.currentSelectionState == state else {
                    return
                }
                self.activeAnnotationRole = nil
                self.activeAnnotationTool = nil
                self.activeBrushPreview = nil
                self.popoverRole = nil
                self.inlineTranslationStatus = .idle
                self.currentTranslatedOverlay = overlay
                self.cachedTranslatedOverlay = overlay
                self.activeAnnotationRole = .translate
                self.inlineTranslationTask = nil
                self.pushAnnotationState()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.activeAnnotationRole = nil
                self.inlineTranslationStatus = .failed(error.localizedDescription)
                self.inlineTranslationTask = nil
                self.pushAnnotationState()
            }
        }
    }

    private func beginScrollingCapture() {
        windowRecords.forEach { $0.window.commitInlineTextEditing() }
        guard scrollingCaptureTask == nil,
              let state = currentSelectionState,
              state.isValidSelection,
              let display = displayForScrollingCapture(state) else {
            return
        }

        inlineTranslationTask?.cancel()
        inlineTranslationTask = nil
        activeAnnotationRole = nil
        activeAnnotationTool = nil
        activeBrushPreview = nil
        inlineTranslationStatus = .idle
        popoverRole = nil
        pushAnnotationState()
        windowRecords.forEach { $0.window.setScrollCaptureActive(true, selection: state) }

        let request = ScrollingScreenshotRequest(selection: state, display: display)
        scrollingCaptureTask = Task { @MainActor [weak self, scrollingScreenshotCapture] in
            let result = await scrollingScreenshotCapture(request)
            guard !Task.isCancelled,
                  let self else {
                return
            }
            self.scrollingCaptureTask = nil
            guard let result else {
                self.cancelSelection()
                return
            }
            self.close()
            self.onResult(.acceptedScrolling(result))
        }
    }

    private func displayForScrollingCapture(_ state: SelectionState) -> ScreenshotDisplay? {
        let selectionRect = state.normalizedRect
        return windowRecords
            .map(\.display)
            .filter { $0.frame.intersects(selectionRect) }
            .max { lhs, rhs in
                lhs.frame.intersection(selectionRect).area < rhs.frame.intersection(selectionRect).area
            }
    }

    private func acceptFullDisplay(on display: ScreenshotDisplay) {
        let state = SelectionState(
            displayFrame: display.frame,
            displayScale: display.scale,
            startPoint: CGPoint(x: display.frame.minX, y: display.frame.minY),
            currentPoint: CGPoint(x: display.frame.maxX, y: display.frame.maxY)
        )
        activeSelection = ActiveSelection(display: display, startPoint: state.startPoint)
        currentSelectionState = state
        currentSelectionOrigin = .targeted
        activeSelectionMovePoint = nil
        activeSelectionResizeHandle = nil
        pendingTargetedSelectionStartPoint = nil
        resetAnnotations()
        windowRecords.forEach { $0.window.setAllowsTargetedSelectionReplacement(false) }
        if let record = windowRecords.first(where: { $0.display.id == display.id }) {
            record.window.setAllowsTargetedSelectionReplacement(true)
            record.window.updateSelection(state)
        }
        pushAnnotationState()
    }

    private func toggleWindowTargeting() {
        isWindowTargetingEnabled.toggle()
        windowRecords.forEach { $0.window.setWindowTargetingEnabled(isWindowTargetingEnabled) }
    }

    private func primaryWindowRecord() -> WindowRecord? {
        windowRecords.first(where: { $0.display.isPrimary }) ?? windowRecords.first
    }

    private func acceptWindowTarget(_ rect: CGRect, on display: ScreenshotDisplay) {
        let state = SelectionState(
            displayFrame: display.frame,
            displayScale: display.scale,
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            currentPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        guard state.isValidSelection else {
            return
        }
        activeSelection = ActiveSelection(display: display, startPoint: state.startPoint)
        currentSelectionState = state
        currentSelectionOrigin = .targeted
        activeSelectionMovePoint = nil
        activeSelectionResizeHandle = nil
        pendingTargetedSelectionStartPoint = nil
        resetAnnotations()
        windowRecords.forEach { $0.window.setAllowsTargetedSelectionReplacement(false) }
        if let record = windowRecords.first(where: { $0.display.id == display.id }) {
            record.window.setAllowsTargetedSelectionReplacement(true)
            record.window.updateSelection(state)
        }
        pushAnnotationState()
    }

    private func saveCurrentSelection(hostWindow: NSWindow?) {
        windowRecords.forEach { $0.window.commitInlineTextEditing() }
        guard let state = currentSelectionState,
              let image = croppedImage(for: state),
              let hostWindow else {
            return
        }

        do {
            let renderedImage = try annotationRenderer.render(image: image, document: annotationDocument)
            windowRecords
                .filter { $0.window.savePanelHostWindow !== hostWindow }
                .forEach { $0.window.setVisibleForModalPresentation(false) }
            imageSaver.savePNG(image: renderedImage, attachedTo: hostWindow) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(true):
                    close()
                    onResult(.cancelled)
                case .success(false):
                    windowRecords.forEach { $0.window.setVisibleForModalPresentation(true) }
                case .failure:
                    windowRecords.forEach { $0.window.setVisibleForModalPresentation(true) }
                    NSSound.beep()
                }
            }
        } catch {
            windowRecords.forEach { $0.window.setVisibleForModalPresentation(true) }
            NSSound.beep()
        }
    }

    private func croppedImage(for state: SelectionState) -> CGImage? {
        let frames = windowRecords.map {
            ScreenshotDisplayFrame(display: $0.display, image: $0.image)
        }
        return ScreenshotSelectionImageComposer.cropSelection(state, from: frames)
    }

    private func resetAnnotations() {
        annotationDocument = AnnotationDocument()
        currentTranslatedOverlay = nil
        cachedTranslatedOverlay = nil
        activeAnnotationRole = nil
        activeAnnotationTool = nil
        activeBrushPreview = nil
        popoverRole = nil
    }

    private func pushAnnotationState() {
        let state = SelectionAnnotationOverlayState(
            document: annotationDocument,
            translatedOverlay: currentTranslatedOverlay,
            preview: activeAnnotationTool?.currentAnnotation,
            brushPreview: activeBrushPreview,
            activeRole: activeAnnotationRole,
            currentStyle: currentAnnotationStyle,
            currentFontSize: currentAnnotationFontSize,
            inlineTranslationStatus: inlineTranslationStatus,
            popoverRole: popoverRole
        )
        windowRecords.forEach { $0.window.updateAnnotationState(state) }
    }

    private func makeAnnotationTool(for role: SelectionToolbarRole) -> (any ScreenshotAnnotationTool)? {
        switch role {
        case .pen:
            FreehandAnnotationTool(style: currentAnnotationStyle)
        case .circle:
            EllipseAnnotationTool(style: currentAnnotationStyle)
        case .rectangle:
            RectangleAnnotationTool(style: currentAnnotationStyle)
        case .arrow:
            ArrowAnnotationTool(style: currentAnnotationStyle)
        case .dotMarker:
            DotMarkerAnnotationTool(style: currentAnnotationStyle)
        case .numberedMarker:
            NumberedMarkerAnnotationTool(
                nextNumber: annotationDocument.elements.filter { $0.kind == .numberedMarker }.count + 1,
                style: currentAnnotationStyle
            )
        case .text:
            TextAnnotationTool(textStyle: ScreenshotAnnotationTextStyle(
                color: currentAnnotationStyle.color,
                fontSize: currentAnnotationFontSize,
                fontName: ".AppleSystemUIFont"
            ))
        case .mosaic:
            MosaicAnnotationTool(brushSize: 40)
        default:
            nil
        }
    }

    private func beginAnnotation(at localPoint: CGPoint, on display: ScreenshotDisplay) {
        guard var tool = activeAnnotationTool,
              let annotationPoint = annotationPoint(from: localPoint, on: display) else {
            return
        }
        tool.beginDrawing(at: annotationPoint)
        activeAnnotationTool = tool
        updateMosaicBrushPreview(center: annotationPoint)
        pushAnnotationState()
    }

    private func updateAnnotation(to localPoint: CGPoint, on display: ScreenshotDisplay) {
        guard var tool = activeAnnotationTool,
              let annotationPoint = annotationPoint(from: localPoint, on: display) else {
            return
        }
        tool.continueDrawing(to: annotationPoint)
        activeAnnotationTool = tool
        updateMosaicBrushPreview(center: annotationPoint)
        pushAnnotationState()
    }

    private func endAnnotation(at localPoint: CGPoint, on display: ScreenshotDisplay) {
        guard var tool = activeAnnotationTool,
              let annotationPoint = annotationPoint(from: localPoint, on: display) else {
            return
        }
        if let element = tool.endDrawing(at: annotationPoint) {
            annotationDocument.add(element)
            if activeAnnotationRole != .select, activeAnnotationRole != .text {
                annotationDocument.selectElement(id: nil)
            }
        }
        activeAnnotationTool = tool
        updateMosaicBrushPreview(center: annotationPoint)
        pushAnnotationState()
    }

    private func updateAnnotationHover(to localPoint: CGPoint?, on display: ScreenshotDisplay) {
        guard activeAnnotationRole == .mosaic,
              let localPoint,
              let annotationPoint = annotationPoint(from: localPoint, on: display) else {
            activeBrushPreview = nil
            pushAnnotationState()
            return
        }
        updateMosaicBrushPreview(center: annotationPoint)
        pushAnnotationState()
    }

    private func updateMosaicBrushPreview(center: CGPoint) {
        guard activeAnnotationRole == .mosaic,
              let tool = activeAnnotationTool as? MosaicAnnotationTool else {
            activeBrushPreview = nil
            return
        }
        activeBrushPreview = AnnotationBrushPreview(center: center, size: tool.brushSize)
    }

    private func selectAnnotation(at localPoint: CGPoint, on display: ScreenshotDisplay) {
        guard let annotationPoint = annotationPoint(from: localPoint, on: display) else {
            return
        }
        annotationDocument.selectElement(id: annotationDocument.hitTestElement(at: annotationPoint))
        pushAnnotationState()
    }

    private func toggleAnnotationSelection(at localPoint: CGPoint, on display: ScreenshotDisplay) {
        guard let annotationPoint = annotationPoint(from: localPoint, on: display),
              let hitID = annotationDocument.hitTestElement(at: annotationPoint) else {
            return
        }
        annotationDocument.toggleElementSelection(id: hitID)
        pushAnnotationState()
    }

    private func beginAnnotationMove(at localPoint: CGPoint, on display: ScreenshotDisplay) {
        guard let annotationPoint = annotationPoint(from: localPoint, on: display),
              let hitID = annotationDocument.hitTestElement(at: annotationPoint) else {
            annotationDocument.selectElement(id: nil)
            activeAnnotationMovePoint = nil
            hasRecordedAnnotationMoveUndo = false
            pushAnnotationState()
            return
        }

        if !annotationDocument.selectedElementIDs.contains(hitID) {
            annotationDocument.selectElement(id: hitID)
        }
        activeAnnotationMovePoint = annotationPoint
        hasRecordedAnnotationMoveUndo = false
        pushAnnotationState()
    }

    private func updateAnnotationMove(to localPoint: CGPoint, on display: ScreenshotDisplay) {
        guard let previousPoint = activeAnnotationMovePoint,
              let annotationPoint = annotationPoint(from: localPoint, on: display) else {
            return
        }
        let offset = CGSize(
            width: annotationPoint.x - previousPoint.x,
            height: annotationPoint.y - previousPoint.y
        )
        guard offset != .zero else {
            return
        }
        if !hasRecordedAnnotationMoveUndo {
            annotationDocument.beginUndoGroup()
            hasRecordedAnnotationMoveUndo = true
        }
        annotationDocument.moveSelectedElement(by: offset, recordsUndo: false)
        activeAnnotationMovePoint = annotationPoint
        pushAnnotationState()
    }

    private func endAnnotationMove() {
        activeAnnotationMovePoint = nil
        hasRecordedAnnotationMoveUndo = false
    }

    private func beginAnnotationResize(
        handle: AnnotationResizeHandle,
        at localPoint: CGPoint,
        on display: ScreenshotDisplay
    ) {
        guard annotationDocument.selectedElementID != nil,
              annotationPoint(from: localPoint, on: display) != nil else {
            activeAnnotationResizeHandle = nil
            hasRecordedAnnotationResizeUndo = false
            return
        }
        activeAnnotationResizeHandle = handle
        hasRecordedAnnotationResizeUndo = false
    }

    private func updateAnnotationResize(to localPoint: CGPoint, on display: ScreenshotDisplay) {
        guard let handle = activeAnnotationResizeHandle,
              let annotationPoint = annotationPoint(from: localPoint, on: display) else {
            return
        }
        if !hasRecordedAnnotationResizeUndo {
            annotationDocument.beginUndoGroup()
            hasRecordedAnnotationResizeUndo = true
        }
        annotationDocument.resizeSelectedElement(handle: handle, to: annotationPoint, recordsUndo: false)
        pushAnnotationState()
    }

    private func endAnnotationResize() {
        activeAnnotationResizeHandle = nil
        hasRecordedAnnotationResizeUndo = false
    }

    private func deleteSelectedAnnotation() {
        annotationDocument.deleteSelectedElement()
        pushAnnotationState()
    }

    private func copySelectedAnnotations() {
        let selectedIDs = Set(annotationDocument.selectedElementIDs)
        copiedAnnotationElements = annotationDocument.elements.filter { selectedIDs.contains($0.id) }
    }

    private func pasteCopiedAnnotations(offset: CGSize = CGSize(width: 15, height: 15)) {
        guard !copiedAnnotationElements.isEmpty else {
            return
        }
        let pastedElements = copiedAnnotationElements.map { element in
            element.duplicated(offset: offset)
        }
        annotationDocument.add(contentsOf: pastedElements)
    }

    private func duplicateSelectedAnnotations(offset: CGSize = CGSize(width: 15, height: 15)) {
        copySelectedAnnotations()
        pasteCopiedAnnotations(offset: offset)
    }

    private func commitTextAnnotation(_ text: String, at localPoint: CGPoint, on display: ScreenshotDisplay) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty,
              let annotationPoint = annotationPoint(from: localPoint, on: display),
              let state = currentSelectionState else {
            return
        }
        annotationDocument.add(.text(TextAnnotationElement(
            position: annotationPoint,
            content: content,
            style: ScreenshotAnnotationTextStyle(
                color: currentAnnotationStyle.color,
                fontSize: currentAnnotationFontSize * max(state.displayScale, 1),
                fontName: ".AppleSystemUIFont"
            )
        )))
        pushAnnotationState()
    }

    private func annotationPoint(from localPoint: CGPoint, on display: ScreenshotDisplay) -> CGPoint? {
        guard let state = currentSelectionState,
              state.normalizedRect.intersects(display.frame) else {
            return nil
        }
        let selectionRect = state.normalizedRect.offsetBy(
            dx: -display.frame.minX,
            dy: -display.frame.minY
        )
        let scale = max(state.displayScale, 1)
        let pixelBounds = CGRect(origin: .zero, size: state.pixelRect.size)
        let annotationPoint = CGPoint(
            x: (localPoint.x - selectionRect.minX) * scale,
            y: (localPoint.y - selectionRect.minY) * scale
        )
        return CGPoint(
            x: min(max(annotationPoint.x, pixelBounds.minX), pixelBounds.maxX),
            y: min(max(annotationPoint.y, pixelBounds.minY), pixelBounds.maxY)
        )
    }


    private func updateActiveToolStyle() {
        guard var tool = activeAnnotationTool else {
            return
        }
        let updatedTextStyle = ScreenshotAnnotationTextStyle(
            color: currentAnnotationStyle.color,
            fontSize: currentAnnotationFontSize,
            fontName: ".AppleSystemUIFont"
        )
        tool.style = currentAnnotationStyle
        tool.textStyle = updatedTextStyle
        activeAnnotationTool = tool
    }
}

private struct WindowRecord {
    let display: ScreenshotDisplay
    let image: CGImage?
    let window: any SelectionOverlayWindowControlling
}

private struct ActiveSelection {
    let display: ScreenshotDisplay
    let startPoint: CGPoint
}

private enum SelectionOrigin {
    case manual
    case targeted
}

private struct PointerDragSession {
    let startedOnDisplayID: CGDirectDisplayID
}

public enum DefaultScrollingScreenshotCapturer {
    @MainActor
    public static func capture(_ request: ScrollingScreenshotRequest) async -> ScrollingScreenshotCaptureResult? {
        await ScrollingScreenshotController(request: request).start()
    }
}

private extension CGRect {
    var area: CGFloat {
        guard width > 0, height > 0 else { return 0 }
        return width * height
    }
}

private final class SelectionOverlayEscapeEventTap: @unchecked Sendable {
    private let onEscape: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onEscape: @escaping @MainActor () -> Void) {
        self.onEscape = onEscape
    }

    func start() {
        guard eventTap == nil else { return }
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.handleEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    deinit {
        stop()
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard type == .keyDown,
              let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let monitor = Unmanaged<SelectionOverlayEscapeEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 53 else {
            return Unmanaged.passUnretained(event)
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                monitor.onEscape()
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    monitor.onEscape()
                }
            }
        }
        return nil
    }
}

@MainActor
public final class AppKitSelectionOverlayWindowFactory: SelectionOverlayWindowMaking {
    public init() {}

    public func makeWindow(
        configuration: SelectionOverlayWindowConfiguration,
        eventHandler: @escaping @MainActor (SelectionOverlayWindowEvent) -> Void
    ) -> any SelectionOverlayWindowControlling {
        AppKitSelectionOverlayWindow(configuration: configuration, eventHandler: eventHandler)
    }
}

@MainActor
private final class AppKitSelectionOverlayWindow: NSPanel, SelectionOverlayWindowControlling {
    private let overlayView: SelectionOverlayContentView
    private let eventHandler: @MainActor (SelectionOverlayWindowEvent) -> Void
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var notificationObserver: Any?
    private var isClosingOverlay = false
    private var isHiddenForModalPresentation = false

    init(
        configuration: SelectionOverlayWindowConfiguration,
        eventHandler: @escaping @MainActor (SelectionOverlayWindowEvent) -> Void
    ) {
        self.eventHandler = eventHandler
        overlayView = SelectionOverlayContentView(configuration: configuration, eventHandler: eventHandler)
        super.init(
            contentRect: configuration.display.overlayFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]
        level = configuration.isFloating ? .screenSaver : .normal
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true

        contentView = overlayView
        overlayView.windowTargetResolver = SelectionWindowTargetResolver.live(
            screenFrame: configuration.display.frame,
            ownWindowID: CGWindowID(windowNumber)
        )
        installResilienceHooks()
    }

    override var canBecomeKey: Bool { true }

    var savePanelHostWindow: NSWindow { self }

    func orderFront() {
        orderFrontRegardless()
    }

    func setVisibleForModalPresentation(_ isVisible: Bool) {
        if isVisible {
            isHiddenForModalPresentation = false
            orderFront()
        } else {
            isHiddenForModalPresentation = true
            orderOut(nil)
        }
    }

    func updateSelection(_ state: SelectionState?) {
        overlayView.selectionState = state
    }

    func updateAnnotationState(_ state: SelectionAnnotationOverlayState) {
        overlayView.annotationState = state
    }

    func setWindowTargetingEnabled(_ isEnabled: Bool) {
        overlayView.isWindowTargetingEnabled = isEnabled
    }

    func setAllowsTargetedSelectionReplacement(_ isEnabled: Bool) {
        overlayView.allowsTargetedSelectionReplacement = isEnabled
    }

    func setScrollCaptureActive(_ isActive: Bool, selection: SelectionState?) {
        ignoresMouseEvents = isActive
        overlayView.isScrollCapturing = isActive
        if let selection {
            overlayView.selectionState = selection
        }
    }

    func commitInlineTextEditing() {
        overlayView.commitInlineTextEditing()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            eventHandler(.cancelRequested)
        case 36, 76:
            eventHandler(.completeRequested)
        case 51, 117:
            eventHandler(.deleteSelectedAnnotationRequested)
        case 6 where event.modifierFlags.contains(.command) && event.isCommandSelectionShortcut:
            eventHandler(.toolbarRole(.undo))
        case 6 where event.modifierFlags.contains(.command)
                && event.modifierFlags.contains(.shift)
                && !event.modifierFlags.contains(.option)
                && !event.modifierFlags.contains(.control):
            eventHandler(.toolbarRole(.redo))
        case 8 where event.isCommandSelectionShortcut:
            eventHandler(.toolbarRole(.copy))
        case 9 where event.isCommandSelectionShortcut:
            eventHandler(.toolbarRole(.paste))
        case 2 where event.isCommandSelectionShortcut:
            eventHandler(.toolbarRole(.duplicate))
        // F full-screen and Tab window-snap behavior follows macshot's overlay UX.
        case 48 where event.isPlainSelectionShortcut:
            eventHandler(.windowTargetingToggleRequested)
        case 3 where event.isPlainSelectionShortcut:
            eventHandler(.fullScreenRequested)
        default:
            super.keyDown(with: event)
        }
    }

    override func close() {
        cleanupResilienceHooks()
        super.close()
    }

    private func installResilienceHooks() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.eventHandler(.cancelRequested)
                return nil
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                self?.eventHandler(.deleteSelectedAnnotationRequested)
                return nil
            }
            if event.keyCode == 6,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control) {
                self?.eventHandler(.toolbarRole(.redo))
                return nil
            }
            if event.keyCode == 6,
               event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control) {
                self?.eventHandler(.toolbarRole(.undo))
                return nil
            }
            if event.keyCode == 8, event.isCommandSelectionShortcut {
                self?.eventHandler(.toolbarRole(.copy))
                return nil
            }
            if event.keyCode == 9, event.isCommandSelectionShortcut {
                self?.eventHandler(.toolbarRole(.paste))
                return nil
            }
            if event.keyCode == 2, event.isCommandSelectionShortcut {
                self?.eventHandler(.toolbarRole(.duplicate))
                return nil
            }
            if event.keyCode == 48, event.isPlainSelectionShortcut {
                self?.eventHandler(.windowTargetingToggleRequested)
                return nil
            }
            if event.keyCode == 3, event.isPlainSelectionShortcut {
                self?.eventHandler(.fullScreenRequested)
                return nil
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.eventHandler(.cancelRequested)
            }
        }

        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      !self.isClosingOverlay,
                      !self.isHiddenForModalPresentation,
                      self.isVisible else {
                    return
                }
                self.orderFrontRegardless()
            }
        }
    }

    private func cleanupResilienceHooks() {
        guard !isClosingOverlay else { return }
        isClosingOverlay = true
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
            self.notificationObserver = nil
        }
    }
}

private extension NSEvent {
    var isPlainSelectionShortcut: Bool {
        !modifierFlags.contains(.command)
            && !modifierFlags.contains(.option)
            && !modifierFlags.contains(.control)
    }

    var isCommandSelectionShortcut: Bool {
        modifierFlags.contains(.command)
            && !modifierFlags.contains(.option)
            && !modifierFlags.contains(.control)
    }
}

private extension Optional where Wrapped == SelectionToolbarRole {
    var isDrawingAnnotationRole: Bool {
        switch self {
        case .pen, .circle, .rectangle, .arrow, .dotMarker, .numberedMarker, .mosaic:
            return true
        case .select, .text, .scrollCapture, .textRecognition, .translate, .color, .lineWidth, .fontSize, .download,
             .copy, .paste, .duplicate, .undo, .redo, .cancel, .complete, nil:
            return false
        }
    }
}

private extension ScreenshotAnnotationColor {
    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

@MainActor
final class SelectionOverlayContentView: NSView {
    private let configuration: SelectionOverlayWindowConfiguration
    private let eventHandler: @MainActor (SelectionOverlayWindowEvent) -> Void
    private let pointerEventRouter: SelectionOverlayPointerEventRouter
    private let snapshotImage: CGImage?
    private let snapshot: NSImage?
    var windowTargetResolver: SelectionWindowTargetResolver?
    var isWindowTargetingEnabled = true {
        didSet {
            pendingWindowTargetRect = nil
            highlightedWindowRect = nil
            needsDisplay = true
        }
    }
    var allowsTargetedSelectionReplacement = false
    var isScrollCapturing = false {
        didSet {
            guard oldValue != isScrollCapturing else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    private var highlightedWindowRect: CGRect? {
        didSet { needsDisplay = true }
    }
    private var pendingWindowTargetRect: CGRect?
    private var selectedAnnotationResizeHandleIsActive = false
    private var isConsumingToolbarInteraction = false
    private var pressedToolbarRole: SelectionToolbarRole?
    private var hoveredToolbarRole: SelectionToolbarRole? {
        didSet {
            guard oldValue != hoveredToolbarRole else { return }
            needsDisplay = true
        }
    }
    private var loadingSpinnerTask: Task<Void, Never>?
    private var loadingSpinnerPhase = 0
    private var pointerTrackingArea: NSTrackingArea?
    private var inlineTextField: InlineAnnotationTextField?
    private var inlineTextAnchor: CGPoint?
    private var isMovingSelection = false {
        didSet {
            guard oldValue != isMovingSelection else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    private var activeSelectionResizeCursorKind: SelectionOverlayCursorKind? {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    var selectionState: SelectionState? {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var annotationState = SelectionAnnotationOverlayState() {
        didSet {
            if annotationState.activeRole != .text {
                cancelInlineTextEditing()
            }
            updateLoadingSpinnerTimer()
            needsDisplay = true
        }
    }

    deinit {
        loadingSpinnerTask?.cancel()
    }

    init(
        configuration: SelectionOverlayWindowConfiguration,
        eventHandler: @escaping @MainActor (SelectionOverlayWindowEvent) -> Void
    ) {
        self.configuration = configuration
        self.eventHandler = eventHandler
        self.pointerEventRouter = SelectionOverlayPointerEventRouter(eventHandler: eventHandler)
        self.snapshotImage = configuration.snapshotImage
        if let snapshotImage = configuration.snapshotImage {
            self.snapshot = NSImage(
                cgImage: snapshotImage,
                size: configuration.display.overlayFrame.size
            )
        } else {
            self.snapshot = nil
        }
        super.init(frame: CGRect(origin: .zero, size: configuration.display.overlayFrame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool {
        false
    }

    override func resetCursorRects() {
        if isScrollCapturing {
            return
        }
        if let activeSelectionResizeCursorKind {
            addCursorRect(bounds, cursor: activeSelectionResizeCursorKind.nsCursor)
            return
        }
        if isMovingSelection {
            addCursorRect(bounds, cursor: NSCursor.closedHand)
            return
        }
        addCursorRect(bounds, cursor: NSCursor.crosshair)
        guard let selectionState, selectionState.isValidSelection else { return }
        let localSelectionRect = selectionState.normalizedRect.offsetBy(
            dx: -configuration.display.frame.minX,
            dy: -configuration.display.frame.minY
        )
        let selectionCursorRect = localSelectionRect.intersection(bounds)
        guard !selectionCursorRect.isEmpty else { return }
        addCursorRect(selectionCursorRect, cursor: NSCursor.openHand)
        let presentation = SelectionOverlayPresentation(state: selectionState, handleSize: 16)
        for handleRect in presentation.resizeHandleRects {
            let localHandleRect = handleRect.offsetBy(
                dx: -configuration.display.frame.minX,
                dy: -configuration.display.frame.minY
            )
            let handleCursorRect = localHandleRect.intersection(bounds)
            guard !handleCursorRect.isEmpty else { continue }
            let kind = SelectionOverlayCursorResolver.cursorKind(
                at: CGPoint(x: handleRect.midX, y: handleRect.midY),
                selectionState: selectionState,
                isMovingSelection: false
            )
            addCursorRect(handleCursorRect, cursor: kind.nsCursor)
        }
    }

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        guard !isScrollCapturing else { return }
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount >= 2 {
            eventHandler(.doubleClick(point))
            return
        }

        // Popover 命中：点 popover 选项，或在 popover 内空白处不做事（等 mouseUp 关闭由后续逻辑处理）。
        if let (role, index) = popoverOption(at: point) {
            eventHandler(.popoverOptionSelected(role, index))
            return
        }
        // Popover 打开时点 popover 区域空白（非选项）— 啥也不做，避免触发底层选区操作。
        if popoverContains(point) {
            return
        }
        // Popover 打开时点 popover 之外（且不是工具栏按钮）— 关闭 popover，吞掉这次点击。
        if annotationState.popoverRole != nil, !toolbarContains(point) {
            eventHandler(.popoverDismissed)
            return
        }

        if toolbarContains(point) {
            isConsumingToolbarInteraction = true
            pressedToolbarRole = toolbarRole(at: point)
            needsDisplay = true
            if let role = pressedToolbarRole {
                if role == .cancel {
                    cancelInlineTextEditing()
                } else {
                    commitInlineTextEditing()
                }
                eventHandler(.toolbarRole(role))
            }
            return
        }

        if annotationState.activeRole == .text, selectionRectContains(point) {
            beginInlineTextEditing(at: point)
            return
        }

        if annotationState.activeRole == .select,
           let handle = selectedAnnotationResizeHandle(at: point) {
            selectedAnnotationResizeHandleIsActive = true
            eventHandler(.annotationResizeBegan(handle, point))
            return
        }

        if annotationState.activeRole == .select,
           event.modifierFlags.contains(.shift),
           selectionRectContains(point) {
            selectedAnnotationResizeHandleIsActive = false
            eventHandler(.annotationToggleSelectionRequested(point))
            return
        }

        if annotationState.activeRole == .select, selectionRectContains(point) {
            selectedAnnotationResizeHandleIsActive = false
            eventHandler(.annotationMoveBegan(point))
            return
        }

        if annotationState.activeRole.isDrawingAnnotationRole, selectionRectContains(point) {
            eventHandler(.annotationBegan(point))
            return
        }

        pendingWindowTargetRect = selectionResizeHandleContains(point) ? nil : windowTarget(at: point)?.frame
        let globalPoint = globalPointerPoint(for: event)
        let cursorKind = SelectionOverlayCursorResolver.cursorKind(
            at: globalPoint,
            selectionState: selectionState,
            isMovingSelection: false
        )
        if allowsTargetedSelectionReplacement {
            isMovingSelection = false
            activeSelectionResizeCursorKind = nil
        } else {
            isMovingSelection = cursorKind == .openHand
            activeSelectionResizeCursorKind = cursorKind.isResize ? cursorKind : nil
        }
        pointerEventRouter.mouseDown(atGlobalPoint: globalPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isScrollCapturing else { return }
        if isConsumingToolbarInteraction {
            return
        }
        if annotationState.activeRole == .text {
            return
        }
        if annotationState.activeRole == .select {
            let point = convert(event.locationInWindow, from: nil)
            if selectedAnnotationResizeHandleIsActive {
                eventHandler(.annotationResizeChanged(point))
            } else {
                eventHandler(.annotationMoveChanged(point))
            }
            return
        }
        if annotationState.activeRole.isDrawingAnnotationRole {
            eventHandler(.annotationChanged(convert(event.locationInWindow, from: nil)))
            return
        }
        pendingWindowTargetRect = nil
        highlightedWindowRect = nil
        pointerEventRouter.mouseDragged(atGlobalPoint: globalPointerPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard !isScrollCapturing else { return }
        if isConsumingToolbarInteraction {
            isConsumingToolbarInteraction = false
            pressedToolbarRole = nil
            needsDisplay = true
            return
        }
        if annotationState.activeRole == .text {
            return
        }
        if annotationState.activeRole == .select {
            let point = convert(event.locationInWindow, from: nil)
            if selectedAnnotationResizeHandleIsActive {
                eventHandler(.annotationResizeEnded(point))
            } else {
                eventHandler(.annotationMoveEnded(point))
            }
            selectedAnnotationResizeHandleIsActive = false
            return
        }
        if annotationState.activeRole.isDrawingAnnotationRole {
            eventHandler(.annotationEnded(convert(event.locationInWindow, from: nil)))
            return
        }
        if let pendingWindowTargetRect,
           allowsTargetedSelectionReplacement || !(selectionState?.isValidSelection ?? false) {
            self.pendingWindowTargetRect = nil
            highlightedWindowRect = nil
            pointerEventRouter.mouseUp(atGlobalPoint: globalPointerPoint(for: event))
            isMovingSelection = false
            activeSelectionResizeCursorKind = nil
            eventHandler(.windowTargetSelected(pendingWindowTargetRect))
            return
        }
        pendingWindowTargetRect = nil
        pointerEventRouter.mouseUp(atGlobalPoint: globalPointerPoint(for: event))
        isMovingSelection = false
        activeSelectionResizeCursorKind = nil
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isScrollCapturing else { return }
        let point = convert(event.locationInWindow, from: nil)
        // Toolbar hover tooltip — works regardless of mosaic/selection state.
        let newHover = toolbarRole(at: point)
        if newHover != hoveredToolbarRole {
            hoveredToolbarRole = newHover
        }

        if annotationState.activeRole == .mosaic {
            if selectionRectContains(point) {
                eventHandler(.annotationHoverChanged(point))
            } else {
                eventHandler(.annotationHoverChanged(nil))
            }
            return
        }

        guard selectionState == nil || selectionState?.isValidSelection == false else {
            return
        }
        highlightedWindowRect = windowTarget(at: point)?.frame.offsetBy(
            dx: -configuration.display.frame.minX,
            dy: -configuration.display.frame.minY
        )
    }

    override func mouseExited(with event: NSEvent) {
        guard !isScrollCapturing else { return }
        if annotationState.activeRole == .mosaic {
            eventHandler(.annotationHoverChanged(nil))
        }
        if hoveredToolbarRole != nil {
            hoveredToolbarRole = nil
        }
    }

    private func globalPointerPoint(for event: NSEvent) -> CGPoint {
        if let point = event.cgEvent?.location {
            return point
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: localPoint.x + configuration.display.frame.minX,
            y: localPoint.y + configuration.display.frame.minY
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if !isScrollCapturing {
            snapshot?.draw(in: bounds)
        }

        guard let selectionState else {
            NSColor.black.withAlphaComponent(0.18).setFill()
            bounds.fill()
            drawHighlightedWindowIfNeeded()
            return
        }

        let presentation = SelectionOverlayPresentation(state: selectionState)
        let selectionRect = SelectionOverlayDisplayGeometry.localSelectionRect(
            for: selectionState,
            on: configuration.display
        )
        let shouldDrawSelectionChrome = SelectionOverlayDisplayGeometry.shouldDrawSelectionChrome(
            localSelectionRect: selectionRect,
            visibleBounds: bounds
        )

        drawDimmedOutside(selectionRect, alpha: presentation.outsideDimmingAlpha)
        if !isScrollCapturing {
            drawAnnotations(in: selectionRect, displayScale: selectionState.displayScale)
        }
        drawSelection(selectionRect, presentation: presentation)
        if !isScrollCapturing, shouldDrawSelectionChrome {
            drawToolbar(SelectionToolbarPresentation.default, near: selectionRect)
            drawInlineTranslationStatusIfNeeded(near: selectionRect)
            drawToolbarTooltipIfNeeded()
        }
    }

    private func selectionRectContains(_ point: CGPoint) -> Bool {
        guard let selectionState else {
            return false
        }
        let selectionRect = SelectionOverlayDisplayGeometry.localSelectionRect(
            for: selectionState,
            on: configuration.display
        )
        return selectionRect.contains(point)
    }

    private func selectionResizeHandleContains(_ point: CGPoint) -> Bool {
        guard let selectionState,
              selectionState.isValidSelection else {
            return false
        }
        let presentation = SelectionOverlayPresentation(state: selectionState, handleSize: 16)
        return presentation.resizeHandleRects.contains { handle in
            handle
                .offsetBy(
                    dx: -configuration.display.frame.minX,
                    dy: -configuration.display.frame.minY
                )
                .contains(point)
        }
    }

    private func selectedAnnotationResizeHandle(at point: CGPoint) -> AnnotationResizeHandle? {
        guard let selectionState,
              let selectedID = annotationState.document.selectedElementID,
              let element = annotationState.document.elements.first(where: { $0.id == selectedID }) else {
            return nil
        }
        let selectionRect = selectionState.normalizedRect.offsetBy(
            dx: -configuration.display.frame.minX,
            dy: -configuration.display.frame.minY
        )
        let scale = max(selectionState.displayScale, 1)
        let handleSize: CGFloat = 16
        for (handle, handlePoint) in resizeHandles(for: element, in: selectionRect, scale: scale) {
            let hitRect = CGRect(
                x: handlePoint.x - handleSize / 2,
                y: handlePoint.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            if hitRect.contains(point) {
                return handle
            }
        }
        return nil
    }

    private func beginInlineTextEditing(at point: CGPoint) {
        commitInlineTextEditing()
        let width = min(max(bounds.width - point.x - 12, 80), 220)
        let field = InlineAnnotationTextField(frame: CGRect(
            x: point.x,
            y: point.y,
            width: width,
            height: 28
        ))
        field.font = NSFont.systemFont(ofSize: 14)
        field.textColor = .labelColor
        field.backgroundColor = NSColor.white.withAlphaComponent(0.88)
        field.isBordered = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 5
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.45).cgColor
        field.onCommit = { [weak self] text in
            self?.finishInlineTextEditing(committedText: text)
        }
        field.onCancel = { [weak self] in
            self?.eventHandler(.cancelRequested)
        }

        inlineTextField = field
        inlineTextAnchor = point
        addSubview(field)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(field)
    }

    fileprivate func commitInlineTextEditing() {
        guard let field = inlineTextField else {
            return
        }
        finishInlineTextEditing(committedText: field.stringValue)
    }

    private func finishInlineTextEditing(committedText: String) {
        guard let field = inlineTextField,
              let anchor = inlineTextAnchor else {
            return
        }
        inlineTextField = nil
        inlineTextAnchor = nil
        field.removeFromSuperview()
        eventHandler(.annotationTextCommitted(anchor, committedText))
    }

    private func cancelInlineTextEditing() {
        inlineTextField?.removeFromSuperview()
        inlineTextField = nil
        inlineTextAnchor = nil
    }

    private func windowTarget(at localPoint: CGPoint) -> SelectionWindowTarget? {
        guard isWindowTargetingEnabled else {
            return nil
        }
        let globalPoint = CGPoint(
            x: localPoint.x + configuration.display.frame.minX,
            y: localPoint.y + configuration.display.frame.minY
        )
        return windowTargetResolver?.targetWindow(at: globalPoint)
    }

    private func drawHighlightedWindowIfNeeded() {
        guard let highlightedWindowRect else { return }
        NSColor.systemGreen.withAlphaComponent(0.22).setFill()
        highlightedWindowRect.fill()
        NSColor.systemGreen.setStroke()
        let border = NSBezierPath(rect: highlightedWindowRect)
        border.lineWidth = 2
        border.stroke()
    }

    private func drawDimmedOutside(_ selectionRect: CGRect, alpha: CGFloat) {
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: selectionRect))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(alpha).setFill()
        path.fill()
    }

    private func drawSelection(_ selectionRect: CGRect, presentation: SelectionOverlayPresentation) {
        let green = NSColor.systemGreen
        green.setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 2
        border.stroke()

        green.setFill()
        for handle in presentation.resizeHandleRects {
            let localHandle = handle.offsetBy(
                dx: -configuration.display.frame.minX,
                dy: -configuration.display.frame.minY
            )
            NSBezierPath(roundedRect: localHandle, xRadius: 2, yRadius: 2).fill()
        }

        drawSizeReadout(presentation.sizeReadout, near: selectionRect)
    }

    private func drawSizeReadout(_ text: String, near selectionRect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.92),
        ]
        let attributed = NSAttributedString(string: " \(text) ", attributes: attributes)
        attributed.draw(
            at: CGPoint(
                x: selectionRect.minX,
                y: max(4, selectionRect.minY - 20)
            )
        )
    }

    private func drawAnnotations(in selectionRect: CGRect, displayScale: CGFloat) {
        let scale = max(displayScale, 1)
        if let translatedOverlay = annotationState.translatedOverlay {
            drawTranslatedOverlayAnnotation(translatedOverlay, in: selectionRect, scale: scale)
        }
        for element in annotationState.document.elements {
            drawAnnotationElement(element, in: selectionRect, scale: scale, isPreview: false)
        }
        drawSelectedAnnotationBounds(in: selectionRect, scale: scale)
        if let preview = annotationState.preview {
            drawAnnotationElement(preview, in: selectionRect, scale: scale, isPreview: true)
        }
        if let brushPreview = annotationState.brushPreview {
            drawMosaicBrushPreview(brushPreview, in: selectionRect, scale: scale)
        }
    }

    private func drawAnnotationElement(
        _ element: AnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat,
        isPreview: Bool
    ) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        switch element {
        case .pen(let element):
            drawPenAnnotation(element, in: selectionRect, scale: scale, isPreview: isPreview)
        case .ellipse(let element):
            drawEllipseAnnotation(element, in: selectionRect, scale: scale, isPreview: isPreview)
        case .rectangle(let element):
            drawRectangleAnnotation(element, in: selectionRect, scale: scale, isPreview: isPreview)
        case .arrow(let element):
            drawArrowAnnotation(element, in: selectionRect, scale: scale, isPreview: isPreview)
        case .dotMarker(let element):
            drawDotMarkerAnnotation(element, in: selectionRect, scale: scale)
        case .numberedMarker(let element):
            drawNumberedMarkerAnnotation(element, in: selectionRect, scale: scale)
        case .text(let element):
            drawTextAnnotation(element, in: selectionRect, scale: scale)
        case .mosaic(let element):
            drawMosaicAnnotation(element, in: selectionRect, scale: scale)
        case .translatedOverlay(let element):
            drawTranslatedOverlayAnnotation(element, in: selectionRect, scale: scale)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelectedAnnotationBounds(in selectionRect: CGRect, scale: CGFloat) {
        let selectedIDs = Set(annotationState.document.selectedElementIDs)
        guard annotationState.activeRole == .select,
              !selectedIDs.isEmpty else {
            return
        }
        NSColor.systemGreen.setStroke()
        for element in annotationState.document.elements where selectedIDs.contains(element.id) {
            guard element.kind != .mosaic else { continue }
            let rect = overlayRect(element.bounds, in: selectionRect, scale: scale).insetBy(dx: -4, dy: -4)
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 1.5
            path.setLineDash([5, 3], count: 2, phase: 0)
            path.stroke()
        }
        guard let selectedID = annotationState.document.selectedElementID,
              let element = annotationState.document.elements.first(where: { $0.id == selectedID }) else {
            return
        }
        for (_, point) in resizeHandles(for: element, in: selectionRect, scale: scale) {
            let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            NSBezierPath(rect: rect).fill()
            NSColor.systemGreen.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawMosaicBrushPreview(
        _ preview: AnnotationBrushPreview,
        in selectionRect: CGRect,
        scale: CGFloat
    ) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()
        let center = overlayPoint(preview.center, in: selectionRect, scale: scale)
        let radius = max(preview.size / max(scale, 1) / 2, 1)
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let path = NSBezierPath(ovalIn: rect)
        NSColor.systemGreen.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.systemGreen.withAlphaComponent(0.78).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPenAnnotation(
        _ element: FreehandAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat,
        isPreview: Bool
    ) {
        guard let first = element.points.first, element.points.count >= 2 else {
            return
        }
        let path = NSBezierPath()
        path.move(to: overlayPoint(first, in: selectionRect, scale: scale))
        for point in element.points.dropFirst() {
            path.line(to: overlayPoint(point, in: selectionRect, scale: scale))
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = overlayLineWidth(element.style.lineWidth, scale: scale)
        element.style.color.nsColor.withAlphaComponent(isPreview ? 0.72 : CGFloat(element.style.color.alpha)).setStroke()
        path.stroke()
    }

    private func drawEllipseAnnotation(
        _ element: EllipseAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat,
        isPreview: Bool
    ) {
        let rect = overlayRect(element.rect, in: selectionRect, scale: scale)
        if let fillColor = element.style.fillColor {
            fillColor.nsColor.withAlphaComponent(isPreview ? 0.18 : CGFloat(fillColor.alpha)).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
        element.style.color.nsColor.withAlphaComponent(isPreview ? 0.72 : CGFloat(element.style.color.alpha)).setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = overlayLineWidth(element.style.lineWidth, scale: scale)
        path.stroke()
    }

    private func drawRectangleAnnotation(
        _ element: RectangleAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat,
        isPreview: Bool
    ) {
        let rect = overlayRect(element.rect, in: selectionRect, scale: scale)
        if let fillColor = element.style.fillColor {
            fillColor.nsColor.withAlphaComponent(isPreview ? 0.18 : CGFloat(fillColor.alpha)).setFill()
            rect.fill()
        }
        element.style.color.nsColor.withAlphaComponent(isPreview ? 0.72 : CGFloat(element.style.color.alpha)).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = overlayLineWidth(element.style.lineWidth, scale: scale)
        path.stroke()
    }

    private func drawArrowAnnotation(
        _ element: ArrowAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat,
        isPreview: Bool
    ) {
        let start = overlayPoint(element.startPoint, in: selectionRect, scale: scale)
        let end = overlayPoint(element.endPoint, in: selectionRect, scale: scale)
        let lineWidth = overlayLineWidth(element.style.lineWidth, scale: scale)
        element.style.color.nsColor.withAlphaComponent(isPreview ? 0.72 : CGFloat(element.style.color.alpha)).setStroke()
        element.style.color.nsColor.withAlphaComponent(isPreview ? 0.72 : CGFloat(element.style.color.alpha)).setFill()

        let line = NSBezierPath()
        line.move(to: start)
        line.line(to: end)
        line.lineWidth = lineWidth
        line.lineCapStyle = .round
        line.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength = max(lineWidth * 4, 10)
        let arrowAngle = CGFloat.pi / 6
        let point1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let point2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: point1)
        head.line(to: point2)
        head.close()
        head.fill()
    }

    private func drawDotMarkerAnnotation(
        _ element: DotMarkerAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat
    ) {
        let rect = overlayRect(element.bounds, in: selectionRect, scale: scale)
        (element.style.fillColor ?? element.style.color).nsColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.white.setStroke()
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = max(1, overlayLineWidth(element.style.lineWidth, scale: scale))
        path.stroke()
    }

    private func drawNumberedMarkerAnnotation(
        _ element: NumberedMarkerAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat
    ) {
        drawDotMarkerAnnotation(
            DotMarkerAnnotationElement(
                id: element.id,
                center: element.center,
                radius: element.radius,
                style: element.style
            ),
            in: selectionRect,
            scale: scale
        )
        let center = overlayPoint(element.center, in: selectionRect, scale: scale)
        let fontSize = max(10, element.radius / scale)
        let text = "\(element.number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawTextAnnotation(
        _ element: TextAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat
    ) {
        let point = overlayPoint(element.position, in: selectionRect, scale: scale)
        let font = NSFont(name: element.style.fontName, size: element.style.fontSize / scale)
            ?? NSFont.systemFont(ofSize: element.style.fontSize / scale)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: element.style.color.nsColor,
        ]
        (element.content as NSString).draw(at: point, withAttributes: attributes)
    }

    private func drawMosaicAnnotation(
        _ element: MosaicAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat
    ) {
        let rect = overlayRect(element.bounds, in: selectionRect, scale: scale)
        let block = max(4, element.blockSize / scale)
        guard let snapshotImage,
              let context = NSGraphicsContext.current?.cgContext else {
            drawFallbackMosaicAnnotation(element, in: selectionRect, scale: scale, rect: rect, block: block)
            return
        }

        context.saveGState()
        clipOverlayMosaicStroke(element, in: context, selectionRect: selectionRect, scale: scale)
        drawPixelatedMosaicAnnotation(
            snapshotImage: snapshotImage,
            context: context,
            rect: rect,
            block: block,
            snapshotScale: configuration.snapshotScale
        )
        context.restoreGState()
    }

    private func drawTranslatedOverlayAnnotation(
        _ element: TranslatedOverlayAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat
    ) {
        for line in element.lines {
            let lineRect = overlayRect(line.bounds, in: selectionRect, scale: scale)
            // 白底覆盖原文
            NSColor.white.setFill()
            NSBezierPath(rect: lineRect).fill()

            // 自适应字号
            let text = line.text as NSString
            let maxFontSize = max(8, lineRect.height)
            var fontSize = maxFontSize
            let targetWidth = lineRect.width - 4 / scale
            while fontSize > 8 {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: NSColor.black,
                ]
                let textSize = text.size(withAttributes: attributes)
                if textSize.width <= targetWidth {
                    break
                }
                fontSize -= 1
            }

            // 居中绘制
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
            let textSize = text.size(withAttributes: attributes)
            let textPoint = CGPoint(
                x: lineRect.midX - textSize.width / 2,
                y: lineRect.midY - textSize.height / 2
            )
            NSGraphicsContext.saveGraphicsState()
            text.draw(at: textPoint, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawPixelatedMosaicAnnotation(
        snapshotImage: CGImage,
        context: CGContext,
        rect: CGRect,
        block: CGFloat,
        snapshotScale: CGFloat
    ) {
        context.saveGState()
        context.interpolationQuality = .none
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let blockRect = CGRect(
                    x: x,
                    y: y,
                    width: min(block, rect.maxX - x),
                    height: min(block, rect.maxY - y)
                )
                let samplePoint = SelectionOverlaySnapshotSampler.pixelPoint(
                    forOverlayPoint: CGPoint(x: x, y: y),
                    snapshotScale: snapshotScale
                )
                let sampleRect = CGRect(
                    x: max(0, min(CGFloat(snapshotImage.width - 1), samplePoint.x)),
                    y: max(0, min(CGFloat(snapshotImage.height - 1), samplePoint.y)),
                    width: 1,
                    height: 1
                )
                if let sample = snapshotImage.cropping(to: sampleRect) {
                    NSImage(cgImage: sample, size: CGSize(width: 1, height: 1)).draw(
                        in: blockRect,
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1
                    )
                }
                x += block
            }
            y += block
        }
        context.restoreGState()
    }

    private func drawFallbackMosaicAnnotation(
        _ element: MosaicAnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat,
        rect: CGRect,
        block: CGFloat
    ) {
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext.current?.cgContext {
            clipOverlayMosaicStroke(element, in: context, selectionRect: selectionRect, scale: scale)
        }
        var y = rect.minY
        var flip = false
        while y < rect.maxY {
            var x = rect.minX
            flip.toggle()
            while x < rect.maxX {
                let alpha: CGFloat = flip ? 0.22 : 0.34
                NSColor.black.withAlphaComponent(alpha).setFill()
                CGRect(x: x, y: y, width: block, height: block).fill()
                x += block
                flip.toggle()
            }
            y += block
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func clipOverlayMosaicStroke(
        _ element: MosaicAnnotationElement,
        in context: CGContext,
        selectionRect: CGRect,
        scale: CGFloat
    ) {
        let points = element.points.map { overlayPoint($0, in: selectionRect, scale: scale) }
        context.beginPath()
        if points.count == 1, let point = points.first {
            let brushSize = element.brushSize / scale
            let radius = brushSize / 2
            context.addEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: brushSize,
                height: brushSize
            ))
            context.clip()
            return
        }

        guard let first = points.first else { return }
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.setLineWidth(element.brushSize / scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()
    }

    private func overlayPoint(_ point: CGPoint, in selectionRect: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: selectionRect.minX + point.x / scale,
            y: selectionRect.minY + point.y / scale
        )
    }

    private func overlayRect(_ rect: CGRect, in selectionRect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: selectionRect.minX + rect.minX / scale,
            y: selectionRect.minY + rect.minY / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )
    }

    private func resizeHandles(
        for element: AnnotationElement,
        in selectionRect: CGRect,
        scale: CGFloat
    ) -> [(AnnotationResizeHandle, CGPoint)] {
        switch element {
        case .arrow(let element):
            return [
                (.startPoint, overlayPoint(element.startPoint, in: selectionRect, scale: scale)),
                (.endPoint, overlayPoint(element.endPoint, in: selectionRect, scale: scale)),
            ]
        case .dotMarker(let element):
            return [
                (
                    .endPoint,
                    overlayPoint(
                        CGPoint(x: element.center.x + element.radius, y: element.center.y),
                        in: selectionRect,
                        scale: scale
                    )
                ),
            ]
        case .numberedMarker(let element):
            return [
                (
                    .endPoint,
                    overlayPoint(
                        CGPoint(x: element.center.x + element.radius, y: element.center.y),
                        in: selectionRect,
                        scale: scale
                    )
                ),
            ]
        case .pen, .mosaic:
            return []
        default:
            let bounds = element.bounds
            return [
                (.startPoint, overlayPoint(CGPoint(x: bounds.minX, y: bounds.minY), in: selectionRect, scale: scale)),
                (.endPoint, overlayPoint(CGPoint(x: bounds.maxX, y: bounds.maxY), in: selectionRect, scale: scale)),
                (.startXEndY, overlayPoint(CGPoint(x: bounds.minX, y: bounds.maxY), in: selectionRect, scale: scale)),
                (.endXStartY, overlayPoint(CGPoint(x: bounds.maxX, y: bounds.minY), in: selectionRect, scale: scale)),
            ]
        }
    }

    private func overlayLineWidth(_ lineWidth: CGFloat, scale: CGFloat) -> CGFloat {
        max(1, lineWidth / scale)
    }

    private func drawToolbar(_ toolbar: SelectionToolbarPresentation, near selectionRect: CGRect) {
        let frame = toolbar.toolbarFrame(for: selectionRect, visibleBounds: bounds)
        let toolbarPath = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)
        NSColor.white.withAlphaComponent(0.92).setFill()
        toolbarPath.fill()
        NSColor.systemGreen.withAlphaComponent(0.32).setStroke()
        toolbarPath.lineWidth = 1
        toolbarPath.stroke()

        var itemOrigin = CGPoint(
            x: frame.minX + toolbar.contentPadding,
            y: frame.minY + toolbar.contentPadding
        )
        for item in toolbar.items {
            drawToolbarIcon(item, in: CGRect(origin: itemOrigin, size: CGSize(width: toolbar.itemSize, height: toolbar.itemSize)))
            itemOrigin.x += toolbar.itemSize + toolbar.itemSpacing
        }

        if let popoverRole = annotationState.popoverRole,
           let popoverFrame = popoverFrame(role: popoverRole, toolbarFrame: frame) {
            drawPopover(role: popoverRole, frame: popoverFrame)
        }
    }

    private func drawInlineTranslationStatusIfNeeded(near selectionRect: CGRect) {
        let message: String
        switch annotationState.inlineTranslationStatus {
        case .idle:
            return
        case .loading:
            drawInlineTranslationSpinner(in: selectionRect)
            return
        case .failed(let reason):
            message = reason.isEmpty ? "翻译失败" : "翻译失败：\(reason)"
        }

        let toolbar = SelectionToolbarPresentation.default
        let toolbarFrame = toolbar.toolbarFrame(for: selectionRect, visibleBounds: bounds)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let text = message as NSString
        let textSize = text.size(withAttributes: attributes)
        let paddingX: CGFloat = 10
        let paddingY: CGFloat = 5
        let gap: CGFloat = 7
        let leadingIndicatorWidth: CGFloat = 0
        let maxWidth = max(120, min(bounds.width - 16, toolbarFrame.width))
        let boxWidth = min(textSize.width + paddingX * 2 + leadingIndicatorWidth, maxWidth)
        let boxHeight = textSize.height + paddingY * 2
        let preferredY = toolbarFrame.maxY + gap
        let fallbackY = toolbarFrame.minY - gap - boxHeight
        let boxY = preferredY + boxHeight <= bounds.maxY ? preferredY : max(bounds.minY + 8, fallbackY)
        let boxX = min(
            max(toolbarFrame.midX - boxWidth / 2, bounds.minX + 8),
            bounds.maxX - boxWidth - 8
        )
        let boxRect = CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)

        NSGraphicsContext.saveGraphicsState()
        let path = NSBezierPath(roundedRect: boxRect, xRadius: 8, yRadius: 8)
        NSColor.systemRed.withAlphaComponent(0.88).setFill()
        path.fill()
        let textRect = CGRect(
            x: boxRect.minX + paddingX + leadingIndicatorWidth,
            y: boxRect.midY - textSize.height / 2,
            width: min(textSize.width, boxWidth - paddingX * 2 - leadingIndicatorWidth),
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawInlineTranslationSpinner(in selectionRect: CGRect) {
        let visibleSelectionRect = selectionRect.intersection(bounds)
        guard visibleSelectionRect.width > 0, visibleSelectionRect.height > 0 else {
            return
        }

        let center = CGPoint(x: visibleSelectionRect.midX, y: visibleSelectionRect.midY)
        let backdropWidth: CGFloat = 72
        let backdropHeight: CGFloat = 74
        let backdropRect = CGRect(
            x: center.x - backdropWidth / 2,
            y: center.y - backdropHeight / 2,
            width: backdropWidth,
            height: backdropHeight
        )
        NSGraphicsContext.saveGraphicsState()
        let backdrop = NSBezierPath(roundedRect: backdropRect, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.42).setFill()
        backdrop.fill()

        let spinnerCenter = CGPoint(x: center.x, y: center.y + 10)
        let spokeCount = 12
        let innerRadius: CGFloat = 7
        let outerRadius: CGFloat = 15
        for index in 0..<spokeCount {
            let rotatedIndex = (index + loadingSpinnerPhase) % spokeCount
            let alpha = 0.18 + CGFloat(rotatedIndex) / CGFloat(spokeCount - 1) * 0.74
            let angle = CGFloat(index) / CGFloat(spokeCount) * CGFloat.pi * 2
            let start = CGPoint(
                x: spinnerCenter.x + cos(angle) * innerRadius,
                y: spinnerCenter.y + sin(angle) * innerRadius
            )
            let end = CGPoint(
                x: spinnerCenter.x + cos(angle) * outerRadius,
                y: spinnerCenter.y + sin(angle) * outerRadius
            )
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = 2.4
            path.lineCapStyle = .round
            NSColor.white.withAlphaComponent(alpha).setStroke()
            path.stroke()
        }

        let text = "翻译中" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94)
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(
                x: center.x - textSize.width / 2,
                y: center.y - 24
            ),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func updateLoadingSpinnerTimer() {
        if annotationState.inlineTranslationStatus == .loading {
            guard loadingSpinnerTask == nil else { return }
            loadingSpinnerTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 55_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.loadingSpinnerPhase = (self.loadingSpinnerPhase + 1) % 12
                    self.needsDisplay = true
                }
            }
        } else {
            loadingSpinnerTask?.cancel()
            loadingSpinnerTask = nil
            loadingSpinnerPhase = 0
        }
    }

    /// 在悬停的 toolbar item 上方/下方绘制 tooltip 气泡。
    /// 与 popover 的方向策略一致：优先上方，空间不足则下方。
    private func drawToolbarTooltipIfNeeded() {
        guard let role = hoveredToolbarRole,
              let toolbarFrame = toolbarFrame(),
              let item = SelectionToolbarPresentation.default.items.first(where: { $0.role == role }),
              let itemIndex = SelectionToolbarPresentation.default.items.firstIndex(where: { $0.role == role }) else {
            return
        }
        let toolbar = SelectionToolbarPresentation.default
        let itemOriginX = toolbarFrame.minX + toolbar.contentPadding
            + CGFloat(itemIndex) * (toolbar.itemSize + toolbar.itemSpacing)
        let itemRect = CGRect(
            x: itemOriginX,
            y: toolbarFrame.minY + toolbar.contentPadding,
            width: toolbar.itemSize,
            height: toolbar.itemSize
        )

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = item.tooltip as NSString
        let textSize = text.size(withAttributes: attributes)
        let paddingX: CGFloat = 8
        let paddingY: CGFloat = 4
        let gapFromItem: CGFloat = 6
        let boxWidth = textSize.width + paddingX * 2
        let boxHeight = textSize.height + paddingY * 2

        // 优先上方，空间不足则下方。
        let aboveY = itemRect.maxY + gapFromItem
        let belowY = itemRect.minY - gapFromItem - boxHeight
        let boxY: CGFloat
        if aboveY + boxHeight <= bounds.maxY {
            boxY = aboveY
        } else if belowY >= bounds.minY {
            boxY = belowY
        } else {
            boxY = aboveY
        }
        let boxX = min(
            max(itemRect.midX - boxWidth / 2, bounds.minX + 4),
            bounds.maxX - boxWidth - 4
        )
        let boxRect = CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)

        NSGraphicsContext.saveGraphicsState()
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.78).setFill()
        boxPath.fill()
        let textRect = CGRect(
            x: boxRect.midX - textSize.width / 2,
            y: boxRect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Popover

    /// Popover 选项的候选数组。与 controller 的 cycleAnnotation* 保持一致。
    private static let popoverColors: [ScreenshotAnnotationColor] = [.voxGreen, .red, .white, .black]
    private static let popoverLineWidths: [CGFloat] = [6, 8, 10]
    private static let popoverFontSizes: [CGFloat] = [14, 24, 32]
    /// 与 popoverFontSizes 对应的显示文字：小 / 中 / 大。
    private static let popoverFontSizeLabels: [String] = ["小", "中", "大"]

    private func popoverFrame(role: SelectionToolbarRole, toolbarFrame: CGRect) -> CGRect? {
        guard let itemIndex = SelectionToolbarPresentation.default.items.firstIndex(where: { $0.role == role }) else {
            return nil
        }
        let toolbar = SelectionToolbarPresentation.default
        let itemOriginX = toolbarFrame.minX + toolbar.contentPadding
            + CGFloat(itemIndex) * (toolbar.itemSize + toolbar.itemSpacing)
        let itemCenterX = itemOriginX + toolbar.itemSize / 2

        let optionCount: Int
        switch role {
        case .color: optionCount = Self.popoverColors.count
        case .lineWidth: optionCount = Self.popoverLineWidths.count
        case .fontSize: optionCount = Self.popoverFontSizes.count
        default: return nil
        }

        let optionSize: CGFloat = 28
        let optionSpacing: CGFloat = 8
        let popoverPadding: CGFloat = 8
        let gapFromToolbar: CGFloat = 6
        let popoverWidth = popoverPadding * 2 + CGFloat(optionCount) * optionSize
            + CGFloat(max(0, optionCount - 1)) * optionSpacing
        let popoverHeight = popoverPadding * 2 + optionSize

        let popoverX = min(
            max(itemCenterX - popoverWidth / 2, bounds.minX + popoverPadding),
            bounds.maxX - popoverWidth - popoverPadding
        )
        let aboveY = toolbarFrame.maxY + gapFromToolbar
        let belowY = toolbarFrame.minY - gapFromToolbar - popoverHeight
        let popoverY: CGFloat
        if aboveY + popoverHeight <= bounds.maxY {
            popoverY = aboveY
        } else if belowY >= bounds.minY {
            popoverY = belowY
        } else {
            popoverY = aboveY
        }
        return CGRect(x: popoverX, y: popoverY, width: popoverWidth, height: popoverHeight)
    }

    private func drawPopover(role: SelectionToolbarRole, frame: CGRect) {
        let path = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)
        NSColor.white.withAlphaComponent(0.96).setFill()
        path.fill()
        NSColor.systemGreen.withAlphaComponent(0.32).setStroke()
        path.lineWidth = 1
        path.stroke()

        let optionSize: CGFloat = 28
        let optionSpacing: CGFloat = 8
        let padding: CGFloat = 8
        let options: Int
        switch role {
        case .color: options = Self.popoverColors.count
        case .lineWidth: options = Self.popoverLineWidths.count
        case .fontSize: options = Self.popoverFontSizes.count
        default: return
        }
        let totalWidth = CGFloat(options) * optionSize + CGFloat(max(0, options - 1)) * optionSpacing
        let startX = frame.midX - totalWidth / 2
        let optionY = frame.minY + padding

        for index in 0..<options {
            let optionRect = CGRect(
                x: startX + CGFloat(index) * (optionSize + optionSpacing),
                y: optionY,
                width: optionSize,
                height: optionSize
            )
            drawPopoverOption(role: role, index: index, in: optionRect)
        }
    }

    private func drawPopoverOption(role: SelectionToolbarRole, index: Int, in rect: CGRect) {
        let isSelected: Bool
        switch role {
        case .color:
            let color = Self.popoverColors[index]
            isSelected = annotationState.currentStyle.color == color
            NSGraphicsContext.saveGraphicsState()
            color.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
            if isSelected {
                NSColor.systemGreen.setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
                ring.lineWidth = 2
                ring.stroke()
            } else {
                NSColor.black.withAlphaComponent(0.18).setStroke()
                let border = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
                border.lineWidth = 1
                border.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            return
        case .lineWidth:
            let width = Self.popoverLineWidths[index]
            isSelected = abs(annotationState.currentStyle.lineWidth - width) < 0.01
            drawPopoverOptionBackground(rect: rect, isSelected: isSelected)
            let dotSize = 8 + (width - 6) * 2
            let dotRect = CGRect(
                x: rect.midX - dotSize / 2,
                y: rect.midY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            NSGraphicsContext.saveGraphicsState()
            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            NSGraphicsContext.restoreGraphicsState()
            return
        case .fontSize:
            let size = Self.popoverFontSizes[index]
            isSelected = abs(annotationState.currentFontSize - size) < 0.01
            drawPopoverOptionBackground(rect: rect, isSelected: isSelected)
            drawCenteredText(Self.popoverFontSizeLabels[index], in: rect)
            return
        default:
            return
        }
    }

    private func drawPopoverOptionBackground(rect: CGRect, isSelected: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if isSelected {
            NSColor.systemGreen.withAlphaComponent(0.28).setFill()
        } else {
            NSColor.black.withAlphaComponent(0.04).setFill()
        }
        path.fill()
    }

    /// 返回 popover 命中的选项 index（0-based），未命中返回 nil。
    private func popoverOption(at point: CGPoint) -> (SelectionToolbarRole, Int)? {
        guard let popoverRole = annotationState.popoverRole,
              let toolbarFrame = toolbarFrame(),
              let popoverFrame = popoverFrame(role: popoverRole, toolbarFrame: toolbarFrame),
              popoverFrame.contains(point) else {
            return nil
        }
        let optionSize: CGFloat = 28
        let optionSpacing: CGFloat = 8
        let padding: CGFloat = 8
        let options: Int
        switch popoverRole {
        case .color: options = Self.popoverColors.count
        case .lineWidth: options = Self.popoverLineWidths.count
        case .fontSize: options = Self.popoverFontSizes.count
        default: return nil
        }
        let totalWidth = CGFloat(options) * optionSize + CGFloat(max(0, options - 1)) * optionSpacing
        let startX = popoverFrame.midX - totalWidth / 2
        let optionY = popoverFrame.minY + padding
        for index in 0..<options {
            let optionRect = CGRect(
                x: startX + CGFloat(index) * (optionSize + optionSpacing),
                y: optionY,
                width: optionSize,
                height: optionSize
            )
            if optionRect.contains(point) {
                return (popoverRole, index)
            }
        }
        return nil
    }

    private func popoverContains(_ point: CGPoint) -> Bool {
        guard let popoverRole = annotationState.popoverRole,
              let toolbarFrame = toolbarFrame(),
              let popoverFrame = popoverFrame(role: popoverRole, toolbarFrame: toolbarFrame) else {
            return false
        }
        return popoverFrame.contains(point)
    }

    private func drawToolbarIcon(_ item: SelectionToolbarItem, in rect: CGRect) {
        let itemPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        let isActiveTool = annotationState.activeRole == item.role
        let isPressed = pressedToolbarRole == item.role
        let fillColor: NSColor
        if isPressed {
            fillColor = item.role == .complete
                ? NSColor.systemGreen.withAlphaComponent(0.22)
                : item.role == .cancel
                ? NSColor.systemRed.withAlphaComponent(0.16)
                : NSColor.systemGreen.withAlphaComponent(0.28)
        } else if isActiveTool {
            fillColor = NSColor.systemGreen.withAlphaComponent(0.18)
        } else {
            fillColor = NSColor.black.withAlphaComponent(0.04)
        }
        fillColor.setFill()
        itemPath.fill()

        switch item.role {
        case .color:
            let colorSize: CGFloat = min(rect.width, rect.height) * 0.6
            let colorRect = CGRect(
                x: rect.midX - colorSize / 2,
                y: rect.midY - colorSize / 2,
                width: colorSize,
                height: colorSize
            )
            NSGraphicsContext.saveGraphicsState()
            annotationState.currentStyle.color.nsColor.setFill()
            NSBezierPath(ovalIn: colorRect).fill()
            let border = NSBezierPath(ovalIn: colorRect)
            border.lineWidth = 1.5
            NSColor.white.setStroke()
            border.stroke()
            NSGraphicsContext.restoreGraphicsState()
            return
        case .lineWidth:
            let lineWidth = annotationState.currentStyle.lineWidth
            let lineLength = rect.width * 0.7
            let lineRect = CGRect(
                x: rect.midX - lineLength / 2,
                y: rect.midY - lineWidth / 2,
                width: lineLength,
                height: lineWidth
            )
            NSGraphicsContext.saveGraphicsState()
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: lineRect, xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()
            NSGraphicsContext.restoreGraphicsState()
            return
        case .fontSize:
            // 字体大小只有 3 档：小 / 中 / 大，与 popoverFontSizes 对应。
            let sizes = Self.popoverFontSizes
            let labels = Self.popoverFontSizeLabels
            let fontSize = annotationState.currentFontSize
            let label: String
            if let idx = sizes.firstIndex(where: { abs($0 - fontSize) < 0.01 }) {
                label = labels[idx]
            } else {
                label = labels[0]
            }
            drawCenteredText(label, in: rect)
            return
        case .translate:
            drawCenteredText("译", in: rect)
            return
        default:
            break
        }

        let image = NSImage(systemSymbolName: item.systemImageName, accessibilityDescription: item.tooltip)
        image?.isTemplate = true
        let iconSize = CGSize(width: 16, height: 16)
        let iconRect = CGRect(
            x: rect.midX - iconSize.width / 2,
            y: rect.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        NSGraphicsContext.saveGraphicsState()
        NSColor.labelColor.set()
        image?.draw(in: iconRect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCenteredText(_ text: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = text as NSString
        let size = attributed.size(withAttributes: attributes)
        let textRect = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        NSGraphicsContext.saveGraphicsState()
        attributed.draw(in: textRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func toolbarRole(at point: CGPoint) -> SelectionToolbarRole? {
        guard let frame = toolbarFrame(),
              frame.contains(point) else {
            return nil
        }
        let toolbar = SelectionToolbarPresentation.default
        var itemOrigin = CGPoint(
            x: frame.minX + toolbar.contentPadding,
            y: frame.minY + toolbar.contentPadding
        )
        for item in toolbar.items {
            let itemRect = CGRect(origin: itemOrigin, size: CGSize(width: toolbar.itemSize, height: toolbar.itemSize))
            if itemRect.contains(point) {
                return item.role
            }
            itemOrigin.x += toolbar.itemSize + toolbar.itemSpacing
        }
        return nil
    }

    private func toolbarContains(_ point: CGPoint) -> Bool {
        toolbarFrame()?.contains(point) == true
    }

    private func toolbarFrame() -> CGRect? {
        guard let selectionState else {
            return nil
        }
        let selectionRect = SelectionOverlayDisplayGeometry.localSelectionRect(
            for: selectionState,
            on: configuration.display
        )
        guard SelectionOverlayDisplayGeometry.shouldDrawSelectionChrome(
            localSelectionRect: selectionRect,
            visibleBounds: bounds
        ) else {
            return nil
        }
        let toolbar = SelectionToolbarPresentation.default
        return toolbar.toolbarFrame(for: selectionRect, visibleBounds: bounds)
    }
}

private final class InlineAnnotationTextField: NSTextField {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var didFinish = false

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            commitIfNeeded()
        case 53:
            cancelIfNeeded()
        default:
            super.keyDown(with: event)
        }
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        commitIfNeeded()
    }

    private func commitIfNeeded() {
        guard !didFinish else {
            return
        }
        didFinish = true
        onCommit?(stringValue)
    }

    private func cancelIfNeeded() {
        guard !didFinish else {
            return
        }
        didFinish = true
        onCancel?()
    }
}
