import CoreGraphics

public struct SelectionOverlayPresentation: Equatable, Sendable {
    public let selectionRect: CGRect
    public let sizeReadout: String
    public let resizeHandleRects: [CGRect]
    public let outsideDimmingAlpha: CGFloat

    public init(
        state: SelectionState,
        handleSize: CGFloat = 8,
        outsideDimmingAlpha: CGFloat = 0.42
    ) {
        let rect = state.normalizedRect
        self.selectionRect = rect
        self.sizeReadout = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        self.resizeHandleRects = Self.handles(for: rect, size: handleSize)
        self.outsideDimmingAlpha = outsideDimmingAlpha
    }

    private static func handles(for rect: CGRect, size: CGFloat) -> [CGRect] {
        let half = size / 2
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        return points.map { point in
            CGRect(
                x: point.x - half,
                y: point.y - half,
                width: size,
                height: size
            )
        }
    }
}
