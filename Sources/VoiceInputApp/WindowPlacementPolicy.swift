import AppKit

enum WindowPlacementPolicy {
    static func centeredFrame(
        windowSize: NSSize,
        visibleFrame: NSRect
    ) -> NSRect {
        let fittedSize = NSSize(
            width: min(windowSize.width, visibleFrame.width),
            height: min(windowSize.height, visibleFrame.height)
        )
        return NSRect(
            x: visibleFrame.midX - fittedSize.width / 2,
            y: visibleFrame.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    static func isFullyVisible(_ frame: NSRect, in visibleFrames: [NSRect]) -> Bool {
        visibleFrames.contains { visibleFrame in
            NSEqualRects(NSIntersectionRect(frame, visibleFrame), frame)
        }
    }

    static func preferredVisibleFrame(
        for windowFrame: NSRect,
        screens: [NSRect]
    ) -> NSRect? {
        screens.max { lhs, rhs in
            intersectionArea(windowFrame, lhs) < intersectionArea(windowFrame, rhs)
        }
    }

    @MainActor
    static func placeOnVisibleScreenIfNeeded(_ window: NSWindow) {
        let screens = NSScreen.screens
        let visibleFrames = screens.map(\.visibleFrame)
        guard !isFullyVisible(window.frame, in: visibleFrames) else { return }
        let visibleFrame = preferredVisibleFrame(
            for: window.frame,
            screens: visibleFrames
        ) ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return }
        window.setFrame(
            centeredFrame(windowSize: window.frame.size, visibleFrame: visibleFrame),
            display: true,
            animate: false
        )
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = NSIntersectionRect(lhs, rhs)
        return max(0, intersection.width) * max(0, intersection.height)
    }
}
