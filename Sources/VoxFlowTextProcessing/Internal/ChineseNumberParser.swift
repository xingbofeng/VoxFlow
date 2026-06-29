import Foundation

/// Isolated Chinese numeral parser. Converts a Chinese number string to
/// Arabic digits without any sentence-level context analysis.
///
/// This type is responsible solely for parsing — given a Chinese numeral
/// string like `"十万零一"`, it returns `"100001"`. Deciding whether a
/// substring in a sentence should be treated as a number is the job of
/// `ChineseITNNormalizer`.
///
/// Behavior is compatible with applicable cases from official `Ailln/cn2an`
/// `cn2an_test.py` for digits, section units, decimals, negatives, financial
/// numerals, and colloquial quantities. See
/// `ChineseNumberParserCompatibilityTests.swift` for the imported fixtures
/// and exclusion list.
public enum ChineseNumberParser {
    /// Digit map: standard, financial (大写), and special (幺/两/〇) forms.
    private static let digitMap: [Character: String] = [
        "零": "0", "〇": "0", "一": "1", "二": "2", "两": "2", "兩": "2", "三": "3", "四": "4",
        "五": "5", "六": "6", "七": "7", "八": "8", "九": "9", "幺": "1",
        "壹": "1", "贰": "2", "貳": "2", "叁": "3", "叄": "3", "肆": "4",
        "伍": "5", "陆": "6", "陸": "6", "柒": "7", "捌": "8", "玖": "9",
    ]

    /// Multiplier (unit) map: standard and financial forms.
    private static let multiplierMap: [Character: Int] = [
        "十": 10, "拾": 10, "百": 100, "佰": 100, "千": 1000, "仟": 1000,
        "万": 10000, "萬": 10000, "亿": 100000000, "億": 100000000,
    ]

    /// Characters used in Chinese number regex patterns.
    public static let numberRegexCharacters = "负零〇一二两兩三四五六七八九十百千万萬亿億幺廿壹贰貳叁叄肆伍陆陸柒捌玖拾佰仟点"

    /// Parse a Chinese numeral string to Arabic digits.
    ///
    /// Examples:
    /// - `"三六九"` (digits only) → `"369"`
    /// - `"十二"` → `"12"`
    /// - `"一百二十"` → `"120"`
    /// - `"十万零一"` → `"100001"`
    /// - `"负三"` → `"-3"`
    /// - `"零点一四"` → `"0.14"`
    /// - `"廿二"` → `"22"`
    ///
    /// Returns nil for unparseable input.
    public static func parse(_ chinese: String) -> String? {
        if chinese.isEmpty { return nil }
        if chinese.unicodeScalars.allSatisfy({ (48...57).contains(Int($0.value)) }) { return chinese }
        if chinese == "廿" { return "20" }
        if chinese.hasPrefix("负") {
            let remainder = String(chinese.dropFirst())
            guard let parsed = parse(remainder) else { return nil }
            return "-\(parsed)"
        }
        if let dot = chinese.firstIndex(of: "点") {
            let integerPart = String(chinese[..<dot])
            let fractionalPart = String(chinese[chinese.index(after: dot)...])
            // Reject decimals without an integer part (e.g., "点零").
            guard !integerPart.isEmpty else { return nil }
            guard let integer = parse(integerPart) else { return nil }
            let fraction = fractionalPart.map { digitMap[$0] ?? String($0) }.joined()
            guard !fraction.isEmpty, fraction.allSatisfy(\.isNumber) else { return nil }
            let normalizedFraction = fraction.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            guard !normalizedFraction.isEmpty else { return integer }
            return "\(integer).\(normalizedFraction)"
        }

        // Simple digit-by-digit conversion (for sequences like "三六九" or
        // "二〇〇二" with no structural multipliers).
        if chinese.allSatisfy({ digitMap[$0] != nil }) {
            return chinese.compactMap { digitMap[$0] }.joined()
        }
        if chinese.hasPrefix("廿") {
            let suffix = String(chinese.dropFirst())
            if suffix.isEmpty { return "20" }
            guard suffix.count == 1, let digit = suffix.first.flatMap({ digitMap[$0] }) else { return nil }
            return "2\(digit)"
        }
        if startsWithImplicitLargeUnit(chinese) {
            return nil
        }
        guard let integer = parseInteger(chinese) else { return nil }
        return String(integer)
    }

    /// Parse cn2an "direct" mode: convert digit-by-digit and preserve leading
    /// zeros/trailing decimal zeros.
    public static func parseDirect(_ chinese: String) -> String? {
        if chinese.isEmpty { return nil }
        if chinese.unicodeScalars.allSatisfy({ (48...57).contains(Int($0.value)) }) {
            return chinese
        }
        if chinese.hasPrefix("负") {
            let remainder = String(chinese.dropFirst())
            guard let parsed = parseDirect(remainder) else { return nil }
            return "-\(parsed)"
        }
        if let dot = chinese.firstIndex(of: "点") {
            let integerPart = String(chinese[..<dot])
            let fractionalPart = String(chinese[chinese.index(after: dot)...])
            guard let integer = parseDirect(integerPart) else { return nil }
            let fraction = fractionalPart.map { digitMap[$0] ?? String($0) }.joined()
            guard !fraction.isEmpty, fraction.allSatisfy(\.isNumber) else { return nil }
            return "\(integer).\(fraction)"
        }
        let digits = chinese.map { digitMap[$0] ?? String($0) }.joined()
        guard digits.allSatisfy(\.isNumber) else { return nil }
        return digits
    }

    /// Parse a Chinese integer string that may contain section units (亿/万).
    private static func parseInteger(_ chinese: String) -> Int? {
        let normalized = chinese.replacingOccurrences(of: "萬", with: "万")
            .replacingOccurrences(of: "億", with: "亿")
        guard !normalized.isEmpty else { return nil }
        if let yiRange = normalized.range(of: "亿") {
            let left = String(normalized[..<yiRange.lowerBound])
            let right = String(normalized[yiRange.upperBound...])
            guard !left.isEmpty, let high = parseInteger(left) else { return nil }
            let low: Int
            if right.isEmpty {
                low = 0
            } else {
                guard let parsedLow = parseInteger(right) else { return nil }
                low = parsedLow
            }
            return high * 100_000_000 + low
        }
        if let wanRange = normalized.range(of: "万") {
            let left = String(normalized[..<wanRange.lowerBound])
            let right = String(normalized[wanRange.upperBound...])
            guard !left.isEmpty, let high = parseInteger(left) else { return nil }
            guard !right.isEmpty else { return high * 10_000 }
            // Colloquial: "三万五" → 3*10000 + 5*1000 = 35000
            if isSingleDigit(right), !right.hasPrefix("零") {
                guard let digit = right.first.flatMap({ digitMap[$0] }).flatMap(Int.init) else { return nil }
                return high * 10_000 + digit * 1_000
            }
            guard let low = parseInteger(right) else { return nil }
            return high * 10_000 + low
        }
        return parseBelowWan(normalized)
    }

    /// Parse a Chinese integer below the 万 (10,000) section.
    private static func parseBelowWan(_ chinese: String) -> Int? {
        var total = 0
        var current = 0
        var lastUnit = 1
        var zeroPending = false
        var previousWasMultiplier = false
        var consecutiveDigitCount = 0
        for char in chinese {
            if let digit = digitMap[char] {
                if digit == "0" {
                    zeroPending = true
                    consecutiveDigitCount = 0
                } else {
                    current = Int(digit) ?? 0
                    consecutiveDigitCount += 1
                }
                previousWasMultiplier = false
            } else if let mult = multiplierMap[char] {
                guard consecutiveDigitCount <= 1 else {
                    return nil
                }
                // Reject consecutive same multipliers like "十十" (invalid).
                // Different multipliers in descending order are valid, e.g.,
                // "百十" in "一百十一" (111).
                if previousWasMultiplier && mult == lastUnit {
                    return nil
                }
                if current == 0 { current = 1 }
                total += current * mult
                current = 0
                lastUnit = mult
                zeroPending = false
                previousWasMultiplier = true
                consecutiveDigitCount = 0
            } else {
                return nil
            }
        }
        if current > 0, !zeroPending {
            // Colloquial: "一百二" → 100 + 2*10 = 120
            if lastUnit == 1000 {
                current *= 100
            } else if lastUnit == 100 {
                current *= 10
            }
        }
        total += current
        return total
    }

    private static func isSingleDigit(_ value: String) -> Bool {
        value.count == 1 && value.first.map { digitMap[$0] != nil } == true
    }

    private static func startsWithImplicitLargeUnit(_ value: String) -> Bool {
        guard let first = value.first else { return false }
        return ["百", "佰", "千", "仟", "万", "萬", "亿", "億"].contains(first)
    }

    /// Convert a single Chinese digit character to its Arabic string form.
    /// Useful for quantity patterns like "三个" → "3个".
    public static func digitToArabic(_ ch: Character) -> String? {
        digitMap[ch]
    }
}
