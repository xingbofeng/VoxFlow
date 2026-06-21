import XCTest
@testable import VoxFlowApp

final class VoiceCorrectionViewPresentationTests: XCTestCase {
    func testNavigationContainsTopLevelVoiceCorrectionTab() {
        XCTAssertTrue(NavigationRoute.allCases.contains(.voiceCorrection))
        XCTAssertEqual(NavigationRoute.voiceCorrection.title, "易错词")
        XCTAssertEqual(NavigationRoute.voiceCorrection.systemImage, "text.badge.checkmark")
    }

    func testVoiceCorrectionViewContainsRequiredSwitchesAndPanels() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("启用易错词修正"))
        XCTAssertTrue(source.contains("自动学习候选词"))
        XCTAssertTrue(source.contains("自动学习直接生效"))
        XCTAssertTrue(source.contains("Shadow Mode"))
        XCTAssertTrue(source.contains("规则列表"))
        XCTAssertTrue(source.contains("学习候选"))
        XCTAssertTrue(source.contains("最近修正"))
        XCTAssertTrue(source.contains("Benchmark"))
    }
}
