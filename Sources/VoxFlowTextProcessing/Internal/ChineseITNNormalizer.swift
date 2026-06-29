import Foundation

/// Chinese Inverse Text Normalization (ITN) normalizer.
///
/// Identifies safe contexts in text — percentages, fractions, times, dates,
/// temperatures, quantities — and converts Chinese numerals to Arabic digits
/// by delegating actual parsing to `ChineseNumberParser`.
///
/// This separation mirrors the design used by mature TN/ITN libraries:
/// parsing a number is not the same as deciding whether text in a sentence
/// should be treated as a number. The normalizer applies conservative
/// context rules to avoid converting idioms and fixed phrases.
///
/// Behavior is compatible with applicable cases from official
/// `wenet-e2e/WeTextProcessing` Chinese ITN test data for percentages,
/// fractions, dates, times, temperatures, and measures. See
/// `ChineseITNCompatibilityTests.swift` for the imported fixtures and
/// exclusion list.
public enum ChineseITNNormalizer {
    /// Characters that indicate a Chinese number is in a numeric context
    /// (measure words, units, suffixes).
    private static let numericContextSuffixes = Set("个次条步骤份天年月日位种名篇段轮组批行列秒小时分钟元块毛两点号岁倍层页章节场人公里米斤克%Kk")

    // MARK: - Public entry point

    /// Normalize Chinese ITN patterns in text.
    ///
    /// Order matters: structured ITN patterns (percent, fraction, time,
    /// temperature) must run BEFORE broad explicit number conversion,
    /// Otherwise patterns like "十六分之三" can be partially converted
    /// into "十6分之三" before the fraction rule sees it.
    ///
    /// Percent and fraction run BEFORE time so that `百分之二点一五` is
    /// handled by the percent rule (not the time rule matching `二点一五`).
    public static func normalize(_ text: String) -> String {
        var result = text
        result = convertNegativeTemperature(result)
        result = convertPercentAndRatio(result)
        result = convertDateAndTimePatterns(result)
        result = convertExplicitNumberPatterns(result)
        result = convertQuantityPatterns(result)
        result = convertYaoToDigit(result)
        return result
    }

    // MARK: - Pattern rules

    /// Convert "零下四摄氏度" → "-4摄氏度" (negative temperature before unit).
    static func convertNegativeTemperature(_ text: String) -> String {
        let number = "[\(ChineseNumberParser.numberRegexCharacters)]+"
        let pattern = "零下(\(number))(?=摄氏度|度)"
        guard let regex = cachedRegex(pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return manualReplace(text, regex: regex, range: range) { match, nsText in
            let num = nsText.substring(with: match.range(at: 1))
            guard let arabic = ChineseNumberParser.parse(num) else {
                return nsText.substring(with: match.range)
            }
            return "-\(arabic)"
        }
    }

    /// Convert time patterns:
    /// - "八点半" → "8:30"
    /// - "五点零二分" → "5:02"
    /// - "十三点十分三十六秒" → "13:10:36"
    /// - "十二点" → "12点"
    ///
    /// The bare `X点Y` pattern (without 分/秒 suffix) is intentionally
    /// NOT matched because it conflicts with decimal numbers like
    /// `一点一一` (1.11) and `三点一四一五九二六` (3.1415926). Only
    /// patterns with explicit time suffixes (半, 分, 秒) are converted.
    static func convertDateAndTimePatterns(_ text: String) -> String {
        var result = text
        let number = "[\(ChineseNumberParser.numberRegexCharacters)]+"

        // "八点半" → "8:30"
        if let regex = cachedRegex("(\(number))点半") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = manualReplace(result, regex: regex, range: range) { match, nsText in
                let hour = nsText.substring(with: match.range(at: 1))
                guard let parsedHour = ChineseNumberParser.parse(hour) else {
                    return nsText.substring(with: match.range)
                }
                return "\(parsedHour):30"
            }
        }

        // "五点零二分" → "5:02", "十三点十分三十六秒" → "13:10:36"
        if let regex = cachedRegex("(\(number))点(\(number))分(?:(\(number))秒)?") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = manualReplace(result, regex: regex, range: range) { match, nsText in
                let hour = nsText.substring(with: match.range(at: 1))
                let minute = nsText.substring(with: match.range(at: 2))
                let secondRange = match.range(at: 3)
                guard let parsedHour = ChineseNumberParser.parse(hour),
                      let parsedMinute = ChineseNumberParser.parse(minute),
                      let minuteValue = Int(parsedMinute) else {
                    return nsText.substring(with: match.range)
                }
                var output = "\(formatHour(parsedHour, source: hour)):\(String(format: "%02d", minuteValue))"
                if secondRange.location != NSNotFound,
                   let parsedSecond = ChineseNumberParser.parse(nsText.substring(with: secondRange)),
                   let secondValue = Int(parsedSecond) {
                    output += ":\(String(format: "%02d", secondValue))"
                }
                return output
            }
        }

        // "八点三十" → "8:30", "八点五" → "8:05"
        // Matches `X点Y` without 分/秒 suffix. The hour pattern excludes 点
        // (which is in numberRegexCharacters for decimals) to prevent it
        // from greedily consuming the separator. The callback rejects Y if
        // it looks like a decimal fraction (multi-digit, no multiplier like
        // 十/百) to avoid converting "一点一一" (1.11) to a time.
        let nonPointChars = ChineseNumberParser.numberRegexCharacters.replacingOccurrences(of: "点", with: "")
        let hourPattern = "[\(nonPointChars)]+"
        let minutePattern = "[\(ChineseNumberParser.numberRegexCharacters)]+"
        let bareTimePattern = "(\(hourPattern))点(\(minutePattern))(?![\(ChineseNumberParser.numberRegexCharacters)])"
        if let regex = cachedRegex(bareTimePattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = manualReplace(result, regex: regex, range: range) { match, nsText in
                let hour = nsText.substring(with: match.range(at: 1))
                let minute = nsText.substring(with: match.range(at: 2))
                guard let parsedHour = ChineseNumberParser.parse(hour),
                      let parsedMinute = ChineseNumberParser.parse(minute),
                      let minuteValue = Int(parsedMinute),
                      minuteValue >= 0 && minuteValue <= 59 else {
                    return nsText.substring(with: match.range)
                }
                // Reject decimal-like minutes: multi-digit sequences without
                // a multiplier (十/百/千/拾/佰/仟). E.g., "一一" → 11 looks like
                // a decimal fraction, not a time. "三十" → 30 has 十 multiplier.
                let multiplierChars: Set<Character> = ["十", "拾", "百", "佰", "千", "仟"]
                let hasMultiplier = minute.contains { multiplierChars.contains($0) }
                let isSingleChar = minute.count == 1
                if !hasMultiplier && !isSingleChar {
                    return nsText.substring(with: match.range)
                }
                // Reject hour=0 in bare X点Y pattern: `零点六` is always the
                // decimal 0.6, not time 0:06. Valid midnight times use the
                // explicit `X点Y分` pattern (e.g., `零点十分` → 00:10).
                if let hourValue = Int(parsedHour), hourValue == 0 {
                    return nsText.substring(with: match.range)
                }
                return "\(parsedHour):\(String(format: "%02d", minuteValue))"
            }
        }

        // "十二点" → "12点" — hour-only pattern where 点 is NOT followed by
        // a number character. This converts the hour but keeps 点 as-is.
        // The negative lookahead prevents matching decimals like "一点一四".
        let hourOnlyNonPoint = ChineseNumberParser.numberRegexCharacters.replacingOccurrences(of: "点", with: "")
        let hourOnlyPattern = "([\(hourOnlyNonPoint)]+)点(?![\(ChineseNumberParser.numberRegexCharacters)])"
        if let regex = cachedRegex(hourOnlyPattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = manualReplace(result, regex: regex, range: range) { match, nsText in
                let num = nsText.substring(with: match.range(at: 1))
                if let arabic = ChineseNumberParser.parse(num) {
                    return "\(arabic)点"
                }
                return nsText.substring(with: match.range)
            }
        }
        return result
    }

    /// Convert "百分之三十" → "30%", "十六分之三" → "3/16".
    /// Must run before broad number conversion.
    static func convertPercentAndRatio(_ text: String) -> String {
        var result = text
        let number = "[\(ChineseNumberParser.numberRegexCharacters)]+"

        // "百分之三十" / "百分三十" → "30%"
        let percentPattern = "百分之?(\(number))"
        if let regex = cachedRegex(percentPattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = manualReplace(result, regex: regex, range: range) { match, nsText in
                let groupRange = match.range(at: 1)
                let num = nsText.substring(with: groupRange)
                if let arabic = parsePercentNumber(num) {
                    return arabic + "%"
                }
                return nsText.substring(with: match.range)
            }
        }

        // "十六分之三" → "3/16", "负十二分之七" → "-7/12"
        // `负` before the fraction makes the whole fraction negative.
        // The denominator excludes 负 so it can't absorb the negative sign.
        let nonNegNumber = "[\(ChineseNumberParser.numberRegexCharacters.replacingOccurrences(of: "负", with: ""))]+"
        let ratioPattern = "(负?)(\(nonNegNumber))分之(\(number))"
        if let regex = cachedRegex(ratioPattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = manualReplace(result, regex: regex, range: range) { match, nsText in
                let signRange = match.range(at: 1)
                let denomRange = match.range(at: 2)
                let numerRange = match.range(at: 3)
                let sign = signRange.length > 0 ? "-" : ""
                let denom = nsText.substring(with: denomRange)
                let numer = nsText.substring(with: numerRange)
                if let d = ChineseNumberParser.parse(denom), let n = ChineseNumberParser.parse(numer) {
                    return "\(sign)\(n)/\(d)"
                }
                return nsText.substring(with: match.range)
            }
        }
        return result
    }

    /// Convert standalone Chinese number sequences in clear numeric contexts:
    /// counters ("三秒"), units ("十K"), ordinals ("第一场"), and structured
    /// values ("一百二", "十万零一"). Idiom-like sequences are skipped.
    static func convertExplicitNumberPatterns(_ text: String) -> String {
        let chars = ChineseNumberParser.numberRegexCharacters
        let pattern = "(?<![\(chars)])[\(chars)]+(?![\(chars)])"
        guard let regex = cachedRegex(pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString

        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: range) {
            let prefixRange = NSRange(location: cursor, length: match.range.location - cursor)
            output += nsText.substring(with: prefixRange)
            let chineseNum = nsText.substring(with: match.range)
            if let mixedSuffix = mixedLargeUnitOutput(chineseNum, in: text, range: match.range) {
                output += mixedSuffix
            } else if let unitSuffix = trailingUnitOutput(chineseNum, unit: "两"),
                      shouldConvertExplicitNumber(chineseNum, in: text, range: match.range) {
                output += unitSuffix
            } else if shouldConvertExplicitNumber(chineseNum, in: text, range: match.range),
               let arabic = ChineseNumberParser.parse(chineseNum) {
                output += arabic
            } else {
                output += chineseNum
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            let suffixRange = NSRange(location: cursor, length: nsText.length - cursor)
            output += nsText.substring(with: suffixRange)
        }
        return output
    }

    /// Convert "三个" → "3个", "五次" → "5次" — single digit + measure word.
    static func convertQuantityPatterns(_ text: String) -> String {
        let measureWords = "个次条步骤份天年月位种名篇段轮组批行列秒小时分钟元块毛两万亿"
        let result = text
        let fullPattern = "([二三四五六七八九])([\(measureWords)])"
        guard let regex2 = cachedRegex(fullPattern) else { return text }
        let range2 = NSRange(result.startIndex..<result.endIndex, in: result)
        let nsResult = result as NSString
        var output = ""
        var cursor = 0
        for match in regex2.matches(in: result, range: range2) {
            let prefixRange = NSRange(location: cursor, length: match.range.location - cursor)
            output += nsResult.substring(with: prefixRange)
            let digitStr = nsResult.substring(with: NSRange(location: match.range.location, length: 1))
            let measureStr = nsResult.substring(with: NSRange(location: match.range.location + 1, length: 1))
            if let digit = ChineseNumberParser.digitToArabic(Character(digitStr)) {
                output += digit + measureStr
            } else {
                output += digitStr + measureStr
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < nsResult.length {
            let suffixRange = NSRange(location: cursor, length: nsResult.length - cursor)
            output += nsResult.substring(with: suffixRange)
        }
        // Also handle 一+measureWord conservatively.
        let onePattern = "(一)([\(measureWords)])"
        if let oneRegex = cachedRegex(onePattern) {
            let oneRange = NSRange(output.startIndex..<output.endIndex, in: output)
            let nsOutput = output as NSString
            var finalOutput = ""
            var finalCursor = 0
            for match in oneRegex.matches(in: output, range: oneRange) {
                let prefixRange = NSRange(location: finalCursor, length: match.range.location - finalCursor)
                finalOutput += nsOutput.substring(with: prefixRange)
                finalOutput += "1" + nsOutput.substring(with: NSRange(location: match.range.location + 1, length: 1))
                finalCursor = match.range.location + match.range.length
            }
            if finalCursor < nsOutput.length {
                let suffixRange = NSRange(location: finalCursor, length: nsOutput.length - finalCursor)
                finalOutput += nsOutput.substring(with: suffixRange)
            }
            output = finalCursor > 0 ? finalOutput : output
        }
        return output
    }

    /// Convert "幺" to "1" in digit sequences: "幺九二" → "192".
    static func convertYaoToDigit(_ text: String) -> String {
        let pattern = "幺([零一二三四五六七八九]+)"
        guard let regex = cachedRegex(pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return manualReplace(text, regex: regex, range: range) { match, nsText in
            let groupRange = match.range(at: 1)
            let num = nsText.substring(with: groupRange)
            if let arabic = ChineseNumberParser.parse(num) {
                return "1" + arabic
            }
            return nsText.substring(with: match.range)
        }
    }

    // MARK: - Context guard

    private static func shouldConvertExplicitNumber(
        _ chineseNum: String,
        in text: String,
        range nsRange: NSRange
    ) -> Bool {
        if chineseNum.contains("十十") {
            return false
        }
        if chineseNum.contains("幺") { return true }
        // Decimals (contains 点) are unambiguously numeric — always convert.
        if chineseNum.contains("点") { return true }
        guard let range = Range(nsRange, in: text) else { return true }
        if range.lowerBound > text.startIndex {
            let previous = text[text.index(before: range.lowerBound)]
            if previous == "几" { return false }
            if previous == "第" { return true }
        }
        if chineseNum.count > 1, let last = chineseNum.last, last == "万" || last == "萬" || last == "亿" || last == "億" {
            return true
        }
        if chineseNum.count > 1, chineseNum.contains("零") || chineseNum.contains("〇") {
            return true
        }
        guard range.upperBound < text.endIndex else { return chineseNum.count > 1 }
        let next = text[range.upperBound]
        if isDirectDigitSequence(chineseNum) {
            return "年月日号號".contains(next)
        }
        // `百分` is the word "percent" / "percentage", not 100 + 分.
        // Don't convert `百` when followed by `分`.
        if chineseNum == "百" && next == "分" { return false }
        if next.isWhitespace || next.isPunctuation { return true }
        return numericContextSuffixes.contains(next)
    }

    private static func trailingUnitOutput(_ chineseNum: String, unit: Character) -> String? {
        guard chineseNum.count > 1, chineseNum.last == unit else { return nil }
        let numberPart = String(chineseNum.dropLast())
        guard let arabic = ChineseNumberParser.parse(numberPart) else { return nil }
        return "\(arabic)\(unit)"
    }

    private static func isDirectDigitSequence(_ value: String) -> Bool {
        guard value.count > 1 else { return false }
        let directDigitCharacters = Set("零〇一二两兩三四五六七八九幺壹贰貳叁叄肆伍陆陸柒捌玖")
        return value.allSatisfy { directDigitCharacters.contains($0) }
    }

    private static func parsePercentNumber(_ value: String) -> String? {
        if value == "百" {
            return "100"
        }
        return ChineseNumberParser.parse(value)
    }

    private static func mixedLargeUnitOutput(
        _ chineseNum: String,
        in text: String,
        range nsRange: NSRange
    ) -> String? {
        guard chineseNum.count > 1, chineseNum.hasSuffix("万") else { return nil }
        guard let range = Range(nsRange, in: text), range.upperBound < text.endIndex else { return nil }
        let next = text[range.upperBound]
        guard next == "字" || next == "人" else { return nil }
        let numberPart = String(chineseNum.dropLast())
        guard let arabic = ChineseNumberParser.parse(numberPart) else { return nil }
        return "\(arabic)万"
    }

    private static func formatHour(_ parsedHour: String, source: String) -> String {
        if parsedHour == "0", source.contains("零") {
            return "00"
        }
        return parsedHour
    }

    private static let regexCache = ChineseITNRegexCache()

    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        regexCache.regex(for: pattern)
    }

    // MARK: - Regex replacement helper

    private static func manualReplace(
        _ text: String,
        regex: NSRegularExpression,
        range: NSRange,
        transform: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }
        var output = ""
        var cursor = 0
        for match in matches {
            let prefixRange = NSRange(location: cursor, length: match.range.location - cursor)
            output += nsText.substring(with: prefixRange)
            output += transform(match, nsText)
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            let suffixRange = NSRange(location: cursor, length: nsText.length - cursor)
            output += nsText.substring(with: suffixRange)
        }
        return output
    }
}

private final class ChineseITNRegexCache: @unchecked Sendable {
    private var values: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        if let cached = values[pattern] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let compiled = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        lock.lock()
        values[pattern] = compiled
        lock.unlock()
        return compiled
    }
}
