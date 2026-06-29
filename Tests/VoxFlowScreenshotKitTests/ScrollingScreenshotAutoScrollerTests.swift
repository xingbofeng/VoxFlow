import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class ScrollingScreenshotAutoScrollerTests: XCTestCase {
    func testFakeAutoScrollerRecordsScrollTicks() {
        let scroller = FakeScrollingScreenshotAutoScroller(hasPermission: true)

        scroller.postScrollTick(lines: 2, at: CGPoint(x: 10, y: 20))
        scroller.postScrollTick(lines: 4, at: CGPoint(x: 30, y: 40))

        XCTAssertEqual(scroller.postedLines, [2, 4])
        XCTAssertEqual(scroller.postedLocations, [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 30, y: 40),
        ])
    }

}

@MainActor
final class FakeScrollingScreenshotAutoScroller: ScrollingScreenshotAutoScrolling {
    var hasAccessibilityPermission: Bool
    private(set) var postedLines: [Int32] = []
    private(set) var postedLocations: [CGPoint] = []
    private(set) var permissionPromptRequestCount = 0

    init(hasPermission: Bool) {
        self.hasAccessibilityPermission = hasPermission
    }

    func postScrollTick(lines: Int32, at location: CGPoint) {
        postedLines.append(lines)
        postedLocations.append(location)
    }

    func requestAccessibilityPermissionPrompt() {
        permissionPromptRequestCount += 1
    }
}
