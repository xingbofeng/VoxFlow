import XCTest
@testable import VoxFlowApp

final class AgentDispatchHUDPresentationTests: XCTestCase {
    func testListeningExactConfirmationSuccessAndFailureCopy() {
        XCTAssertEqual(
            AgentDispatchHUDPresentation.listening(agentNames: ["前端", "后端", "数据库"]).title,
            "正在听你说"
        )
        XCTAssertEqual(
            AgentDispatchHUDPresentation.exact(agentName: "前端", message: "检查按钮").badge,
            "100% 直接发送"
        )
        XCTAssertEqual(
            AgentDispatchHUDPresentation.confirmation(utterance: "看一下", candidates: []).title,
            "选择要指挥的队员"
        )
        XCTAssertEqual(AgentDispatchHUDPresentation.sent(agentName: "前端").title, "已发送给前端")
        XCTAssertEqual(
            AgentDispatchHUDPresentation.failure(message: "队员已退出", retainedText: "检查按钮").detail,
            "队员已退出\n指令已保留：检查按钮"
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
