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

/// Lifecycle status of the Chinese input bridge.
///
/// WHY a dedicated status (not just `isStarted`): the extension needs to
/// distinguish three distinct situations — the bridge is warming up (Rime
/// deploy can take a moment), it is ready, or it failed to deploy. A failed
/// bridge must route all key input straight to raw host text so the keyboard
/// stays usable instead of swallowing typed keys.
public enum ChineseInputStatus: Equatable, Sendable {
    case idle
    case starting
    case ready
    case failed
}

@MainActor
public protocol ChineseRimeBridge {
    var state: ChineseCompositionState { get }
    var status: ChineseInputStatus { get }
    func start(hasFullAccess: Bool) async throws
    func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState
    func input(_ text: String) async throws -> ChineseCompositionState
    func selectCandidate(at index: Int) async throws -> ChineseCompositionState
    func deleteBackward() async throws -> ChineseCompositionState
    func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion]
    func replacePreeditInput(_ replacement: String) async throws -> ChineseCompositionState
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
