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
    private(set) var lastDispatchedMessage: String?
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
        lastDispatchedMessage = nil
        let revision = listeningRevision
        AppLogger.dictation.debug("AgentDispatchCoordinator startListening revision=\(revision)")
        do {
            let currentAgents = try await router.listAgents()
            guard revision == listeningRevision else { return }
            agents = currentAgents.currentDispatchableAgents
            present(.listening(agentNames: agents.map(\.displayName)))
            AppLogger.dictation.debug("AgentDispatchCoordinator startListening agents=\(agents.count)")
        } catch {
            guard revision == listeningRevision else { return }
            AppLogger.dictation.warning("AgentDispatchCoordinator startListening failed: \(error.localizedDescription)")
            present(.failure(message: error.localizedDescription, retainedText: ""))
        }
    }

    func dispatch(utterance: String) async {
        invalidatePendingListening()
        let revision = listeningRevision
        AppLogger.dictation.debug("AgentDispatchCoordinator dispatch revision=\(revision) utteranceLen=\(utterance.count)")
        do {
            agents = try await router.listAgents().currentDispatchableAgents
            guard revision == listeningRevision else { return }
            let outcome = try await router.resolve(utterance: utterance)
            guard revision == listeningRevision else { return }
            switch outcome {
            case let .direct(agentID, message, _):
                guard let agent = agents.first(where: { $0.agentID == agentID }) else {
                    AppLogger.dictation.warning("AgentDispatchCoordinator direct resolution failed missing agent=\(agentID)")
                    present(.failure(
                        message: L10n.localize("agent_dispatch.error.target_unavailable", comment: ""),
                        retainedText: message
                    ))
                    return
                }
                guard directSendEnabled() else {
                    AppLogger.dictation.debug("AgentDispatchCoordinator direct resolution requires confirmation")
                    present(.confirmation(utterance: utterance, candidates: [agent]))
                    return
                }
                present(.exact(agentName: agent.displayName, message: message))
                do {
                    try await router.send(.init(agentID: agentID, message: message, submit: true))
                    guard revision == listeningRevision else { return }
                    lastDispatchedMessage = message
                    present(.sent(agentName: agent.displayName))
                } catch {
                    guard revision == listeningRevision else { return }
                    AppLogger.dictation.warning("AgentDispatchCoordinator direct send failed: \(error.localizedDescription)")
                    present(.failure(
                        message: error.localizedDescription,
                        retainedText: message
                    ))
                }
            case let .ambiguous(candidateIDs):
                let behavior = unresolvedBehavior()
                AppLogger.dictation.debug("AgentDispatchCoordinator outcome ambiguous behavior=\(behavior) candidates=\(candidateIDs.count)")
                guard behavior != "cancel" else {
                    present(.failure(
                        message: L10n.localize("agent_dispatch.error.cancelled_send", comment: ""),
                        retainedText: utterance
                    ))
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
                AppLogger.dictation.debug("AgentDispatchCoordinator outcome notFound behavior=\(behavior)")
                guard behavior != "cancel" else {
                    present(.failure(
                        message: L10n.localize("agent_dispatch.error.cancelled_send", comment: ""),
                        retainedText: utterance
                    ))
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
                present(.failure(
                    message: L10n.localize("agent_dispatch.error.no_command_to_send", comment: ""),
                    retainedText: utterance
                ))
            case let .unavailable(_, reason):
                present(.failure(message: reason.userMessage, retainedText: utterance))
            }
        } catch {
            AppLogger.dictation.warning("AgentDispatchCoordinator dispatch failed: \(error.localizedDescription)")
            present(.failure(message: error.localizedDescription, retainedText: utterance))
        }
    }

    func confirm(agentID: String, utterance: String, message: String, alias: String?) async {
        invalidatePendingListening()
        let revision = listeningRevision
        AppLogger.dictation.debug("AgentDispatchCoordinator confirm revision=\(revision) agent=\(agentID)")
        do {
            if let alias, !alias.isEmpty {
                try await router.learnAlias(alias, agentID: agentID, userConfirmed: true)
                guard revision == listeningRevision else { return }
            }
            try await router.send(.init(agentID: agentID, message: message, submit: true))
            guard revision == listeningRevision else { return }
            lastDispatchedMessage = message
            present(.sent(
                agentName: agents.first(where: { $0.agentID == agentID })?.displayName ?? agentID
            ))
        } catch {
            guard revision == listeningRevision else { return }
            AppLogger.dictation.warning("AgentDispatchCoordinator confirm failed: \(error.localizedDescription)")
            present(.failure(message: error.localizedDescription, retainedText: message))
        }
    }

    func fallbackToClipboard(text: String) {
        invalidatePendingListening()
        AppLogger.dictation.debug("AgentDispatchCoordinator fallbackToClipboard textLen=\(text.count)")
        present(.clipboardFallback(text: text))
    }

    func fail(message: String, retainedText: String) {
        invalidatePendingListening()
        AppLogger.dictation.warning("AgentDispatchCoordinator fail message=\(message)")
        present(.failure(message: message, retainedText: retainedText))
    }

    func invalidatePendingListening() {
        listeningRevision &+= 1
        AppLogger.dictation.debug("AgentDispatchCoordinator invalidatePendingListening revision=\(listeningRevision)")
    }

    private func presentCandidates(utterance: String, candidateIDs: [String]) async {
        var candidates = agents.filter { candidateIDs.contains($0.agentID) }
        guard !candidates.isEmpty else {
            present(.fallbackInput(text: utterance))
            return
        }
        if let modelResolver,
           let resolution = try? await modelResolver.resolve(
               utterance: utterance,
               candidates: candidates
           ) {
            guard resolution.confidence >= 0.60 else {
                present(.failure(
                    message: L10n.localize("agent_dispatch.error.no_clear_target", comment: ""),
                    retainedText: utterance
                ))
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
                        AppLogger.dictation.debug("AgentDispatchCoordinator high-confidence auto-send agent=\(preferred.displayName)")
                        try await router.send(.init(
                            agentID: preferred.agentID,
                            message: dispatchMessage,
                            submit: true
                        ))
                        lastDispatchedMessage = dispatchMessage
                        present(.sent(agentName: preferred.displayName))
                    } catch {
                        AppLogger.dictation.warning("AgentDispatchCoordinator auto-send failed: \(error.localizedDescription)")
                        present(.failure(
                            message: error.localizedDescription,
                            retainedText: dispatchMessage
                        ))
                    }
                    return
                }
            }
        }
        AppLogger.dictation.debug("AgentDispatchCoordinator present confirmation for \(candidates.count) candidates")
        present(.confirmation(utterance: utterance, candidates: candidates))
    }

    private func present(_ next: AgentDispatchHUDPresentation) {
        switch next {
        case .sent:
            break
        default:
            lastDispatchedMessage = nil
        }
        presentation = next
        let presentationName: String
        switch next {
        case .idle:
            presentationName = "idle"
        case .listening:
            presentationName = "listening"
        case .exact:
            presentationName = "exact"
        case .confirmation:
            presentationName = "confirmation"
        case .fallbackInput:
            presentationName = "fallbackInput"
        case .clipboardFallback:
            presentationName = "clipboardFallback"
        case .sent:
            presentationName = "sent"
        case .failure:
            presentationName = "failure"
        }
        AppLogger.dictation.debug("AgentDispatchCoordinator presentation set=\(presentationName)")
        onPresentationChange?(next)
    }
}

extension AgentDispatchFailureReason {
    var userMessage: String {
        switch self {
        case .exited: return L10n.localize("agent_dispatch.error.agent_exited", comment: "")
        case .stale: return L10n.localize("agent_dispatch.error.agent_stale", comment: "")
        case .inputChannelMissing: return L10n.localize("agent_dispatch.error.agent_input_channel_missing", comment: "")
        case .ambiguous: return L10n.localize("agent_dispatch.error.agent_ambiguous", comment: "")
        case .notFound: return L10n.localize("agent_dispatch.error.agent_not_found", comment: "")
        case .writeFailed: return L10n.localize("agent_dispatch.error.write_failed", comment: "")
        }
    }
}
