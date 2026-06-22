import CoreGraphics
import Foundation

public enum ScreenCaptureWindowExclusion {
    public static func currentProcessWindowIDs() -> [CGWindowID] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windowIDs(from: windowList, ownerPID: getpid())
    }

    static func windowIDs(
        from windowList: [[String: Any]],
        ownerPID: pid_t
    ) -> [CGWindowID] {
        windowList.compactMap { info in
            guard let windowID = windowID(from: info[kCGWindowNumber as String]),
                  let windowOwnerPID = pid(from: info[kCGWindowOwnerPID as String]),
                  windowOwnerPID == ownerPID else {
                return nil
            }
            return windowID
        }
    }

    private static func windowID(from value: Any?) -> CGWindowID? {
        switch value {
        case let id as CGWindowID:
            return id
        case let number as NSNumber:
            return CGWindowID(number.uint32Value)
        default:
            return nil
        }
    }

    private static func pid(from value: Any?) -> pid_t? {
        switch value {
        case let pid as pid_t:
            return pid
        case let number as NSNumber:
            return pid_t(number.int32Value)
        default:
            return nil
        }
    }
}
