import Foundation
import XCTest
import VoxFlowInfrastructure

final class VoxFlowInfrastructureClockTests: XCTestCase {
    func testClockProtocolIsAvailableFromInfrastructureTarget() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let clock: any AppClock = InfrastructureFixedClock(now: date)

        XCTAssertEqual(clock.now, date)
    }

    func testSystemClockIsAvailableFromInfrastructureTarget() {
        let before = Date()
        let now = SystemClock().now
        let after = Date()

        XCTAssertGreaterThanOrEqual(now, before)
        XCTAssertLessThanOrEqual(now, after)
    }
}

private struct InfrastructureFixedClock: AppClock {
    let now: Date

    func sleep(nanoseconds: UInt64) async throws {}
}
