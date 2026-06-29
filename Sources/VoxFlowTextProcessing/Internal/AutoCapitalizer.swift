import Foundation

/// Context-aware automatic capitalization of the first letter in natural
/// English sentences. Disabled in coding/identifier contexts to avoid
/// breaking variable names, commands, or technical identifiers.
public enum AutoCapitalizer {
    public struct Context: Sendable, Equatable {
        public let isCodingContext: Bool
        public init(isCodingContext: Bool = false) {
            self.isCodingContext = isCodingContext
        }
    }

    public static func process(_ text: String, context: Context = Context()) -> String {
        guard !context.isCodingContext else { return text }

        var lines = text.components(separatedBy: "\n")
        for i in lines.indices {
            lines[i] = capitalizeFirstEnglishLetter(in: lines[i])
        }
        return lines.joined(separator: "\n")
    }

    /// Capitalize the first English letter of a line if it starts with a
    /// lowercase English letter and the line looks like a natural sentence
    /// (not a code snippet, URL, or identifier).
    static func capitalizeFirstEnglishLetter(in line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return line }
        guard let first = trimmed.first, first.isLowercase, first.isASCII, first.isLetter else {
            return line
        }

        // Don't capitalize if the line looks like code/identifier:
        // - starts with a known code prefix
        // - contains no spaces (likely a single identifier/token)
        // - starts with / (path), http (URL), or ` (backtick)
        let lowercased = trimmed.lowercased()
        let codePrefixes = ["http://", "https://", "ftp://", "npm ", "git ", "cd ", "ls ", "sudo ", "pip ", "brew "]
        if codePrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return line
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("`") || trimmed.hasPrefix("#") {
            return line
        }
        // Single token with no space → likely identifier, skip.
        if !trimmed.contains(" ") {
            return line
        }
        // camelCase or snake_case at start → likely identifier, skip.
        if trimmed.contains("_") || (trimmed.dropFirst().contains { $0.isUppercase }) {
            // Only skip if the first word itself looks like an identifier.
            let firstWord = trimmed.components(separatedBy: " ").first ?? trimmed
            if firstWord.contains("_") || firstWord.dropFirst().contains(where: { $0.isUppercase }) {
                return line
            }
        }

        // Capitalize the first letter.
        let leadingWhitespace = line.prefix(while: { $0.isWhitespace })
        let rest = line.dropFirst(leadingWhitespace.count)
        guard let firstChar = rest.first else { return line }
        let capitalized = String(firstChar).uppercased() + String(rest.dropFirst())
        return String(leadingWhitespace) + capitalized
    }
}
