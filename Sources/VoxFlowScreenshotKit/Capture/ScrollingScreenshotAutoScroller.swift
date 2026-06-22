import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
public protocol ScrollingScreenshotAutoScrolling: AnyObject {
    var hasAccessibilityPermission: Bool { get }
    func postScrollTick(lines: Int32)
}

@MainActor
public final class AppKitScrollingScreenshotAutoScroller: ScrollingScreenshotAutoScrolling {
    public init() {}

    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    public func postScrollTick(lines: Int32) {
        guard hasAccessibilityPermission,
              let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: -lines,
                wheel2: 0,
                wheel3: 0
              ) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
