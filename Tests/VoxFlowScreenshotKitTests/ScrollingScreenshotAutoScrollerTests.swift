import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class ScrollingScreenshotAutoScrollerTests: XCTestCase {
    func testFakeAutoScrollerRecordsScrollTicks() {
        let scroller = FakeScrollingScreenshotAutoScroller(hasPermission: true)

        scroller.postScrollTick(lines: 2)
        scroller.postScrollTick(lines: 4)

        XCTAssertEqual(scroller.postedLines, [2, 4])
    }
}

@MainActor
final class FakeScrollingScreenshotAutoScroller: ScrollingScreenshotAutoScrolling {
    var hasAccessibilityPermission: Bool
    private(set) var postedLines: [Int32] = []

    init(hasPermission: Bool) {
        self.hasAccessibilityPermission = hasPermission
    }

    func postScrollTick(lines: Int32) {
        postedLines.append(lines)
    }
}
