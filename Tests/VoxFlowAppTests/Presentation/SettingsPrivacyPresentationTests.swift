import XCTest
@testable import VoxFlowApp

final class SettingsPrivacyPresentationTests: XCTestCase {
    func testPrivacyToggleRowsOnlyExposeCrashLogsAndLLMTraceDiagnostics() throws {
        let rows = SettingsPrivacyPresentation.toggleRows

        XCTAssertEqual(rows.map(\.option), [.crashLogs, .llmTraceDiagnostics])
        XCTAssertFalse(rows.map(\.title).contains("分析"))
        XCTAssertTrue(rows.map(\.title).contains("崩溃日志"))
        let crashLogs = try XCTUnwrap(rows.first { $0.option == .crashLogs })
        XCTAssertTrue(crashLogs.subtitle.contains("音频"))
        XCTAssertTrue(crashLogs.subtitle.contains("转录文本"))
        XCTAssertTrue(crashLogs.subtitle.contains("剪贴板"))
        XCTAssertTrue(crashLogs.subtitle.contains("截图"))
        XCTAssertTrue(crashLogs.subtitle.contains("提示词"))
    }

    func testManualCrashReportSupportCopyExplainsPostCrashRecovery() {
        let support = SettingsPrivacyPresentation.manualCrashReportSupport

        XCTAssertEqual(support.title, "刚刚闪退了？")
        XCTAssertTrue(support.subtitle.contains("最近的系统崩溃报告"))
        XCTAssertEqual(support.viewSummaryButtonTitle, "查看摘要")
        XCTAssertEqual(support.sendLatestButtonTitle, "发送最近报告")
    }
}
