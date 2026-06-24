import CoreGraphics

enum ScrollingScreenshotPanelGeometry {
    static func localRect(for selectionRect: CGRect, display: ScreenshotDisplay) -> CGRect {
        selectionRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }

    static func screenRect(forLocalRect localRect: CGRect, display: ScreenshotDisplay) -> CGRect {
        CGRect(
            x: display.overlayFrame.minX + localRect.minX,
            y: display.overlayFrame.maxY - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        )
    }
}
