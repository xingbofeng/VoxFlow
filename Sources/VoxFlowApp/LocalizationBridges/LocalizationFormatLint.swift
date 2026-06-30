import Foundation

enum LocalizationFormatLint {
    struct Violation: Equatable {
        let line: Int
        let snippet: String
    }

    static func violations(in source: String) -> [Violation] {
        source
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { index, line in
                guard line.contains("String(format:"),
                      line.contains("L10n.localize(") else {
                    return nil
                }
                return Violation(line: index + 1, snippet: line.trimmingCharacters(in: .whitespaces))
            }
    }
}
