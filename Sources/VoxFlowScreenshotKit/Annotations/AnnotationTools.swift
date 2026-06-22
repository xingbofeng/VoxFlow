import CoreGraphics
import Foundation

// Annotation tool state machine adapted from sadopc/ScreenCapture (MIT), commit
// 081cb96b5c9f4bf72ace9187205009c92ab15f8c. VoxFlow adds marker and mosaic tools.

@MainActor
public protocol ScreenshotAnnotationTool {
    var kind: AnnotationElementKind { get }
    var isActive: Bool { get }
    var style: ScreenshotAnnotationStyle { get set }
    var textStyle: ScreenshotAnnotationTextStyle { get set }
    var currentAnnotation: AnnotationElement? { get }

    mutating func beginDrawing(at point: CGPoint)
    mutating func continueDrawing(to point: CGPoint)
    mutating func endDrawing(at point: CGPoint) -> AnnotationElement?
    mutating func cancelDrawing()
}

public extension ScreenshotAnnotationTool {
    var textStyle: ScreenshotAnnotationTextStyle {
        get { .default }
        set {}
    }
}

public struct DrawingState: Equatable, Sendable {
    public var startPoint: CGPoint
    public var points: [CGPoint]
    public var isDrawing: Bool

    public init(startPoint: CGPoint = .zero) {
        self.startPoint = startPoint
        self.points = [startPoint]
        self.isDrawing = false
    }

    public mutating func reset() {
        startPoint = .zero
        points = []
        isDrawing = false
    }
}

@MainActor
public struct RectangleAnnotationTool: ScreenshotAnnotationTool {
    public let kind: AnnotationElementKind = .rectangle
    public var style: ScreenshotAnnotationStyle
    public var textStyle: ScreenshotAnnotationTextStyle = .default
    private var drawingState = DrawingState()

    public init(style: ScreenshotAnnotationStyle = .default) {
        self.style = style
    }

    public var isActive: Bool { drawingState.isDrawing }

    public var currentAnnotation: AnnotationElement? {
        guard isActive else { return nil }
        let rect = currentRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        return .rectangle(RectangleAnnotationElement(rect: rect, style: style))
    }

    public mutating func beginDrawing(at point: CGPoint) {
        drawingState = DrawingState(startPoint: point)
        drawingState.isDrawing = true
    }

    public mutating func continueDrawing(to point: CGPoint) {
        guard isActive else { return }
        drawingState.setCurrentPoint(point)
    }

    public mutating func endDrawing(at point: CGPoint) -> AnnotationElement? {
        guard isActive else { return nil }
        continueDrawing(to: point)
        let rect = currentRect
        drawingState.reset()
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        return .rectangle(RectangleAnnotationElement(rect: rect, style: style))
    }

    public mutating func cancelDrawing() {
        drawingState.reset()
    }

    private var currentRect: CGRect {
        drawingState.normalizedRectToLastPoint
    }
}

@MainActor
public struct EllipseAnnotationTool: ScreenshotAnnotationTool {
    public let kind: AnnotationElementKind = .ellipse
    public var style: ScreenshotAnnotationStyle
    public var textStyle: ScreenshotAnnotationTextStyle = .default
    private var drawingState = DrawingState()

    public init(style: ScreenshotAnnotationStyle = .default) {
        self.style = style
    }

    public var isActive: Bool { drawingState.isDrawing }

    public var currentAnnotation: AnnotationElement? {
        guard isActive else { return nil }
        let rect = drawingState.normalizedRectToLastPoint
        guard rect.width > 0, rect.height > 0 else { return nil }
        return .ellipse(EllipseAnnotationElement(rect: rect, style: style))
    }

    public mutating func beginDrawing(at point: CGPoint) {
        drawingState = DrawingState(startPoint: point)
        drawingState.isDrawing = true
    }

    public mutating func continueDrawing(to point: CGPoint) {
        guard isActive else { return }
        drawingState.setCurrentPoint(point)
    }

    public mutating func endDrawing(at point: CGPoint) -> AnnotationElement? {
        guard isActive else { return nil }
        continueDrawing(to: point)
        let rect = drawingState.normalizedRectToLastPoint
        drawingState.reset()
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        return .ellipse(EllipseAnnotationElement(rect: rect, style: style))
    }

    public mutating func cancelDrawing() {
        drawingState.reset()
    }
}

@MainActor
public struct MosaicAnnotationTool: ScreenshotAnnotationTool {
    public let kind: AnnotationElementKind = .mosaic
    public var style: ScreenshotAnnotationStyle = .default
    public var textStyle: ScreenshotAnnotationTextStyle = .default
    public var brushSize: CGFloat
    public var blockSize: CGFloat
    public var minimumPointDistance: CGFloat
    private var drawingState = DrawingState()

    public init(brushSize: CGFloat = 18, blockSize: CGFloat = 8, minimumPointDistance: CGFloat = 2) {
        self.brushSize = brushSize
        self.blockSize = blockSize
        self.minimumPointDistance = minimumPointDistance
    }

    public var isActive: Bool { drawingState.isDrawing }

    public var currentAnnotation: AnnotationElement? {
        guard isActive else { return nil }
        return .mosaic(MosaicAnnotationElement(
            points: drawingState.points,
            brushSize: brushSize,
            blockSize: blockSize
        ))
    }

    public mutating func beginDrawing(at point: CGPoint) {
        drawingState = DrawingState(startPoint: point)
        drawingState.isDrawing = true
    }

    public mutating func continueDrawing(to point: CGPoint) {
        guard isActive else { return }
        if let lastPoint = drawingState.points.last,
           hypot(point.x - lastPoint.x, point.y - lastPoint.y) < minimumPointDistance {
            return
        }
        drawingState.points.append(point)
    }

    public mutating func endDrawing(at point: CGPoint) -> AnnotationElement? {
        guard isActive else { return nil }
        continueDrawing(to: point)
        let points = drawingState.points
        drawingState.reset()
        guard !points.isEmpty else { return nil }
        return .mosaic(MosaicAnnotationElement(
            points: points,
            brushSize: brushSize,
            blockSize: blockSize
        ))
    }

    public mutating func cancelDrawing() {
        drawingState.reset()
    }
}

@MainActor
public struct ArrowAnnotationTool: ScreenshotAnnotationTool {
    public let kind: AnnotationElementKind = .arrow
    public var style: ScreenshotAnnotationStyle
    public var textStyle: ScreenshotAnnotationTextStyle = .default
    private var drawingState = DrawingState()

    public init(style: ScreenshotAnnotationStyle = .default) {
        self.style = style
    }

    public var isActive: Bool { drawingState.isDrawing }

    public var currentAnnotation: AnnotationElement? {
        guard isActive, let end = drawingState.points.last, drawingState.points.count >= 2 else {
            return nil
        }
        return .arrow(ArrowAnnotationElement(startPoint: drawingState.startPoint, endPoint: end, style: style))
    }

    public mutating func beginDrawing(at point: CGPoint) {
        drawingState = DrawingState(startPoint: point)
        drawingState.isDrawing = true
    }

    public mutating func continueDrawing(to point: CGPoint) {
        guard isActive else { return }
        drawingState.setCurrentPoint(point)
    }

    public mutating func endDrawing(at point: CGPoint) -> AnnotationElement? {
        guard isActive else { return nil }
        continueDrawing(to: point)
        let start = drawingState.startPoint
        drawingState.reset()
        guard hypot(point.x - start.x, point.y - start.y) >= 5 else { return nil }
        return .arrow(ArrowAnnotationElement(startPoint: start, endPoint: point, style: style))
    }

    public mutating func cancelDrawing() {
        drawingState.reset()
    }
}

@MainActor
public struct FreehandAnnotationTool: ScreenshotAnnotationTool {
    public let kind: AnnotationElementKind = .pen
    public var style: ScreenshotAnnotationStyle
    public var textStyle: ScreenshotAnnotationTextStyle = .default
    public var minimumPointDistance: CGFloat
    private var drawingState = DrawingState()

    public init(style: ScreenshotAnnotationStyle = .default, minimumPointDistance: CGFloat = 2) {
        self.style = style
        self.minimumPointDistance = minimumPointDistance
    }

    public var isActive: Bool { drawingState.isDrawing }

    public var currentAnnotation: AnnotationElement? {
        guard isActive, drawingState.points.count >= 2 else { return nil }
        return .pen(FreehandAnnotationElement(points: drawingState.points, style: style))
    }

    public mutating func beginDrawing(at point: CGPoint) {
        drawingState = DrawingState(startPoint: point)
        drawingState.isDrawing = true
    }

    public mutating func continueDrawing(to point: CGPoint) {
        guard isActive else { return }
        if let lastPoint = drawingState.points.last,
           hypot(point.x - lastPoint.x, point.y - lastPoint.y) < minimumPointDistance {
            return
        }
        drawingState.points.append(point)
    }

    public mutating func endDrawing(at point: CGPoint) -> AnnotationElement? {
        guard isActive else { return nil }
        continueDrawing(to: point)
        let points = drawingState.points
        drawingState.reset()
        guard points.count >= 2 else { return nil }
        return .pen(FreehandAnnotationElement(points: points, style: style))
    }

    public mutating func cancelDrawing() {
        drawingState.reset()
    }
}

@MainActor
public struct DotMarkerAnnotationTool: ScreenshotAnnotationTool {
    public let kind: AnnotationElementKind = .dotMarker
    public var style: ScreenshotAnnotationStyle
    public var textStyle: ScreenshotAnnotationTextStyle = .default
    public var radius: CGFloat
    private var point: CGPoint?

    public init(style: ScreenshotAnnotationStyle = .default, radius: CGFloat = 6) {
        self.style = style
        self.radius = radius
    }

    public var isActive: Bool { point != nil }

    public var currentAnnotation: AnnotationElement? {
        guard let point else { return nil }
        return .dotMarker(DotMarkerAnnotationElement(center: point, radius: radius, style: style))
    }

    public mutating func beginDrawing(at point: CGPoint) {
        self.point = point
    }

    public mutating func continueDrawing(to point: CGPoint) {
        self.point = point
    }

    public mutating func endDrawing(at point: CGPoint) -> AnnotationElement? {
        self.point = nil
        return .dotMarker(DotMarkerAnnotationElement(center: point, radius: radius, style: style))
    }

    public mutating func cancelDrawing() {
        point = nil
    }
}

@MainActor
public struct NumberedMarkerAnnotationTool: ScreenshotAnnotationTool {
    public let kind: AnnotationElementKind = .numberedMarker
    public var style: ScreenshotAnnotationStyle
    public var textStyle: ScreenshotAnnotationTextStyle = .default
    public var nextNumber: Int
    public var radius: CGFloat
    private var point: CGPoint?

    public init(nextNumber: Int = 1, style: ScreenshotAnnotationStyle = .default, radius: CGFloat = 9) {
        self.nextNumber = nextNumber
        self.style = style
        self.radius = radius
    }

    public var isActive: Bool { point != nil }

    public var currentAnnotation: AnnotationElement? {
        guard let point else { return nil }
        return .numberedMarker(NumberedMarkerAnnotationElement(center: point, number: nextNumber, radius: radius, style: style))
    }

    public mutating func beginDrawing(at point: CGPoint) {
        self.point = point
    }

    public mutating func continueDrawing(to point: CGPoint) {
        self.point = point
    }

    public mutating func endDrawing(at point: CGPoint) -> AnnotationElement? {
        self.point = nil
        let element = NumberedMarkerAnnotationElement(center: point, number: nextNumber, radius: radius, style: style)
        nextNumber += 1
        return .numberedMarker(element)
    }

    public mutating func cancelDrawing() {
        point = nil
    }
}

@MainActor
public struct TextAnnotationTool: ScreenshotAnnotationTool {
    public let kind: AnnotationElementKind = .text
    public var style: ScreenshotAnnotationStyle = .default
    public var textStyle: ScreenshotAnnotationTextStyle
    public private(set) var placementPoint: CGPoint?
    public private(set) var currentText: String

    public init(textStyle: ScreenshotAnnotationTextStyle = .default) {
        self.textStyle = textStyle
        self.currentText = ""
    }

    public var isActive: Bool { placementPoint != nil }

    public var currentAnnotation: AnnotationElement? {
        guard let placementPoint, !currentText.isEmpty else { return nil }
        return .text(TextAnnotationElement(position: placementPoint, content: currentText, style: textStyle))
    }

    public mutating func beginDrawing(at point: CGPoint) {
        placementPoint = point
        currentText = ""
    }

    public mutating func continueDrawing(to point: CGPoint) {}

    public mutating func endDrawing(at point: CGPoint) -> AnnotationElement? {
        nil
    }

    public mutating func updateText(_ text: String) {
        currentText = text
    }

    public mutating func commitText() -> AnnotationElement? {
        guard let placementPoint,
              !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cancelDrawing()
            return nil
        }
        let element = AnnotationElement.text(
            TextAnnotationElement(position: placementPoint, content: currentText, style: textStyle)
        )
        cancelDrawing()
        return element
    }

    public mutating func cancelDrawing() {
        placementPoint = nil
        currentText = ""
    }
}

private extension DrawingState {
    mutating func setCurrentPoint(_ point: CGPoint) {
        if points.count > 1 {
            points[1] = point
        } else {
            points.append(point)
        }
    }

    var normalizedRectToLastPoint: CGRect {
        guard let endPoint = points.last else { return .zero }
        return CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }
}
