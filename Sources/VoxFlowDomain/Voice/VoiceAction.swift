public enum VoiceAction: String, Codable, Equatable, CaseIterable, Sendable {
    case dictation
    case agentCompose
    case agentDispatch
    /// Spoken instruction applied to the text already in the focused input
    /// area: record an instruction, rewrite the existing text, replace it.
    case command
}
