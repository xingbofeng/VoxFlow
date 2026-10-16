import Foundation

/// Converts Chinese unit names following Arabic digits into international
/// symbols (公里 → km, 千克 → kg, 摄氏度 → °C). Modeled on Chatterfly's
/// `keyVoiceUnitToInternational` toggle.
///
/// Conservative by construction:
/// - Only converts after an Arabic digit (`5公里` → `5km`); bare nouns like
///   大米/秒杀 are untouched because they never follow a digit.
/// - Chinese numerals (`五公里`) are left alone — smartNumberRecognition runs
///   before this processor and hands over already-converted digits.
/// - The unit must end at a word boundary, so 克拉 and 米其林 are not
///   partially rewritten as 克 and 米.
/// - URLs, paths, emails, versions, identifiers and backtick content are
///   protected through the same `CJKLatinSpacer.ProtectedRegions` masking
///   used by SmartNumberRecognizer.
public enum UnitNormalizer {
    /// Longest match first, so 千米 wins over 米, 平方米 over 米, 千克 over 克.
    private static let unitTable: [(chinese: String, symbol: String)] = [
        // Length
        ("千米", "km"), ("公里", "km"), ("厘米", "cm"), ("公分", "cm"),
        ("毫米", "mm"), ("米", "m"),
        // Mass
        ("千克", "kg"), ("公斤", "kg"), ("毫克", "mg"), ("克", "g"), ("吨", "t"),
        // Temperature
        ("摄氏度", "°C"), ("华氏度", "°F"),
        // Time
        ("小时", "h"), ("分钟", "min"), ("毫秒", "ms"), ("秒", "s"),
        // Volume
        ("毫升", "mL"), ("升", "L"),
        // Area
        ("平方千米", "km²"), ("平方公里", "km²"), ("平方米", "m²"),
        // Volume (cubic)
        ("立方米", "m³"),
        // Speed
        ("公里每小时", "km/h"), ("千米每小时", "km/h"),
    ].sorted { $0.chinese.count > $1.chinese.count }

    public static func process(_ text: String) -> String {
        let protected = CJKLatinSpacer.ProtectedRegions.mask(text)
        var result = protected.masked
        var wordEndings = Set<Int>()
        result.enumerateSubstrings(in: result.startIndex..<result.endIndex, options: .byWords) { _, range, _, _ in
            wordEndings.insert(NSRange(range, in: result).upperBound)
        }

        let alternatives = unitTable.map { NSRegularExpression.escapedPattern(for: $0.chinese) }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: "[0-9](\(alternatives))") else { return text }
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        for match in regex.matches(in: result, range: range).reversed() {
            let unitRange = match.range(at: 1)
            guard wordEndings.contains(unitRange.upperBound),
                  let stringRange = Range(unitRange, in: result),
                  let symbol = unitTable.first(where: { $0.chinese == result[stringRange] })?.symbol else { continue }
            result.replaceSubrange(stringRange, with: symbol)
        }

        return CJKLatinSpacer.ProtectedRegions.unmask(result, regions: protected.regions)
    }
}
