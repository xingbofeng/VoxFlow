import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
public protocol ScrollingScreenshotAutoScrolling: AnyObject {
    var hasAccessibilityPermission: Bool { get }
    func requestAccessibilityPermissionPrompt()
    func postScrollTick(lines: Int32, at location: CGPoint)
}

public extension ScrollingScreenshotAutoScrolling {
    func requestAccessibilityPermissionPrompt() {}
}

@MainActor
public final class AppKitScrollingScreenshotAutoScroller: ScrollingScreenshotAutoScrolling {
    public init() {}

    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibilityPermissionPrompt() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func postScrollTick(lines: Int32, at location: CGPoint) {
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
        event.location = location
        event.post(tap: .cghidEventTap)
    }
}
