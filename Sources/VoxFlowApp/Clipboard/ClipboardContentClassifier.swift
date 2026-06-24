import AppKit
import Foundation

enum ClipboardContentClassifier {
    /// Adapted from Stash ContentType.swift (MIT): https://github.com/hex/Stash
    /// Priority: image > file > URL > rich text > plain text.
    static func detect(
        from types: [NSPasteboard.PasteboardType],
        plainText: String?
    ) -> AssetContentType? {
        let typeSet = Set(types)

        if typeSet.contains(.tiff) || typeSet.contains(.png) {
            return .image
        }

        if typeSet.contains(.fileURL) {
            return .file
        }

        if typeSet.contains(.URL) {
            return .link
        }

        if let plainText,
           isExactURL(plainText) {
            return .link
        }

        if typeSet.contains(.rtf) || typeSet.contains(.html) {
            return .text
        }

        if typeSet.contains(.string) {
            if let plainText,
               isExactColor(plainText) {
                return .color
            }
            return .text
        }

        return nil
    }

    static func isExactColor(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^#[0-9a-fA-F]{3}$"#,
            #"^#[0-9a-fA-F]{6}$"#,
            #"^#[0-9a-fA-F]{8}$"#,
            #"^rgba?\(\s*(?:\d{1,3}\s*,\s*){2}\d{1,3}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)$"#,
            #"^hsla?\(\s*-?\d+(?:\.\d+)?(?:deg)?\s*,\s*\d{1,3}%\s*,\s*\d{1,3}%(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)$"#,
        ]
        return patterns.contains { pattern in
            trimmed.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func isExactURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.range.location == 0,
              match.range.length == trimmed.utf16.count else {
            return false
        }
        return true
    }
}
