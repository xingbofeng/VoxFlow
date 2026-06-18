public struct TranscriptAssemblyState: Equatable, Sendable {
    public var stablePrefix: String
    public var unstableSuffix: String
    public var revision: UInt64
    public var finalText: String?

    public init(
        stablePrefix: String = "",
        unstableSuffix: String = "",
        revision: UInt64 = 0,
        finalText: String? = nil
    ) {
        self.stablePrefix = stablePrefix
        self.unstableSuffix = unstableSuffix
        self.revision = revision
        self.finalText = finalText
    }
}

public struct TranscriptAssembler: Sendable {
    public let sessionID: ASRSessionID
    public private(set) var state = TranscriptAssemblyState()

    private var latestRevision: UInt64?

    public init(sessionID: ASRSessionID) {
        self.sessionID = sessionID
    }

    @discardableResult
    public mutating func apply(_ event: ASREvent) -> TranscriptAssemblyState? {
        guard event.sessionID == sessionID,
              shouldAccept(revision: event.revision) else {
            return nil
        }

        latestRevision = event.revision
        state.revision = event.revision

        switch event {
        case let .partial(_, transcript):
            apply(transcript)
        case let .final(_, _, text):
            state.stablePrefix = text
            state.unstableSuffix = ""
            state.finalText = text
        case .preparing,
             .ready,
             .speechStarted,
             .endpoint,
             .metrics,
             .failure:
            break
        }

        return state
    }

    private func shouldAccept(revision: UInt64) -> Bool {
        guard let latestRevision else { return true }
        return revision > latestRevision
    }

    private mutating func apply(_ transcript: PartialTranscript) {
        state.finalText = nil

        if transcript.stablePrefix.hasPrefix(state.stablePrefix) {
            state.stablePrefix = transcript.stablePrefix
            state.unstableSuffix = transcript.unstableSuffix
            return
        }

        let incomingText = transcript.stablePrefix + transcript.unstableSuffix
        if incomingText.hasPrefix(state.stablePrefix) {
            let suffixStart = incomingText.index(
                incomingText.startIndex,
                offsetBy: state.stablePrefix.count
            )
            state.unstableSuffix = String(incomingText[suffixStart...])
        } else {
            state.unstableSuffix = incomingText
        }
    }
}
