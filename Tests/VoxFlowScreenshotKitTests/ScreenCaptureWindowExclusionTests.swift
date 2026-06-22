import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class ScreenCaptureWindowExclusionTests: XCTestCase {
    func testWindowIDsFiltersCurrentProcessWindowsOnly() {
        let windows: [[String: Any]] = [
            [
                kCGWindowNumber as String: CGWindowID(10),
                kCGWindowOwnerPID as String: pid_t(1234),
            ],
            [
                kCGWindowNumber as String: CGWindowID(20),
                kCGWindowOwnerPID as String: pid_t(9999),
            ],
            [
                kCGWindowNumber as String: CGWindowID(30),
                kCGWindowOwnerPID as String: NSNumber(value: 1234),
            ],
        ]

        let ids = ScreenCaptureWindowExclusion.windowIDs(from: windows, ownerPID: 1234)

        XCTAssertEqual(ids, [10, 30])
    }

    func testMalformedWindowEntriesAreIgnored() {
        let windows: [[String: Any]] = [
            [kCGWindowOwnerPID as String: pid_t(1234)],
            [kCGWindowNumber as String: CGWindowID(20)],
            [
                kCGWindowNumber as String: "not a window id",
                kCGWindowOwnerPID as String: pid_t(1234),
            ],
        ]

        let ids = ScreenCaptureWindowExclusion.windowIDs(from: windows, ownerPID: 1234)

        XCTAssertTrue(ids.isEmpty)
    }
}
