public enum CorrectionWarning: String, Codable, Sendable, Equatable {
    case snapshotUnavailable
    case processingFailed
}

public struct CorrectionResult: Codable, Sendable, Equatable {
    public let rawText: String
    public let correctedText: String
    public let events: [CorrectionEvent]
    public let warnings: [CorrectionWarning]

    public init(
        rawText: String,
        correctedText: String,
        events: [CorrectionEvent] = [],
        warnings: [CorrectionWarning] = []
    ) {
        self.rawText = rawText
        self.correctedText = correctedText
        self.events = events
        self.warnings = warnings
    }
}
