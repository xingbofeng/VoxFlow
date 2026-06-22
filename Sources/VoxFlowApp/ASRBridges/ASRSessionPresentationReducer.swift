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

enum ASRErrorUserMessage {
    static func message(for error: ASRError) -> String {
        switch error.category {
        case .emptyTranscript:
            return "没有检测到有效语音，请靠近麦克风再试一次。"
        default:
            return error.message
        }
    }
}

enum RecognitionErrorRecovery: Equatable {
    case none
    case openMainWindow
    case openHistoryDetail
}

struct RecognitionErrorHUDFeedback: Equatable {
    let message: String
    let duration: TimeInterval
    let isActionable: Bool
}

enum RecognitionErrorHUDPresentation {
    static func feedback(
        for error: Error,
        recovery: RecognitionErrorRecovery
    ) -> RecognitionErrorHUDFeedback {
        if let asrError = asrError(from: error),
           asrError.category == .emptyTranscript {
            return RecognitionErrorHUDFeedback(
                message: ASRErrorUserMessage.message(for: asrError),
                duration: 2.4,
                isActionable: false
            )
        }

        let message = message(for: error, recovery: recovery)
        return RecognitionErrorHUDFeedback(
            message: message,
            duration: 8.0,
            isActionable: recovery != .none
        )
    }

    private static func message(
        for error: Error,
        recovery: RecognitionErrorRecovery
    ) -> String {
        switch recovery {
        case .openHistoryDetail:
            return "处理失败：\(error.localizedDescription)"
        case .none, .openMainWindow:
            return error.localizedDescription
        }
    }

    private static func asrError(from error: Error) -> ASRError? {
        guard let engineError = error as? ASRCoreBackedASREngineError else {
            return nil
        }

        switch engineError {
        case .failure(let asrError):
            return asrError
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
        AppLogger.general.debug("ASR session apply event=\(event)")
        guard let state = assembler.apply(event) else {
            AppLogger.general.debug("ASR session apply ignored event=\(event)")
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
            phase = .failed(message: ASRErrorUserMessage.message(for: error))
        }

        return phase
    }

    mutating func waitForFinal() -> ASRSessionPresentationPhase {
        AppLogger.general.debug("ASR session waitForFinal sessionID=\(sessionID)")
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
        AppLogger.general.debug("ASR session begin sessionID=\(sessionID)")
        activeSessionID = sessionID
        phase = .idle
        reducer = ASRSessionPresentationReducer(sessionID: sessionID)
    }

    mutating func apply(_ event: ASREvent) -> ASRSessionPresentationPhase? {
        AppLogger.general.debug("ASR router apply event session=\(event.sessionID)")
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
