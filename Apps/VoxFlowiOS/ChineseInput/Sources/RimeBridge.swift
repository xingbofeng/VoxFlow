import Foundation

public struct ChineseCompositionState: Equatable {
    public var preedit: String
    public var candidates: [CandidateSuggestion]
    public var commitText: String?

    public init(preedit: String = "", candidates: [CandidateSuggestion] = [], commitText: String? = nil) {
        self.preedit = preedit
        self.candidates = candidates
        self.commitText = commitText
    }
}

@MainActor
public protocol ChineseRimeBridge {
    var state: ChineseCompositionState { get }
    func start(hasFullAccess: Bool) async throws
    func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState
    func input(_ text: String) async throws -> ChineseCompositionState
    func selectCandidate(at index: Int) async throws -> ChineseCompositionState
    func deleteBackward() async throws -> ChineseCompositionState
    func reset() async
}

public enum ChineseInputCompositionPolicy: Equatable, Sendable {
    case commitBeforeVoice
    case clearBeforeVoice
    case preserveBeforeVoice
}

public struct ChineseInputState: Equatable {
    public var mode: ChineseInputMode
    public var composition: ChineseCompositionState
    public var voicePolicy: ChineseInputCompositionPolicy

    public init(
        mode: ChineseInputMode = .chineseQwerty,
        composition: ChineseCompositionState = .init(),
        voicePolicy: ChineseInputCompositionPolicy = .commitBeforeVoice
    ) {
        self.mode = mode
        self.composition = composition
        self.voicePolicy = voicePolicy
    }

    public var hasActiveComposition: Bool {
        !composition.preedit.isEmpty || !composition.candidates.isEmpty
    }
}
