import XCTest
@testable import VoxFlowApp

final class AgentDispatchHUDPresentationTests: XCTestCase {
    func testListeningExactConfirmationSuccessAndFailureCopy() {
        XCTAssertEqual(
            AgentDispatchHUDPresentation.listening(agentNames: ["前端", "后端", "数据库"]).title,
            L10n.localize("hud.title.listening", comment: "")
        )
        XCTAssertEqual(
            AgentDispatchHUDPresentation.exact(agentName: "前端", message: "检查按钮").badge,
            L10n.localize("hud.badge.exact_send", comment: "")
        )
        XCTAssertEqual(
            AgentDispatchHUDPresentation.confirmation(utterance: "看一下", candidates: []).title,
            L10n.localize("hud.title.confirmation", comment: "")
        )
        XCTAssertEqual(
            AgentDispatchHUDPresentation.sent(agentName: "前端").title,
            String(format: L10n.localize("hud.feedback.sent_to_agent_format", comment: ""), "前端")
        )
        XCTAssertEqual(
            AgentDispatchHUDPresentation.failure(message: "任务助手已退出", retainedText: "检查按钮").detail,
            String(format: L10n.localize("hud.detail.failure_with_retained", comment: ""), "任务助手已退出", "检查按钮")
        )
    }

    func testConfirmationIntentLearnsOnlyConservativelyParsedAlias() {
        XCTAssertEqual(
            AgentConfirmationIntent.parse("前台，把按钮改白"),
            AgentConfirmationIntent(alias: "前台", message: "把按钮改白")
        )
        XCTAssertEqual(
            AgentConfirmationIntent.parse("给数据库说检查迁移"),
            AgentConfirmationIntent(alias: "数据库", message: "检查迁移")
        )
        XCTAssertEqual(
            AgentConfirmationIntent.parse("把按钮改白"),
            AgentConfirmationIntent(alias: nil, message: "把按钮改白")
        )
    }
}
