import VoxFlowDomain

public enum TextInsertionStrategy: Equatable {
    case fastPaste
    case simulatedTyping
}

public struct TextInsertionStrategyResolver {
    public init() {}

    public func strategy(for mode: TextInputMode) -> TextInsertionStrategy {
        switch mode {
        case .automatic, .fastPaste:
            return .fastPaste
        case .simulatedTyping:
            return .simulatedTyping
        }
    }
}

@MainActor
public protocol TextInsertionCoordinating: AnyObject {
    @discardableResult
    func insert(_ text: String, mode: TextInputMode) async -> TextInsertionResult
}

@MainActor
public final class TextInsertionCoordinator: TextInsertionCoordinating {
    private let fastPasteInserter: any TextInserting
    private let simulatedTypingInserter: (any TextInserting)?
    private let strategyResolver: TextInsertionStrategyResolver

    public init(
        fastPasteInserter: any TextInserting,
        simulatedTypingInserter: (any TextInserting)? = nil,
        strategyResolver: TextInsertionStrategyResolver = TextInsertionStrategyResolver()
    ) {
        self.fastPasteInserter = fastPasteInserter
        self.simulatedTypingInserter = simulatedTypingInserter
        self.strategyResolver = strategyResolver
    }

    public func insert(_ text: String, mode: TextInputMode) async -> TextInsertionResult {
        switch strategyResolver.strategy(for: mode) {
        case .fastPaste:
            return await fastPasteInserter.insert(text)
        case .simulatedTyping:
            if text.containsLineBreak {
                return await fastPasteInserter.insert(text)
            }
            guard let simulatedTypingInserter else {
                return .unavailable(reason: "Simulated typing is not available yet")
            }
            return await simulatedTypingInserter.insert(text)
        }
    }
}

private extension String {
    var containsLineBreak: Bool {
        rangeOfCharacter(from: .newlines) != nil
    }
}
