import Foundation

/// Inserts a space between CJK and Latin/digit characters, while protecting
/// URLs, paths, code identifiers, emails, version strings, and backtick-
/// wrapped content from being split.
///
/// Behavior is compatible with official `vinta/pangu.js` CJK-Latin spacing
/// rules for the realistic voice-input character set (Han + ASCII/Latin/Greek).
/// See `PanguCompatibilityTests.swift` for the imported official fixtures and
/// the exclusion list for upstream cases outside VoxFlow's pipe scope.
public enum CJKLatinSpacer {
    /// Non-CJK letter pattern matching any Unicode letter that is not Han.
    /// Uses ICU regex set intersection to cover Latin, Latin-1 Supplement,
    /// Latin Extended, Greek, Cyrillic, and other non-CJK scripts in one
    /// expression, matching Pangu's `cjk-alphabets-numbers` behavior for
    /// the realistic voice-input character set.
    private static let nonCJKLetterClass = "[\\p{L}&&[^\\p{Script=Han}]]"

    public static func process(_ text: String) -> String {
        var result = PanguSpacingNormalizer.process(text)
        result = preserveCompactDateAndTimeUnits(result)
        return result
    }

    struct ProtectedResult {
        let masked: String
        let regions: [ProtectedRegion]
    }

    struct ProtectedRegion: Equatable {
        let placeholder: String
        let original: String
    }

    enum ProtectedRegions {
        static func mask(_ text: String) -> ProtectedResult {
            var masked = text
            var regions: [ProtectedRegion] = []
            let patterns: [(name: String, regex: String)] = [
                ("url", #"https?://[^\s\u4e00-\u9fff]+"#),
                // Use explicit ASCII ranges instead of \w, because ICU's \w
                // matches CJK ideographs (they're alphabetic in Unicode),
                // which would consume adjacent CJK text as part of the path.
                ("path", #"(?:/[a-zA-Z0-9_.\-]+)+"#),
                ("email", #"[a-zA-Z0-9_.]+@[a-zA-Z0-9_.]+\.[a-zA-Z0-9]+"#),
                ("version", #"\d+\.\d+(?:\.\d+)*"#),
                ("backtick", #"`[^`]+`"#),
                ("identifier", #"\b[a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)+\b"#),
            ]
            for (index, pattern) in patterns.enumerated() {
                guard let regex = try? NSRegularExpression(pattern: pattern.regex) else { continue }
                let range = NSRange(masked.startIndex..<masked.endIndex, in: masked)
                let matches = regex.matches(in: masked, range: range).sorted { $0.range.location > $1.range.location }
                for match in matches {
                    guard let matchRange = Range(match.range, in: masked) else { continue }
                    let original = String(masked[matchRange])
                    // Placeholder starts and ends with ASCII letters so that
                    // CJK-Latin spacing naturally applies at protected-region
                    // boundaries. Digits are wrapped by letters to avoid
                    // interfering with CJK-digit or date-unit preservation.
                    let placeholder = "zzPR\(index)zz\(regions.count)zz"
                    regions.append(ProtectedRegion(placeholder: placeholder, original: original))
                    masked.replaceSubrange(matchRange, with: placeholder)
                }
            }
            return ProtectedResult(masked: masked, regions: regions)
        }

        static func unmask(_ text: String, regions: [ProtectedRegion]) -> String {
            var result = text
            for region in regions {
                result = result.replacingOccurrences(of: region.placeholder, with: region.original)
            }
            return result
        }
    }

    /// Insert space between CJK and Latin letters: "Hello世界" → "Hello 世界"
    /// Also handles Latin-1 Supplement and Greek letters per Pangu rules.
    static func insertSpaceBetweenCJKAndLatin(_ text: String) -> String {
        // CJK followed by non-CJK letter
        let pattern1 = "(\\p{Script=Han})(\(nonCJKLetterClass))"
        // Non-CJK letter followed by CJK
        let pattern2 = "(\(nonCJKLetterClass))(\\p{Script=Han})"

        var result = text
        if let regex = try? NSRegularExpression(pattern: pattern1) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1 $2")
        }
        if let regex = try? NSRegularExpression(pattern: pattern2) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1 $2")
        }
        return result
    }

    /// Insert space between CJK and digits: "共3个" → "共 3 个"
    static func insertSpaceBetweenCJKAndDigits(_ text: String) -> String {
        // CJK followed by digit
        let pattern1 = "(\\p{Script=Han})([0-9])"
        // Digit followed by CJK
        let pattern2 = "([0-9])(\\p{Script=Han})"

        var result = text
        if let regex = try? NSRegularExpression(pattern: pattern1) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1 $2")
        }
        if let regex = try? NSRegularExpression(pattern: pattern2) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1 $2")
        }
        return result
    }

    /// Keep date/time expressions compact after generic CJK-digit spacing:
    /// "2021 年 1 月" → "2021年1月", matching common Chinese date formatting.
    static func preserveCompactDateAndTimeUnits(_ text: String) -> String {
        let units = "年月日号点分秒"
        var result = text
        if let regex = try? NSRegularExpression(pattern: "([0-9])\\s+([\(units)])") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1$2")
        }
        if let regex = try? NSRegularExpression(pattern: "([\(units)])\\s+([0-9]+)(?![0-9/])") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1$2")
        }
        if let regex = try? NSRegularExpression(pattern: "(\\p{Script=Han})\\s+([0-9]+[\(units)])") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1$2")
        }
        return result
    }
}
