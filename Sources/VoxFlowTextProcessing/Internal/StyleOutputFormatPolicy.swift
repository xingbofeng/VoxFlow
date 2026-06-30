import Foundation

public enum StylePunctuationPolicy: String, Codable, Sendable, Equatable {
    case complete
    case less
    case noEnding
    case preserve
}

public enum StyleCapitalizationPolicy: String, Codable, Sendable, Equatable {
    case normal
    case relaxed
    case preserve
}

public struct StyleOutputFormatPolicy: Codable, Sendable, Equatable {
    public let punctuation: StylePunctuationPolicy?
    public let capitalization: StyleCapitalizationPolicy?

    public init(
        punctuation: StylePunctuationPolicy? = nil,
        capitalization: StyleCapitalizationPolicy? = nil
    ) {
        self.punctuation = punctuation
        self.capitalization = capitalization
    }

    public var isEmpty: Bool {
        punctuation == nil && capitalization == nil
    }
}

public enum StyleOutputFormatter {
    public static func process(
        _ text: String,
        policy: StyleOutputFormatPolicy
    ) -> String {
        guard !policy.isEmpty else { return text }
        var result = text
        if policy.punctuation == .noEnding {
            result = removeOrdinaryEndingPunctuation(result)
        }
        return result
    }

    static func removeOrdinaryEndingPunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let protected = CJKLatinSpacer.ProtectedRegions.mask(text)
        var masked = protected.masked
        var trailingWhitespace = ""
        while let last = masked.last, last.isWhitespace {
            trailingWhitespace.insert(last, at: trailingWhitespace.startIndex)
            masked.removeLast()
        }
        guard let last = masked.last else { return text }
        guard isOrdinaryFullStop(last) else { return text }
        masked.removeLast()
        return CJKLatinSpacer.ProtectedRegions.unmask(masked, regions: protected.regions) + trailingWhitespace
    }

    private static func isOrdinaryFullStop(_ character: Character) -> Bool {
        character == "。" || character == "."
    }
}
