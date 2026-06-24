import Foundation

enum SingleLineTextInput {
    static func removingLineBreaks(_ value: String) -> String {
        String(value.filter { !$0.isNewline })
    }

    static func normalized(_ value: String) -> String {
        removingLineBreaks(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
