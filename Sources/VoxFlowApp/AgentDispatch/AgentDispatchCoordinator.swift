import Foundation

protocol AgentRouting: Sendable {
    func listAgents() async throws -> [AgentSessionCard]
    func resolve(utterance: String) async throws -> AgentResolveOutcome
    func send(_ request: AgentDispatchRequest) async throws
    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws
}

@MainActor
final class AgentDispatchCoordinator {
    private let router: any AgentRouting
    private let modelResolver: (any AgentTargetModelResolving)?
    private let directSendEnabled: () -> Bool
    private let unresolvedBehavior: () -> String
    private let highConfidenceSendDelayNanoseconds: UInt64
    private var listeningRevision = 0
    private(set) var agents: [AgentSessionCard] = []
    private(set) var presentation: AgentDispatchHUDPresentation = .idle
    var onPresentationChange: ((AgentDispatchHUDPresentation) -> Void)?

    init(
        router: any AgentRouting,
        modelResolver: (any AgentTargetModelResolving)? = nil,
        directSendEnabled: @escaping () -> Bool = { true },
        unresolvedBehavior: @escaping () -> String = { "confirm" },
        highConfidenceSendDelayNanoseconds: UInt64 = 1_200_000_000
    ) {
        self.router = router
        self.modelResolver = modelResolver
        self.directSendEnabled = directSendEnabled
        self.unresolvedBehavior = unresolvedBehavior
        self.highConfidenceSendDelayNanoseconds = highConfidenceSendDelayNanoseconds
    }

    func startListening() async {
        listeningRevision &+= 1
        let revision = listeningRevision
        do {
            let currentAgents = try await router.listAgents()
            guard revision == listeningRevision else { return }
            agents = currentAgents.currentDispatchableAgents
            present(.listening(agentNames: agents.map(\.displayName)))
        } catch {
            guard revision == listeningRevision else { return }
            present(.failure(message: error.localizedDescription, retainedText: ""))
        }
    }

    func dispatch(utterance: String) async {
        invalidatePendingListening()
        let revision = listeningRevision
        do {
            agents = try await router.listAgents().currentDispatchableAgents
            guard revision == listeningRevision else { return }
            let outcome = try await router.resolve(utterance: utterance)
            guard revision == listeningRevision else { return }
            switch outcome {
            case let .direct(agentID, message, _):
                guard let agent = agents.first(where: { $0.agentID == agentID }) else {
                    present(.failure(message: "目标队员已不可用", retainedText: message))
                    return
                }
                guard directSendEnabled() else {
                    present(.confirmation(utterance: utterance, candidates: [agent]))
                    return
                }
                present(.exact(agentName: agent.displayName, message: message))
                do {
                    try await router.send(.init(agentID: agentID, message: message, submit: true))
                    guard revision == listeningRevision else { return }
                    present(.sent(agentName: agent.displayName))
                } catch {
                    guard revision == listeningRevision else { return }
                    present(.failure(
                        message: error.localizedDescription,
                        retainedText: message
                    ))
                }
            case let .ambiguous(candidateIDs):
                let behavior = unresolvedBehavior()
                guard behavior != "cancel" else {
                    present(.failure(message: "已取消发送", retainedText: utterance))
                    return
                }
                guard behavior != "default" else {
                    present(.fallbackInput(text: utterance))
                    return
                }
                await presentCandidates(
                    utterance: utterance,
                    candidateIDs: candidateIDs
                )
            case .notFound:
                let behavior = unresolvedBehavior()
                guard behavior != "cancel" else {
                    present(.failure(message: "已取消发送", retainedText: utterance))
                    return
                }
                guard behavior != "default" else {
                    present(.fallbackInput(text: utterance))
                    return
                }
                await presentCandidates(
                    utterance: utterance,
                    candidateIDs: agents.map(\.agentID)
                )
            case .invalidMessage:
                present(.failure(message: "没有识别到要发送的指令", retainedText: utterance))
            case let .unavailable(_, reason):
                present(.failure(message: reason.userMessage, retainedText: utterance))
            }
        } catch {
            present(.failure(message: error.localizedDescription, retainedText: utterance))
        }
    }

    func confirm(agentID: String, utterance: String, message: String, alias: String?) async {
        invalidatePendingListening()
        let revision = listeningRevision
        do {
            if let alias, !alias.isEmpty {
                try await router.learnAlias(alias, agentID: agentID, userConfirmed: true)
                guard revision == listeningRevision else { return }
            }
            try await router.send(.init(agentID: agentID, message: message, submit: true))
            guard revision == listeningRevision else { return }
            present(.sent(
                agentName: agents.first(where: { $0.agentID == agentID })?.displayName ?? agentID
            ))
        } catch {
            guard revision == listeningRevision else { return }
            present(.failure(message: error.localizedDescription, retainedText: message))
        }
    }

    func fallbackToClipboard(text: String) {
        invalidatePendingListening()
        present(.clipboardFallback(text: text))
    }

    func fail(message: String, retainedText: String) {
        invalidatePendingListening()
        present(.failure(message: message, retainedText: retainedText))
    }

    func invalidatePendingListening() {
        listeningRevision &+= 1
    }

    private func presentCandidates(utterance: String, candidateIDs: [String]) async {
        var candidates = agents.filter { candidateIDs.contains($0.agentID) }
        guard !candidates.isEmpty else {
            present(.failure(message: "没有可用队员", retainedText: utterance))
            return
        }
        if let modelResolver,
           let resolution = try? await modelResolver.resolve(
               utterance: utterance,
               candidates: candidates
           ) {
            guard resolution.confidence >= 0.60 else {
                present(.failure(message: "找不到明确队员", retainedText: utterance))
                return
            }
            if let preferred = candidates.first(where: { $0.agentID == resolution.agentID }) {
                candidates.removeAll { $0.agentID == preferred.agentID }
                candidates.insert(preferred, at: 0)

                if resolution.confidence >= 0.85, directSendEnabled() {
                    let message = resolution.message.trimmingCharacters(in: .whitespacesAndNewlines)
                    let dispatchMessage = message.isEmpty ? utterance : message
                    present(.exact(agentName: preferred.displayName, message: dispatchMessage))
                    let revision = listeningRevision
                    if highConfidenceSendDelayNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: highConfidenceSendDelayNanoseconds)
                    }
                    guard revision == listeningRevision else { return }
                    do {
                        try await router.send(.init(
                            agentID: preferred.agentID,
                            message: dispatchMessage,
                            submit: true
                        ))
                        present(.sent(agentName: preferred.displayName))
                    } catch {
                        present(.failure(
                            message: error.localizedDescription,
                            retainedText: dispatchMessage
                        ))
                    }
                    return
                }
            }
        }
        present(.confirmation(utterance: utterance, candidates: candidates))
    }

    private func present(_ next: AgentDispatchHUDPresentation) {
        presentation = next
        onPresentationChange?(next)
    }
}

extension AgentDispatchFailureReason {
    var userMessage: String {
        switch self {
        case .exited: return "队员已退出"
        case .stale: return "队员连接已失效"
        case .inputChannelMissing: return "队员输入通道不可用"
        case .ambiguous: return "匹配到多个队员"
        case .notFound: return "找不到对应队员"
        case .writeFailed: return "发送失败"
        }
    }
}
