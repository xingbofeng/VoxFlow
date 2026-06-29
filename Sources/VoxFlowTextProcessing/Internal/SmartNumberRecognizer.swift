import Foundation

/// Smart Chinese-to-Arabic number recognition. Converts Chinese numerals to
/// Arabic digits in quantity, date, time, percentage, ratio, and temperature
/// contexts. Conservative: idioms, fixed phrases, and ambiguous "一" are
/// preserved.
///
/// This type is a thin wrapper that:
/// 1. Masks protected regions (URLs, paths, code, emails, versions) to
///    prevent number conversion inside code-like content.
/// 2. Delegates pattern matching to `ChineseITNNormalizer`, which calls
///    `ChineseNumberParser` for actual numeral parsing.
/// 3. Restores protected regions.
public enum SmartNumberRecognizer {
    public static func process(_ text: String) -> String {
        // Protect code-like regions (URLs, paths, backtick content, emails,
        // version strings) from number conversion.
        let protected = CJKLatinSpacer.ProtectedRegions.mask(text)
        let normalized = ChineseITNNormalizer.normalize(protected.masked)
        return CJKLatinSpacer.ProtectedRegions.unmask(normalized, regions: protected.regions)
    }
}
