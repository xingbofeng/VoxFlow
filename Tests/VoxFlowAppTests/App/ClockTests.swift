import Foundation
import XCTest
@testable import VoxFlowApp

final class ClockTests: XCTestCase {
    func testClockProtocolSupportsDeterministicNow() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let clock: any AppClock = FixedClock(now: date)

        XCTAssertEqual(clock.now, date)
    }

    func testSystemClockNowIsCurrentDate() {
        let before = Date()
        let now = SystemClock().now
        let after = Date()

        XCTAssertGreaterThanOrEqual(now, before)
        XCTAssertLessThanOrEqual(now, after)
    }
}

private struct FixedClock: AppClock {
    let now: Date

    func sleep(nanoseconds: UInt64) async throws {}
}
