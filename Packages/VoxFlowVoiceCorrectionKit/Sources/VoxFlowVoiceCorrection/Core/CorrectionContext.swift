public enum CorrectionInputMode: String, Codable, Sendable, CaseIterable {
    case dictation
    case command
    case translation
}

public struct CorrectionContext: Codable, Sendable, Equatable {
    public let mode: CorrectionInputMode
    public let providerID: String
    public let modelID: String?
    public let language: String?
    public let bundleIdentifier: String?
    public let isFinalTranscript: Bool
    public let isSecureField: Bool

    public init(
        mode: CorrectionInputMode,
        providerID: String,
        modelID: String?,
        language: String?,
        bundleIdentifier: String?,
        isFinalTranscript: Bool,
        isSecureField: Bool
    ) {
        self.mode = mode
        self.providerID = providerID
        self.modelID = modelID
        self.language = language
        self.bundleIdentifier = bundleIdentifier
        self.isFinalTranscript = isFinalTranscript
        self.isSecureField = isSecureField
    }
}
