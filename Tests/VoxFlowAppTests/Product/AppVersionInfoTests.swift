import XCTest
@testable import VoxFlowApp

final class AppVersionInfoTests: XCTestCase {
    func testBuildsDisplayVersionFromInfoDictionary() {
        let info = AppVersionInfo.from(
            infoDictionary: [
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "45",
            ]
        )

        XCTAssertEqual(info.version, "1.2.3")
        XCTAssertEqual(info.build, "45")
        XCTAssertEqual(info.displayText, "1.2.3")
        XCTAssertEqual(info.detailedDisplayText, "1.2.3 (45)")
    }

    func testMissingVersionFallsBackToDevelopmentLabel() {
        let info = AppVersionInfo.from(infoDictionary: [:])

        XCTAssertEqual(info.version, "开发版")
        XCTAssertEqual(info.build, "0")
        XCTAssertEqual(info.displayText, "开发版")
        XCTAssertEqual(info.detailedDisplayText, "开发版 (0)")
    }
}
