import XCTest
@testable import VoxFlowApp

final class AgentRouterCodecTests: XCTestCase {
    func testDecodesRustDirectAndAmbiguousOutcomes() throws {
        let direct = try JSONDecoder().decode(AgentResolveOutcome.self, from: Data(#"{"outcome":"direct","agent_id":"front","message":"检查按钮","matched_by":"exact_name"}"#.utf8))
        XCTAssertEqual(direct, .direct(agentID: "front", message: "检查按钮", matchedBy: "exact_name"))

        let ambiguous = try JSONDecoder().decode(AgentResolveOutcome.self, from: Data(#"{"outcome":"ambiguous","candidates":["front","back"]}"#.utf8))
        XCTAssertEqual(ambiguous, .ambiguous(candidates: ["front", "back"]))
    }

    func testDecodesRustSessionCardUsingSnakeCaseKeys() throws {
        let card = try JSONDecoder().decode(AgentSessionCard.self, from: Data(#"{"schema_version":1,"agent_id":"front","wrapper_pid":1,"child_pid":2,"cli":"codex","command":["codex"],"cwd":"/tmp/web","repo_root":"/tmp/web","repo_name":"web","branch":"main","terminal":"ghostty","tty":"/dev/ttys1","input_channel":"/tmp/front.stdin","status":"active","exit_code":null,"self_summary":{"label":"前端","summary":"页面","topics":[],"phase":"editing","expires_at":9999999999},"provider_session_refs":[],"last_dispatched_at":null,"started_at":1,"updated_at":2}"#.utf8))
        XCTAssertEqual(card.agentID, "front")
        XCTAssertEqual(card.displayName, "前端")
        XCTAssertEqual(card.status, .active)
    }

    func testSessionStatusPresentationUsesChineseAndOnlyActiveIsDispatchable() {
        XCTAssertEqual(AgentSessionStatus.active.localizedTitle, "在线")
        XCTAssertEqual(AgentSessionStatus.exited.localizedTitle, "已退出")
        XCTAssertEqual(AgentSessionStatus.stale.localizedTitle, "已失效")

        XCTAssertTrue(AgentSessionStatus.active.isDispatchable)
        XCTAssertFalse(AgentSessionStatus.exited.isDispatchable)
        XCTAssertFalse(AgentSessionStatus.stale.isDispatchable)
    }

    func testCurrentAgentCardsExcludeExitedAndStaleSessions() {
        let cards: [AgentSessionCard] = [
            .fixture(id: "front", name: "前端", status: .active),
            .fixture(id: "old", name: "旧终端", status: .exited),
            .fixture(id: "stale", name: "断联终端", status: .stale),
        ]

        XCTAssertEqual(cards.currentDispatchableAgents.map(\.displayName), ["前端"])
    }

    func testExpiredSelfSummaryDoesNotRemainTheVisibleAgentIdentity() throws {
        let card = try JSONDecoder().decode(AgentSessionCard.self, from: Data(#"{"schema_version":1,"agent_id":"front","wrapper_pid":1,"child_pid":2,"cli":"codex","command":["codex"],"cwd":"/tmp/web","repo_root":"/tmp/web","repo_name":"web","branch":"main","terminal":"ghostty","tty":"/dev/ttys1","input_channel":"/tmp/front.stdin","status":"active","exit_code":null,"self_summary":{"label":"旧前端","summary":"过期任务","topics":[],"phase":"done","expires_at":1},"provider_session_refs":[],"last_dispatched_at":null,"started_at":1,"updated_at":2}"#.utf8))

        XCTAssertNil(card.currentSelfSummary)
        XCTAssertEqual(card.displayName, "web")
    }

    func testObservedProviderTitlePrecedesSelfSummaryForDisplayName() throws {
        let card = try JSONDecoder().decode(AgentSessionCard.self, from: Data(#"{"schema_version":1,"agent_id":"front","wrapper_pid":1,"child_pid":2,"cli":"claude","command":["claude"],"cwd":"/tmp/web","repo_root":"/tmp/web","repo_name":"web","branch":"main","terminal":"ghostty","tty":"/dev/ttys1","input_channel":"/tmp/front.stdin","status":"active","exit_code":null,"observed_title":{"title":"登录页修复","source":"claude.ai-title","updated_at":2},"self_summary":{"label":"前端","summary":"页面","topics":[],"phase":"editing","expires_at":9999999999},"provider_session_refs":[],"last_dispatched_at":null,"started_at":1,"updated_at":2}"#.utf8))

        XCTAssertEqual(card.displayName, "登录页修复")
    }
}

private extension AgentSessionCard {
    static func fixture(id: String, name: String, status: AgentSessionStatus) -> AgentSessionCard {
        AgentSessionCard(
            schemaVersion: 1,
            agentID: id,
            cli: "codex",
            command: ["codex"],
            cwd: "/tmp/project",
            repoName: "project",
            branch: "main",
            status: status,
            displayName: name
        )
    }
}
