import Foundation

public enum ChineseInputMode: String, CaseIterable, Equatable, Sendable {
    case chineseQwerty
    case chineseNineGrid
    case english
    case symbols
    case voice

    public var isChinese: Bool {
        switch self {
        case .chineseQwerty, .chineseNineGrid:
            return true
        case .english, .symbols, .voice:
            return false
        }
    }
}

public enum ChineseNineGridKey: Equatable, Sendable {
    case input(label: String, digit: String?)
    case backspace
    case clearComposition
    case returnKey
    case symbols
    case numbers
    case space
    case emoji
    case switchLanguage
    case send

    public var displayLabel: String {
        switch self {
        case let .input(label, _):
            return label
        case .backspace:
            return "delete"
        case .clearComposition:
            return "clear"
        case .returnKey:
            return "return"
        case .symbols:
            return "symbols"
        case .numbers:
            return "123"
        case .space:
            return "space"
        case .emoji:
            return "emoji"
        case .switchLanguage:
            return "switchLanguage"
        case .send:
            return "send"
        }
    }

    public var inputDigit: String? {
        switch self {
        case let .input(_, digit):
            return digit
        default:
            return nil
        }
    }
}

public enum ChineseNineGridLayout {
    /// Copied from Hamster's ChineseNineGridLayoutProvider action rows, expressed
    /// as a brand-neutral layout model for the Dictus shell integration.
    public static let rows: [[ChineseNineGridKey]] = [
        [.symbols, .input(label: "ABC", digit: "2"), .input(label: "DEF", digit: "3"), .backspace],
        [.input(label: "GHI", digit: "4"), .input(label: "JKL", digit: "5"), .input(label: "MNO", digit: "6"), .returnKey],
        [.input(label: "PQRS", digit: "7"), .input(label: "TUV", digit: "8"), .input(label: "WXYZ", digit: "9"), .emoji],
        [.numbers, .space, .switchLanguage, .send],
    ]
}
