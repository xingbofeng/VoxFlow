import Foundation

@MainActor
public final class ChineseInputSession {
    public private(set) var state: ChineseInputState
    public private(set) var isStarted = false
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
        self.bridge = bridge
    }

    public func start(hasFullAccess: Bool) async throws {
        try await bridge.start(hasFullAccess: hasFullAccess)
        isStarted = true
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

    @discardableResult
    public func deleteBackward() async throws -> ChineseInputAction {
        guard state.hasActiveComposition else {
            return .deleteHostText
        }
        let next = try await bridge.deleteBackward()
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
