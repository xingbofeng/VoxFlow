import Foundation

/// Maximum number of candidates the UI will surface for a single composition.
/// Rime's default page already bounds the list; this is a final guard against a
/// pathological schema returning thousands of entries and stalling the keyboard.
public let chineseCandidateWindowSize = 100
public let chineseCandidatePageSize = 20

@MainActor
public final class ChineseInputSession {
    public private(set) var state: ChineseInputState
    public private(set) var isStarted = false
    public private(set) var status: ChineseInputStatus = .idle
    private let bridge: ChineseRimeBridge

    public init(
        mode: ChineseInputMode = .chineseQwerty,
        bridge: ChineseRimeBridge,
        voicePolicy: ChineseInputCompositionPolicy = .commitBeforeVoice
    ) {
        self.state = ChineseInputState(
            mode: mode,
            composition: bridge.state,
            voicePolicy: voicePolicy
        )
        self.status = bridge.status
        self.bridge = bridge
    }

    public func start(hasFullAccess: Bool) async throws {
        status = .starting
        do {
            try await bridge.start(hasFullAccess: hasFullAccess)
        } catch {
            status = .failed
            isStarted = false
            throw error
        }
        isStarted = true
        status = .ready
        updateComposition(bridge.state)
    }

    @discardableResult
    public func switchMode(_ mode: ChineseInputMode) async throws -> ChineseInputAction {
        state.mode = mode
        if !mode.isChinese {
            await bridge.reset()
            updateComposition(.init())
        } else {
            let next = try await bridge.switchMode(mode)
            updateComposition(next)
        }
        return .updateComposition(state.composition)
    }

    @discardableResult
    public func input(_ text: String) async throws -> ChineseInputAction {
        let next = try await bridge.input(text)
        return action(for: next)
    }

    @discardableResult
    public func selectCandidate(at index: Int) async throws -> ChineseInputAction {
        let next = try await bridge.selectCandidate(at: index)
        return action(for: next)
    }

    @discardableResult
    public func commitBestCandidateOrPreedit() async -> ChineseInputAction {
        guard state.hasActiveComposition else {
            return .none
        }

        let text = state.composition.commitText
            ?? state.composition.candidates.first?.text
            ?? state.composition.preedit
        await bridge.reset()
        updateComposition(.init())
        if !text.isEmpty {
            return .commitText(text)
        }
        return .updateComposition(state.composition)
    }

    /// The capped candidate window the UI should render for the current composition.
    /// The bridge may return more candidates than is safe to lay out at once; this
    /// keeps the keyboard responsive and matches Rime's own paging model.
    public var visibleCandidates: [CandidateSuggestion] {
        Array(state.composition.candidates.prefix(chineseCandidateWindowSize))
    }

    @discardableResult
    public func deleteBackward() async throws -> ChineseInputAction {
        guard state.hasActiveComposition else {
            return .deleteHostText
        }
        let next = try await bridge.deleteBackward()
        return action(for: next)
    }

    @discardableResult
    public func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion] {
        try await bridge.pageCandidates(from: offset, count: count)
    }

    @discardableResult
    public func loadMoreCandidates() async throws -> ChineseInputAction {
        let loadedCount = state.composition.candidates.count
        guard state.composition.hasMoreCandidates,
              loadedCount < chineseCandidateWindowSize else {
            state.composition.hasMoreCandidates = false
            return .updateComposition(state.composition)
        }

        let limit = min(chineseCandidatePageSize, chineseCandidateWindowSize - loadedCount)
        var next = try await bridge.loadMoreCandidates(limit: limit)
        if next.candidates.count > chineseCandidateWindowSize {
            next.candidates = Array(next.candidates.prefix(chineseCandidateWindowSize))
        }
        if next.candidates.count >= chineseCandidateWindowSize {
            next.hasMoreCandidates = false
        }
        updateComposition(next)
        return .updateComposition(next)
    }

    @discardableResult
    public func replacePreeditInput(_ replacement: String) async throws -> ChineseInputAction {
        let next = try await bridge.replacePreeditInput(replacement)
        return action(for: next)
    }

    @discardableResult
    public func selectPinyinCandidate(_ candidate: String) async throws -> ChineseInputAction {
        let next = try await bridge.selectPinyinCandidate(candidate)
        return action(for: next)
    }

    @discardableResult
    public func clearComposition() async -> ChineseInputAction {
        await bridge.reset()
        updateComposition(.init())
        return .updateComposition(state.composition)
    }

    @discardableResult
    public func prepareForVoice() async -> ChineseInputAction {
        guard state.hasActiveComposition else {
            return .none
        }

        switch state.voicePolicy {
        case .commitBeforeVoice:
            let text = state.composition.commitText
                ?? state.composition.candidates.first?.text
            await bridge.reset()
            updateComposition(.init())
            if let text, !text.isEmpty {
                return .commitText(text)
            }
            return .updateComposition(state.composition)

        case .clearBeforeVoice:
            await bridge.reset()
            updateComposition(.init())
            return .updateComposition(state.composition)

        case .preserveBeforeVoice:
            return .updateComposition(state.composition)
        }
    }

    private func action(for composition: ChineseCompositionState) -> ChineseInputAction {
        updateComposition(composition)
        if let text = composition.commitText, !text.isEmpty {
            updateComposition(.init())
            return .commitText(text)
        }
        return .updateComposition(composition)
    }

    private func updateComposition(_ composition: ChineseCompositionState) {
        state.composition = composition
    }
}

public enum ChineseInputAction: Equatable {
    case none
    case updateComposition(ChineseCompositionState)
    case commitText(String)
    case deleteHostText
}
