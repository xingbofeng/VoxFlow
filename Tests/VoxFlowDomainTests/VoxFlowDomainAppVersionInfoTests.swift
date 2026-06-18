import XCTest
import VoxFlowDomain

final class VoxFlowDomainAppVersionInfoTests: XCTestCase {
    func testAppVersionInfoIsAvailableFromDomainTarget() {
        let info = AppVersionInfo.from(
            infoDictionary: [
                "CFBundleShortVersionString": "2.0.0",
                "CFBundleVersion": "42",
            ]
        )

        XCTAssertEqual(info.version, "2.0.0")
        XCTAssertEqual(info.build, "42")
        XCTAssertEqual(info.displayText, "2.0.0")
        XCTAssertEqual(info.detailedDisplayText, "2.0.0 (42)")
    }

    func testAppVersionInfoFallsBackForMissingBundleValues() {
        let info = AppVersionInfo.from(infoDictionary: [:])

        XCTAssertEqual(info.version, "开发版")
        XCTAssertEqual(info.build, "0")
    }
}
