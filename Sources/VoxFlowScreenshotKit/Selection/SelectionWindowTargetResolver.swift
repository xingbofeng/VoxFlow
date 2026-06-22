import CoreGraphics
import Foundation

// Window targeting adapted from tokuhirom/ShotShot (MIT), commit
// c600d978c3ba1cce72c26e8af19e3bca155d0e15. VoxFlow keeps this as a pure
// resolver so multi-display and occlusion rules can be tested without UI.

struct SelectionWindowInfo: Equatable, Sendable {
    let id: CGWindowID
    let frame: CGRect
    let name: String?
    let ownerName: String?
    let layer: Int

    init(
        id: CGWindowID,
        frame: CGRect,
        name: String?,
        ownerName: String?,
        layer: Int
    ) {
        self.id = id
        self.frame = frame
        self.name = name
        self.ownerName = ownerName
        self.layer = layer
    }
}

struct SelectionWindowTarget: Equatable, Sendable {
    let id: CGWindowID
    let frame: CGRect
    let name: String?
    let ownerName: String?
}

struct SelectionWindowTargetResolver: Sendable {
    private let screenFrame: CGRect
    private let windowsInFrontToBackOrder: [SelectionWindowInfo]
    private let ownWindowID: CGWindowID

    static func live(
        screenFrame: CGRect,
        ownWindowID: CGWindowID
    ) -> SelectionWindowTargetResolver {
        SelectionWindowTargetResolver(
            screenFrame: screenFrame,
            windowsInFrontToBackOrder: loadOnScreenWindows(),
            ownWindowID: ownWindowID
        )
    }

    init(
        screenFrame: CGRect,
        windowsInFrontToBackOrder: [SelectionWindowInfo],
        ownWindowID: CGWindowID
    ) {
        self.screenFrame = screenFrame
        self.windowsInFrontToBackOrder = windowsInFrontToBackOrder
        self.ownWindowID = ownWindowID
    }

    func targetWindow(at point: CGPoint) -> SelectionWindowTarget? {
        guard let topmost = windowsInFrontToBackOrder.first(where: { window in
            window.id != ownWindowID &&
                window.layer == 0 &&
                window.frame.contains(point)
        }) else {
            return nil
        }

        guard isCaptureWorthy(topmost) else {
            return nil
        }

        return SelectionWindowTarget(
            id: topmost.id,
            frame: topmost.frame,
            name: topmost.name,
            ownerName: topmost.ownerName
        )
    }

    private func isCaptureWorthy(_ window: SelectionWindowInfo) -> Bool {
        guard window.frame.width > 50,
              window.frame.height > 50 else {
            return false
        }

        if window.ownerName == "Dock" || window.ownerName == "WindowServer" {
            return false
        }

        if window.ownerName == "Finder",
           window.name?.isEmpty ?? true {
            return false
        }

        return true
    }

    private static func loadOnScreenWindows() -> [SelectionWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { info in
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let x = numeric(boundsDict["X"]),
                  let y = numeric(boundsDict["Y"]),
                  let width = numeric(boundsDict["Width"]),
                  let height = numeric(boundsDict["Height"]) else {
                return nil
            }

            return SelectionWindowInfo(
                id: windowID,
                frame: CGRect(x: x, y: y, width: width, height: height),
                name: info[kCGWindowName as String] as? String,
                ownerName: info[kCGWindowOwnerName as String] as? String,
                layer: info[kCGWindowLayer as String] as? Int ?? 0
            )
        }
    }

    private static func numeric(_ value: Any?) -> CGFloat? {
        switch value {
        case let number as NSNumber:
            return CGFloat(number.doubleValue)
        case let value as CGFloat:
            return value
        case let value as Double:
            return CGFloat(value)
        case let value as Int:
            return CGFloat(value)
        default:
            return nil
        }
    }
}
