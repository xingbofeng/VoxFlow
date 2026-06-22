import XCTest
@testable import VoxFlowApp

final class VoiceCorrectionViewPresentationTests: XCTestCase {
    func testNavigationContainsTopLevelVoiceCorrectionTab() {
        XCTAssertTrue(NavigationRoute.allCases.contains(.voiceCorrection))
        XCTAssertEqual(NavigationRoute.voiceCorrection.title, "易错词")
        XCTAssertEqual(NavigationRoute.voiceCorrection.systemImage, "text.badge.checkmark")
    }

    func testVoiceCorrectionViewFocusesOnTargetTermLibrary() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("维护常被听错的专名、术语和写法；OCR 只作为本次临时上下文，不写入这里。"))
        XCTAssertTrue(source.contains("目标词库"))
        XCTAssertTrue(source.contains("目标词"))
        XCTAssertTrue(source.contains("误听写法"))
        XCTAssertTrue(source.contains("本周修正"))
        XCTAssertTrue(source.contains("新增目标词"))
        XCTAssertTrue(source.contains("常见误听写法"))
        XCTAssertTrue(source.contains("最近学习"))
        XCTAssertTrue(source.contains("已学习："))
        XCTAssertTrue(source.contains("撤销"))
        XCTAssertFalse(source.contains("规则列表"))
        XCTAssertFalse(source.contains("原文"))
        XCTAssertFalse(source.contains("替换为"))
        XCTAssertFalse(source.contains("待确认候选"))
        XCTAssertFalse(source.contains("学习候选"))
        XCTAssertFalse(source.contains("Shadow Mode"))
        XCTAssertFalse(source.contains("启用易错词修正"))
        XCTAssertFalse(source.contains("自动学习直接生效"))
        XCTAssertFalse(source.contains("Benchmark"))
        XCTAssertFalse(source.contains("匹配策略"))
    }

    func testVoiceCorrectionSettingsMovedToSettingsPage() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("title: \"易错词修正\""))
        XCTAssertTrue(source.contains("title: \"启用易错词修正\""))
        XCTAssertTrue(source.contains("title: \"自动学习候选词\""))
        XCTAssertTrue(source.contains("title: \"自动学习直接生效\""))
        XCTAssertTrue(source.contains("title: \"影子模式\""))
    }
}
