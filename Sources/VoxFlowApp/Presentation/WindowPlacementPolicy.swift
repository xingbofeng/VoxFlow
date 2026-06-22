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

    static func interactionVisibleFrame(
        focusedWindowFrame: NSRect?,
        mouseLocation: NSPoint?,
        screenFrames: [NSRect],
        visibleFrames: [NSRect]
    ) -> NSRect? {
        let screenPairs = Array(zip(screenFrames, visibleFrames))
        guard !screenPairs.isEmpty else { return nil }

        if let focusedWindowFrame,
           let focusedPair = screenPairs.max(by: {
               intersectionArea(focusedWindowFrame, $0.0) < intersectionArea(focusedWindowFrame, $1.0)
           }),
           intersectionArea(focusedWindowFrame, focusedPair.0) > 0 {
            return focusedPair.1
        }

        if let mouseLocation,
           let mousePair = screenPairs.first(where: { NSMouseInRect(mouseLocation, $0.0, false) }) {
            return mousePair.1
        }

        return nil
    }

    @MainActor
    static func interactionVisibleFrame() -> NSRect? {
        let screens = NSScreen.screens
        if let focusedWindowFrame = SystemFocusedWindowFrameProvider.focusedWindowFrame(),
           let visibleFrame = interactionVisibleFrame(
               focusedWindowFrame: focusedWindowFrame,
               mouseLocation: nil,
               screenFrames: screens.map { displayFrame(for: $0) ?? $0.frame },
               visibleFrames: screens.map(\.visibleFrame)
           ) {
            return visibleFrame
        }

        if let mouseScreen = screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            return mouseScreen.visibleFrame
        }

        return NSScreen.main?.visibleFrame
    }

    @MainActor
    static func centerOnMainScreen(_ window: NSWindow) {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            window.center()
            return
        }
        window.setFrame(
            centeredFrame(windowSize: window.frame.size, visibleFrame: visibleFrame),
            display: window.isVisible,
            animate: false
        )
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

    private static func displayFrame(for screen: NSScreen) -> NSRect? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID else {
            return nil
        }
        return CGDisplayBounds(displayID)
    }
}

private enum SystemFocusedWindowFrameProvider {
    static func focusedWindowFrame() -> NSRect? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedWindow = axWindowAttribute(appElement, kAXFocusedWindowAttribute) else {
            return nil
        }
        guard let positionValue = axValueAttribute(focusedWindow, kAXPositionAttribute),
              let sizeValue = axValueAttribute(focusedWindow, kAXSizeAttribute),
              AXValueGetType(positionValue) == .cgPoint,
              AXValueGetType(sizeValue) == .cgSize else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return NSRect(origin: origin, size: size)
    }

    private static func axWindowAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func axValueAttribute(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return (value as! AXValue)
    }
}
