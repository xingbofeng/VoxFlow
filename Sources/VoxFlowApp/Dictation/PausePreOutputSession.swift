import Foundation

struct PausePreOutputConfiguration: Equatable {
    let silenceThresholdNanoseconds: UInt64
    let minimumSegmentCharacterCount: Int

    init(
        silenceThresholdNanoseconds: UInt64,
        minimumSegmentCharacterCount: Int
    ) {
        precondition(silenceThresholdNanoseconds > 0, "Silence threshold must be positive.")
        precondition(minimumSegmentCharacterCount > 0, "Minimum segment character count must be positive.")
        self.silenceThresholdNanoseconds = silenceThresholdNanoseconds
        self.minimumSegmentCharacterCount = minimumSegmentCharacterCount
    }
}

enum PausePreOutputDelta: Equatable {
    case text(String)
    case noDelta
    case revised
}

/// Tracks the text watermark of the current dictation utterance and derives
/// the un-delivered segment delta for pause pre-output.
///
/// Engines report cumulative full text (Apple Speech) or full session text at
/// finish (ASRCore-backed providers), so the delta is computed here against
/// the prefix that has already been delivered to the target app. Once an
/// engine revision overlaps the delivered prefix the session is permanently
/// broken and callers must fall back to the regular full-utterance flow.
struct PausePreOutputSession {
    private let configuration: PausePreOutputConfiguration
    private var deliveredPrefix = ""
    private var lastClaim: (start: String, end: String)?
    private(set) var isBroken = false

    init(configuration: PausePreOutputConfiguration) {
        self.configuration = configuration
    }

    /// Rolls back the watermark after a failed or cancelled segment delivery,
    /// so the text is retried by the regular release path instead of being lost.
    mutating func rollbackDelivery(of segmentText: String) {
        guard let lastClaim,
              lastClaim.end == segmentText else {
            return
        }
        deliveredPrefix = lastClaim.start
        self.lastClaim = nil
    }

    /// Returns the text segment beyond the delivered watermark.
    ///
    /// - Parameters:
    ///   - cumulativeText: Latest cumulative transcript reported by the engine.
    ///   - enforcingMinimumCharacterCount: When `false` the minimum segment
    ///     length is ignored, used for flushing the tail at release time.
    mutating func takeDelta(
        from cumulativeText: String,
        enforcingMinimumCharacterCount: Bool
    ) -> PausePreOutputDelta {
        guard !isBroken else { return .revised }

        let text = cumulativeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.hasPrefix(deliveredPrefix) else {
            // Empty text or a revision overlapping the delivered prefix: the
            // already-inserted segment can no longer be reconciled.
            if !deliveredPrefix.isEmpty {
                isBroken = true
                return .revised
            }
            return .noDelta
        }

        let delta = String(text.dropFirst(deliveredPrefix.count))
        let content = delta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return .noDelta }
        if enforcingMinimumCharacterCount,
           content.count < configuration.minimumSegmentCharacterCount {
            return .noDelta
        }

        lastClaim = (start: deliveredPrefix, end: text)
        deliveredPrefix = text
        return .text(delta)
    }
}
