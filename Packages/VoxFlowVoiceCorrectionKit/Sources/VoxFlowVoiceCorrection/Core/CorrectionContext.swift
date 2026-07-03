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
    /// Whether the ordinary-dictation refinement guard should evaluate the
    /// LLM output produced under this context. Ordinary dictation defaults to
    /// `true`. Agent paths that reuse the ordinary text pipeline as a building
    /// block (e.g. Agent Dispatch payload cleanup) explicitly opt out with
    /// `false` so the guard stays scoped to ordinary dictation.
    public let appliesDictationRefinementGuard: Bool

    public init(
        mode: CorrectionInputMode,
        providerID: String,
        modelID: String?,
        language: String?,
        bundleIdentifier: String?,
        isFinalTranscript: Bool,
        isSecureField: Bool,
        appliesDictationRefinementGuard: Bool = true
    ) {
        self.mode = mode
        self.providerID = providerID
        self.modelID = modelID
        self.language = language
        self.bundleIdentifier = bundleIdentifier
        self.isFinalTranscript = isFinalTranscript
        self.isSecureField = isSecureField
        self.appliesDictationRefinementGuard = appliesDictationRefinementGuard
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case providerID
        case modelID
        case language
        case bundleIdentifier
        case isFinalTranscript
        case isSecureField
        case appliesDictationRefinementGuard
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try c.decode(CorrectionInputMode.self, forKey: .mode)
        self.providerID = try c.decode(String.self, forKey: .providerID)
        self.modelID = try c.decodeIfPresent(String.self, forKey: .modelID)
        self.language = try c.decodeIfPresent(String.self, forKey: .language)
        self.bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        self.isFinalTranscript = try c.decodeIfPresent(Bool.self, forKey: .isFinalTranscript) ?? false
        self.isSecureField = try c.decodeIfPresent(Bool.self, forKey: .isSecureField) ?? false
        // Backward-compatible: traces persisted before the guard flag existed
        // lack this key; they default to applying the guard.
        self.appliesDictationRefinementGuard = try c.decodeIfPresent(Bool.self, forKey: .appliesDictationRefinementGuard) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(providerID, forKey: .providerID)
        try c.encodeIfPresent(modelID, forKey: .modelID)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
        try c.encode(isFinalTranscript, forKey: .isFinalTranscript)
        try c.encode(isSecureField, forKey: .isSecureField)
        try c.encode(appliesDictationRefinementGuard, forKey: .appliesDictationRefinementGuard)
    }
}
