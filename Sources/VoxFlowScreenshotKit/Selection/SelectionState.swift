import CoreGraphics

public enum SelectionResizeHandle: CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
}

public struct SelectionState: Equatable, Sendable {
    public let displayFrame: CGRect
    public let displayScale: CGFloat
    public let startPoint: CGPoint
    public let currentPoint: CGPoint
    public let minimumSizePoints: CGFloat

    public init(
        displayFrame: CGRect,
        displayScale: CGFloat,
        startPoint: CGPoint,
        currentPoint: CGPoint,
        minimumSizePoints: CGFloat = 8
    ) {
        self.displayFrame = displayFrame
        self.displayScale = displayScale
        self.startPoint = startPoint
        self.currentPoint = currentPoint
        self.minimumSizePoints = minimumSizePoints
    }

    public var normalizedRect: CGRect {
        Self.normalizedRect(from: startPoint, to: currentPoint)
    }

    public var pixelRect: CGRect {
        pixelRect(in: displayFrame, scale: displayScale)
    }

    public var isValidSelection: Bool {
        normalizedRect.width >= minimumSizePoints &&
            normalizedRect.height >= minimumSizePoints
    }

    public func movingSelection(by offset: CGSize) -> SelectionState {
        SelectionState(
            displayFrame: displayFrame,
            displayScale: displayScale,
            startPoint: CGPoint(
                x: startPoint.x + offset.width,
                y: startPoint.y + offset.height
            ),
            currentPoint: CGPoint(
                x: currentPoint.x + offset.width,
                y: currentPoint.y + offset.height
            ),
            minimumSizePoints: minimumSizePoints
        )
    }

    public func pixelRect(in frame: CGRect, scale: CGFloat) -> CGRect {
        let rect = normalizedRect
        let scale = max(scale, 1)
        return CGRect(
            x: (rect.minX - frame.minX) * scale,
            y: (rect.minY - frame.minY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    public func resizingSelection(
        handle: SelectionResizeHandle,
        to point: CGPoint
    ) -> SelectionState {
        var minX = normalizedRect.minX
        var minY = normalizedRect.minY
        var maxX = normalizedRect.maxX
        var maxY = normalizedRect.maxY

        switch handle {
        case .topLeft:
            minX = point.x
            minY = point.y
        case .top:
            minY = point.y
        case .topRight:
            maxX = point.x
            minY = point.y
        case .left:
            minX = point.x
        case .right:
            maxX = point.x
        case .bottomLeft:
            minX = point.x
            maxY = point.y
        case .bottom:
            maxY = point.y
        case .bottomRight:
            maxX = point.x
            maxY = point.y
        }

        return SelectionState(
            displayFrame: displayFrame,
            displayScale: displayScale,
            startPoint: CGPoint(x: minX, y: minY),
            currentPoint: CGPoint(x: maxX, y: maxY),
            minimumSizePoints: minimumSizePoints
        )
    }

    public static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
