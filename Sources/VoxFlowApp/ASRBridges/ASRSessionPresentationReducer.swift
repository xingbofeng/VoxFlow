import Foundation
import VoxFlowASRCore

enum ASRSessionPresentationPhase: Equatable {
    case idle
    case preparing
    case recognizing(text: String)
    case waitingForFinal(text: String)
    case completed(text: String)
    case failed(message: String)

    var visibleText: String {
        switch self {
        case .idle, .preparing:
            return ""
        case .recognizing(let text),
             .waitingForFinal(let text),
             .completed(let text):
            return text
        case .failed(let message):
            return message
        }
    }
}

struct ASRSessionPresentationReducer {
    let sessionID: ASRSessionID
    private(set) var phase: ASRSessionPresentationPhase = .idle

    private var assembler: TranscriptAssembler

    init(sessionID: ASRSessionID) {
        self.sessionID = sessionID
        assembler = TranscriptAssembler(sessionID: sessionID)
    }

    mutating func apply(_ event: ASREvent) -> ASRSessionPresentationPhase? {
        guard let state = assembler.apply(event) else {
            return nil
        }

        switch event {
        case .preparing:
            phase = .preparing
        case .ready, .speechStarted:
            phase = .recognizing(text: displayText(from: state))
        case .partial:
            phase = .recognizing(text: displayText(from: state))
        case .endpoint:
            phase = .waitingForFinal(text: displayText(from: state))
        case let .final(_, _, text):
            phase = .completed(text: text)
        case .metrics:
            return nil
        case let .failure(_, _, error):
            phase = .failed(message: error.message)
        }

        return phase
    }

    mutating func waitForFinal() -> ASRSessionPresentationPhase {
        phase = .waitingForFinal(text: phase.visibleText)
        return phase
    }

    private func displayText(from state: TranscriptAssemblyState) -> String {
        state.finalText ?? state.stablePrefix + state.unstableSuffix
    }
}

struct ASRSessionPresentationRouter {
    private(set) var activeSessionID: ASRSessionID?
    private(set) var phase: ASRSessionPresentationPhase = .idle

    private var reducer: ASRSessionPresentationReducer?

    mutating func beginSession(_ sessionID: ASRSessionID) {
        activeSessionID = sessionID
        phase = .idle
        reducer = ASRSessionPresentationReducer(sessionID: sessionID)
    }

    mutating func apply(_ event: ASREvent) -> ASRSessionPresentationPhase? {
        guard event.sessionID == activeSessionID,
              var activeReducer = reducer,
              let nextPhase = activeReducer.apply(event) else {
            return nil
        }

        reducer = activeReducer
        phase = nextPhase
        return nextPhase
    }
}
