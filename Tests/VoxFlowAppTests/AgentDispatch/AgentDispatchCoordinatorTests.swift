import XCTest
@testable import VoxFlowApp

@MainActor
final class AgentDispatchCoordinatorTests: XCTestCase {
    func testListeningLoadsCurrentAgentCardsForHUDPreview() async {
        let router = FakeAgentRouter(
            agents: [.fixture(id: "front", name: "前端"), .fixture(id: "back", name: "后端")]
        )
        let coordinator = AgentDispatchCoordinator(router: router)

        await coordinator.startListening()

        XCTAssertEqual(coordinator.presentation, .listening(agentNames: ["前端", "后端"]));
        XCTAssertEqual(router.listCallCount, 1)
    }

    func testExactDirectResultBypassesModelAndSubmitsMessage() async {
        let router = FakeAgentRouter(
            agents: [.fixture(id: "front", name: "前端")],
            resolution: .direct(agentID: "front", message: "把按钮改白", matchedBy: "exact_name")
        )
        let model = CapturingAgentModelResolver()
        let coordinator = AgentDispatchCoordinator(router: router, modelResolver: model)

        await coordinator.dispatch(utterance: "前端，把按钮改白")

        XCTAssertEqual(router.sent, [.init(agentID: "front", message: "把按钮改白", submit: true)])
        XCTAssertEqual(model.callCount, 0)
        XCTAssertEqual(coordinator.presentation, .sent(agentName: "前端"))
    }

    func testAmbiguousAndNotFoundResultsWaitForConfirmationWithoutSending() async {
        let agents: [AgentSessionCard] = [
            .fixture(id: "front", name: "前端"),
            .fixture(id: "back", name: "后端"),
        ]
        let router = FakeAgentRouter(agents: agents, resolution: .ambiguous(candidates: ["front", "back"]))
        let coordinator = AgentDispatchCoordinator(router: router)

        await coordinator.dispatch(utterance: "前端后端看一下")

        XCTAssertEqual(coordinator.presentation, .confirmation(
            utterance: "前端后端看一下",
            candidates: agents
        ))
        XCTAssertTrue(router.sent.isEmpty)
    }

    func testSendFailureShowsReasonAndKeepsMessageAvailable() async {
        let router = FakeAgentRouter(
            agents: [.fixture(id: "front", name: "前端")],
            resolution: .direct(agentID: "front", message: "检查按钮", matchedBy: "exact_name"),
            sendError: AgentRouterClientError.router("任务助手已退出")
        )
        let coordinator = AgentDispatchCoordinator(router: router)

        await coordinator.dispatch(utterance: "前端，检查按钮")

        XCTAssertEqual(coordinator.presentation, .failure(message: "任务助手已退出", retainedText: "检查按钮"))
    }

    func testLateListeningResultCannotOverwriteCompletedDispatch() async {
        let router = DelayedListeningAgentRouter(
            agent: .fixture(id: "front", name: "前端")
        )
        let coordinator = AgentDispatchCoordinator(router: router)
        let listening = Task { await coordinator.startListening() }
        await router.waitUntilFirstListIsPending()

        await coordinator.dispatch(utterance: "前端，把按钮改白")
        await router.finishFirstList()
        await listening.value

        XCTAssertEqual(coordinator.presentation, .sent(agentName: "前端"))
    }

    func testInvalidatedDispatchDoesNotPublishLateSendResult() async {
        let router = DelayedSendAgentRouter(
            agent: .fixture(id: "front", name: "前端")
        )
        let coordinator = AgentDispatchCoordinator(router: router)
        var presentations: [AgentDispatchHUDPresentation] = []
        coordinator.onPresentationChange = { presentations.append($0) }

        let dispatch = Task { await coordinator.dispatch(utterance: "前端，把按钮改白") }
        await router.waitUntilSendIsPending()
        coordinator.invalidatePendingListening()
        await router.finishSend()
        await dispatch.value

        XCTAssertFalse(presentations.contains(.sent(agentName: "前端")))
        XCTAssertEqual(coordinator.presentation, .exact(agentName: "前端", message: "把按钮改白"))
    }

    func testMediumConfidenceModelFallbackOnlyReordersCandidatesAndNeverSends() async {
        let agents: [AgentSessionCard] = [
            .fixture(id: "front", name: "前端"),
            .fixture(id: "back", name: "后端"),
        ]
        let router = FakeAgentRouter(agents: agents, resolution: .notFound)
        let model = CapturingAgentModelResolver(
            resolution: .init(agentID: "back", message: "检查接口", confidence: 0.7)
        )
        let coordinator = AgentDispatchCoordinator(router: router, modelResolver: model)

        await coordinator.dispatch(utterance: "检查一下接口")

        XCTAssertEqual(model.callCount, 1)
        XCTAssertEqual(coordinator.presentation, .confirmation(
            utterance: "检查一下接口",
            candidates: [agents[1], agents[0]]
        ))
        XCTAssertTrue(router.sent.isEmpty)
    }

    func testHighConfidenceModelFallbackShowsExactThenSubmitsAfterCancelWindow() async {
        let agents: [AgentSessionCard] = [
            .fixture(id: "front", name: "前端"),
            .fixture(id: "back", name: "后端"),
        ]
        let router = FakeAgentRouter(agents: agents, resolution: .notFound)
        let model = CapturingAgentModelResolver(
            resolution: .init(agentID: "back", message: "检查接口", confidence: 0.9)
        )
        let coordinator = AgentDispatchCoordinator(
            router: router,
            modelResolver: model,
            highConfidenceSendDelayNanoseconds: 0
        )

        await coordinator.dispatch(utterance: "检查一下接口")

        XCTAssertEqual(router.sent, [
            .init(agentID: "back", message: "检查接口", submit: true),
        ])
        XCTAssertEqual(coordinator.presentation, .sent(agentName: "后端"))
    }

    func testLowConfidenceModelFallbackFailsWithoutSending() async {
        let agents: [AgentSessionCard] = [
            .fixture(id: "front", name: "前端"),
            .fixture(id: "back", name: "后端"),
        ]
        let router = FakeAgentRouter(agents: agents, resolution: .notFound)
        let model = CapturingAgentModelResolver(
            resolution: .init(agentID: "back", message: "检查接口", confidence: 0.59)
        )
        let coordinator = AgentDispatchCoordinator(router: router, modelResolver: model)

        await coordinator.dispatch(utterance: "检查一下接口")

        XCTAssertEqual(
            coordinator.presentation,
            .failure(
                message: L10n.localize("agent_dispatch.error.no_clear_target", comment: ""),
                retainedText: "检查一下接口"
            )
        )
        XCTAssertTrue(router.sent.isEmpty)
    }

    func testDefaultUnresolvedBehaviorFallsBackToCurrentInputForNotFoundUtterance() async {
        let agents: [AgentSessionCard] = [
            .fixture(id: "front", name: "前端"),
            .fixture(id: "back", name: "后端"),
        ]
        let router = FakeAgentRouter(agents: agents, resolution: .notFound)
        let model = CapturingAgentModelResolver()
        let coordinator = AgentDispatchCoordinator(
            router: router,
            modelResolver: model,
            unresolvedBehavior: { "default" }
        )

        await coordinator.dispatch(utterance: "检查一下按钮")

        XCTAssertTrue(router.sent.isEmpty)
        XCTAssertEqual(model.callCount, 0)
        XCTAssertEqual(coordinator.presentation.title, L10n.localize("hud.title.fallback_input", comment: ""))
        XCTAssertEqual(coordinator.presentation.detail, "检查一下按钮")
    }

    func testConfirmUnresolvedBehaviorWithoutAgentsFallsBackToCurrentInput() async {
        let router = FakeAgentRouter(agents: [], resolution: .notFound)
        let coordinator = AgentDispatchCoordinator(router: router)

        await coordinator.dispatch(utterance: "检查一下按钮")

        XCTAssertTrue(router.sent.isEmpty)
        XCTAssertEqual(coordinator.presentation, .fallbackInput(text: "检查一下按钮"))
    }

    func testDefaultUnresolvedBehaviorFallsBackToCurrentInputEvenWhenNoAgentIsAvailable() async {
        let router = FakeAgentRouter(agents: [], resolution: .notFound)
        let coordinator = AgentDispatchCoordinator(
            router: router,
            unresolvedBehavior: { "default" }
        )

        await coordinator.dispatch(utterance: "检查一下按钮")

        XCTAssertTrue(router.sent.isEmpty)
        XCTAssertEqual(coordinator.presentation.title, L10n.localize("hud.title.fallback_input", comment: ""))
        XCTAssertEqual(coordinator.presentation.detail, "检查一下按钮")
    }

    func testUserConfirmationLearnsAliasThenSubmitsTheParsedMessage() async {
        let router = FakeAgentRouter(
            agents: [.fixture(id: "front", name: "前端")],
            resolution: .notFound
        )
        let coordinator = AgentDispatchCoordinator(router: router)
        await coordinator.dispatch(utterance: "前台，把按钮改白")

        await coordinator.confirm(
            agentID: "front",
            utterance: "前台，把按钮改白",
            message: "把按钮改白",
            alias: "前台"
        )

        XCTAssertEqual(router.learnedAliases, ["前台": "front"])
        XCTAssertEqual(router.sent, [
            .init(agentID: "front", message: "把按钮改白", submit: true),
        ])
        XCTAssertEqual(coordinator.presentation, .sent(agentName: "前端"))
    }
}

private actor DelayedListeningAgentRouter: AgentRouting {
    let agent: AgentSessionCard
    private var listCallCount = 0
    private var firstListContinuation: CheckedContinuation<[AgentSessionCard], Never>?

    init(agent: AgentSessionCard) {
        self.agent = agent
    }

    func listAgents() async throws -> [AgentSessionCard] {
        listCallCount += 1
        if listCallCount == 1 {
            return await withCheckedContinuation { continuation in
                firstListContinuation = continuation
            }
        }
        return [agent]
    }

    func waitUntilFirstListIsPending() async {
        while firstListContinuation == nil {
            await Task.yield()
        }
    }

    func finishFirstList() {
        firstListContinuation?.resume(returning: [agent])
        firstListContinuation = nil
    }

    func resolve(utterance: String) async throws -> AgentResolveOutcome {
        .direct(agentID: agent.agentID, message: "把按钮改白", matchedBy: "exact_name")
    }

    func send(_ request: AgentDispatchRequest) async throws {}
    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws {}
}

private actor DelayedSendAgentRouter: AgentRouting {
    let agent: AgentSessionCard
    private var sendContinuation: CheckedContinuation<Void, Never>?

    init(agent: AgentSessionCard) {
        self.agent = agent
    }

    func listAgents() async throws -> [AgentSessionCard] { [agent] }

    func resolve(utterance: String) async throws -> AgentResolveOutcome {
        .direct(agentID: agent.agentID, message: "把按钮改白", matchedBy: "exact_name")
    }

    func send(_ request: AgentDispatchRequest) async throws {
        await withCheckedContinuation { continuation in
            sendContinuation = continuation
        }
    }

    func waitUntilSendIsPending() async {
        while sendContinuation == nil {
            await Task.yield()
        }
    }

    func finishSend() {
        sendContinuation?.resume()
        sendContinuation = nil
    }

    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws {}
}

private final class FakeAgentRouter: AgentRouting, @unchecked Sendable {
    let agents: [AgentSessionCard]
    let resolution: AgentResolveOutcome
    let sendError: Error?
    private(set) var listCallCount = 0
    private(set) var sent: [AgentDispatchRequest] = []
    private(set) var learnedAliases: [String: String] = [:]

    init(
        agents: [AgentSessionCard],
        resolution: AgentResolveOutcome = .notFound,
        sendError: Error? = nil
    ) {
        self.agents = agents
        self.resolution = resolution
        self.sendError = sendError
    }

    func listAgents() async throws -> [AgentSessionCard] {
        listCallCount += 1
        return agents
    }

    func resolve(utterance: String) async throws -> AgentResolveOutcome { resolution }

    func send(_ request: AgentDispatchRequest) async throws {
        if let sendError { throw sendError }
        sent.append(request)
    }

    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws {
        if userConfirmed {
            learnedAliases[alias] = agentID
        }
    }
}

private final class CapturingAgentModelResolver: AgentTargetModelResolving, @unchecked Sendable {
    let resolution: AgentModelResolution?
    private(set) var callCount = 0

    init(resolution: AgentModelResolution? = nil) {
        self.resolution = resolution
    }

    func resolve(utterance: String, candidates: [AgentSessionCard]) async throws -> AgentModelResolution? {
        callCount += 1
        return resolution
    }
}

private extension AgentSessionCard {
    static func fixture(id: String, name: String) -> AgentSessionCard {
        AgentSessionCard(
            schemaVersion: 1,
            agentID: id,
            cli: "codex",
            command: ["codex"],
            cwd: "/tmp/project",
            repoName: "project",
            branch: "main",
            status: .active,
            displayName: name
        )
    }
}
