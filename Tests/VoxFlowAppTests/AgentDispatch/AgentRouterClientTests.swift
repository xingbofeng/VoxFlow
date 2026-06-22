import XCTest
@testable import VoxFlowApp

final class AgentRouterClientTests: XCTestCase {
    func testClientUsesRouterMethodsAndDecodesResults() async throws {
        let transport = CapturingAgentRouterTransport(responses: [
            #"{"id":1,"result":[]}"#,
            #"{"id":2,"result":{"outcome":"direct","agent_id":"front","message":"检查按钮","matched_by":"exact_name"}}"#,
            #"{"id":3,"result":{"submitted":true}}"#,
        ])
        let client = AgentRouterClient(transport: transport)

        let agents = try await client.listAgents()
        let resolution = try await client.resolve(utterance: "前端，检查按钮")
        XCTAssertEqual(agents, [])
        XCTAssertEqual(
            resolution,
            .direct(agentID: "front", message: "检查按钮", matchedBy: "exact_name")
        )
        try await client.send(.init(agentID: "front", message: "检查按钮", submit: true))

        XCTAssertEqual(transport.methods, ["list_agents", "resolve_agent", "send_message"])
        XCTAssertEqual(
            (transport.requests.first?["params"] as? [String: Any])?["include_inactive"] as? Bool,
            false
        )
        let params = transport.requests.last?["params"] as? [String: Any]
        XCTAssertEqual(params?["submit"] as? Bool, true)
    }

    func testSettingsListCanExplicitlyIncludeInactiveSessions() async throws {
        let transport = CapturingAgentRouterTransport(responses: [#"{"id":1,"result":[]}"#])
        let client = AgentRouterClient(transport: transport)

        _ = try await client.listAllAgents()

        XCTAssertEqual(
            (transport.requests.first?["params"] as? [String: Any])?["include_inactive"] as? Bool,
            true
        )
    }

    func testClientCanClearDispatchLog() async throws {
        let transport = CapturingAgentRouterTransport(responses: [#"{"id":1,"result":{"cleared":true}}"#])
        let client = AgentRouterClient(transport: transport)

        try await client.clearDispatchLog()

        XCTAssertEqual(transport.methods, ["clear_dispatch_log"])
    }

    func testClientSurfacesStructuredRouterError() async {
        let transport = CapturingAgentRouterTransport(responses: [
            #"{"id":1,"error":{"code":"router_error","message":"任务助手已退出"}}"#,
        ])
        let client = AgentRouterClient(transport: transport)

        await XCTAssertThrowsErrorAsync(try await client.listAgents()) { error in
            XCTAssertEqual(error as? AgentRouterClientError, .router("任务助手已退出"))
        }
    }

    func testClientTimesOutWhenTransportDoesNotReturn() async {
        let client = AgentRouterClient(
            transport: HangingAgentRouterTransport(),
            timeoutNanoseconds: 20_000_000
        )

        await XCTAssertThrowsErrorAsync(try await client.listAgents()) { error in
            XCTAssertEqual(error as? AgentRouterClientError, .timeout)
        }
    }

    func testClientRejectsOversizedRequestsBeforeOpeningSocket() async {
        let transport = CapturingAgentRouterTransport(responses: [])
        let client = AgentRouterClient(transport: transport)
        let oversizedMessage = String(repeating: "x", count: 1_100_000)

        await XCTAssertThrowsErrorAsync(
            try await client.send(.init(agentID: "front", message: oversizedMessage, submit: true))
        ) { error in
            XCTAssertEqual(error as? AgentRouterClientError, .requestTooLarge)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}

private final class CapturingAgentRouterTransport: AgentRouterTransport, @unchecked Sendable {
    private var responses: [String]
    private(set) var requests: [[String: Any]] = []
    var methods: [String] { requests.compactMap { $0["method"] as? String } }

    init(responses: [String]) { self.responses = responses }

    func send(_ data: Data) async throws -> Data {
        requests.append(try JSONSerialization.jsonObject(with: data) as! [String: Any])
        return Data(responses.removeFirst().utf8)
    }
}

private final class HangingAgentRouterTransport: AgentRouterTransport, @unchecked Sendable {
    func send(_ data: Data) async throws -> Data {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return Data()
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch {
        handler(error)
    }
}
