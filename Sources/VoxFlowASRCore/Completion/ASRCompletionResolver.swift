public enum ASRCompletionOutcome: Equatable, Sendable {
    case awaitingFinal(recoverablePartial: String?)
    case completed(finalText: String)
    case failed(error: ASRError, recoverablePartial: String?)
}

public struct ASRCompletionResolver: Sendable {
    public let sessionID: ASRSessionID

    private var assembler: TranscriptAssembler
    private var recoverablePartial: String?

    public init(sessionID: ASRSessionID) {
        self.sessionID = sessionID
        assembler = TranscriptAssembler(sessionID: sessionID)
    }

    @discardableResult
    public mutating func apply(_ event: ASREvent) -> ASRCompletionOutcome? {
        guard let state = assembler.apply(event) else {
            return nil
        }

        switch event {
        case .partial:
            recoverablePartial = displayText(from: state)
            return .awaitingFinal(recoverablePartial: recoverablePartial)
        case let .final(_, _, text):
            return .completed(finalText: text)
        case let .failure(_, _, error):
            return .failed(error: error, recoverablePartial: recoverablePartial)
        case .preparing,
             .ready,
             .speechStarted,
             .endpoint,
             .metrics:
            return nil
        }
    }

    private func displayText(from state: TranscriptAssemblyState) -> String? {
        let text = state.stablePrefix + state.unstableSuffix
        return text.isEmpty ? nil : text
    }
}
