// DictusCore/Sources/DictusCore/AccentedCharacters.swift
// Long-press accent variants (multilingual) and the French-specific adaptive
// accent key (AZERTY row 3) namespace.
import Foundation

/// Accented character variants for keyboard long-press popups.
///
/// Currently shared across all languages — French AZERTY variants plus Spanish
/// acute/n-tilde added in #82/#83. Migration to per-language `LanguageProfile.longPressAccents`
/// is tracked in CONTEXT.md.
///
/// WHY precomposed Unicode characters (e.g., \u{00E9}) instead of combining characters:
/// Combining characters (e.g., "e" + combining acute \u{0301}) can cause string comparison
/// issues and display inconsistencies. Precomposed forms are single code points that render
/// identically everywhere. This is how iOS system keyboards store accented characters.
public enum AccentedCharacters {

    /// Maps a base letter (lowercase) to its accented variants. Currently a union
    /// of French AZERTY accents and Spanish acute/n-tilde variants.
    public static let mappings: [String: [String]] = [
        "e": ["\u{00E9}", "\u{00E8}", "\u{00EA}", "\u{00EB}"],          // e acute, grave, circumflex, diaeresis
        "a": ["\u{00E0}", "\u{00E2}", "\u{00E4}", "\u{00E1}"],          // a grave, circumflex, diaeresis, acute
        "u": ["\u{00F9}", "\u{00FB}", "\u{00FC}", "\u{00FA}"],          // u grave, circumflex, diaeresis, acute
        "i": ["\u{00EE}", "\u{00EF}", "\u{00ED}"],                      // i circumflex, diaeresis, acute
        "o": ["\u{00F4}", "\u{00F6}", "\u{00F3}"],                      // o circumflex, diaeresis, acute
        "c": ["\u{00E7}"],                                              // c cedilla
        "y": ["\u{00FF}"],                                              // y diaeresis
        "n": ["\u{00F1}"],                                              // n tilde
        "s": ["\u{00DF}"]                                               // ß (German eszett, added with #109)
    ]

    /// Returns accented variants for a given key, or nil if no accents exist.
    /// Lookup is case-insensitive: "E" and "e" return the same result.
    ///
    /// WHY case-insensitive:
    /// The keyboard layout stores uppercase labels ("E") but the user may be typing
    /// in either case. The accented variants are always lowercase — the keyboard target
    /// applies case transformation based on shift state.
    public static func accents(for key: String) -> [String]? {
        return mappings[key.lowercased()]
    }

}

/// French-specific adaptive accent key (AZERTY row 3) behaviour.
///
/// The data and rules in this namespace apply ONLY to French. Other languages
/// reach accents via standard long-press popups (`AccentedCharacters.mappings`)
/// — they do not get an adaptive key at all. This namespace exists as its own
/// type so future readers cannot mistake the contents for a multilingual API.
///
/// Wired into the keyboard at the AZERTY layout's row 3 single key labelled
/// `"'"` with `alternate: "accent"`. `DictusKeyboardBridge` calls into this
/// namespace on each keystroke to decide what label the key should display
/// and what action it should take when tapped.
public enum FrenchAdaptiveKey {

    /// Default accent per vowel (most common in French).
    /// Used by `label(...)` to decide the adaptive key's displayed character
    /// after the user types a vowel.
    public static let defaults: [String: String] = [
        "e": "\u{00E9}",  // e-acute (most common French accent)
        "a": "\u{00E0}",  // a-grave
        "u": "\u{00F9}",  // u-grave
        "i": "\u{00EE}",  // i-circumflex
        "o": "\u{00F4}",  // o-circumflex
    ]

    /// Bigrams where the second character is a vowel but the user almost certainly
    /// wants an apostrophe, not an accent. "qu" is the canonical French example:
    /// qu'il, qu'elle, qu'on, qu'un, qu'est-ce, etc.
    private static let apostropheBigrams: Set<String> = ["qu"]

    /// Returns what the adaptive key should display based on the last typed character.
    /// After a vowel: shows the most common French accent for that vowel.
    /// Otherwise (or after an apostrophe-bigram): shows apostrophe (').
    ///
    /// WHY apostrophe as default:
    /// In French, the apostrophe is the most common non-letter character after space.
    /// It appears in "l'", "d'", "n'", "j'", "c'", "s'" etc. Having it one tap away
    /// on the letters layer eliminates the 3-tap layer switch otherwise needed.
    public static func label(afterTyping lastChar: String?, precedingChar: String? = nil) -> String {
        guard let lastChar = lastChar else { return "'" }
        let lowered = lastChar.lowercased()

        // Check if the 2-char context triggers apostrophe override (e.g., "qu")
        if let prev = precedingChar?.lowercased() {
            let bigram = prev + lowered
            if apostropheBigrams.contains(bigram) {
                return "'"
            }
        }

        if let accent = defaults[lowered] {
            // Preserve original case: if user typed "A", return "À" not "à"
            return lastChar == lastChar.uppercased() && lastChar != lastChar.lowercased()
                ? accent.uppercased() : accent
        }
        return "'"
    }

    /// Returns true if the adaptive key should replace the previous character
    /// (i.e., when the key is showing an accent for a vowel, not apostrophe).
    /// Used by the bridge to call `deleteBackward()` before inserting the accent.
    public static func shouldReplace(afterTyping lastChar: String?, precedingChar: String? = nil) -> Bool {
        guard let lastChar = lastChar?.lowercased() else { return false }
        if let prev = precedingChar?.lowercased() {
            let bigram = prev + lastChar
            if apostropheBigrams.contains(bigram) {
                return false
            }
        }
        return defaults[lastChar] != nil
    }

    /// Returns the base vowel that triggered the adaptive key's accent display.
    /// Used to determine which accent variants to show on long-press.
    /// Returns nil when the adaptive key is showing apostrophe (no long-press popup needed).
    public static func vowel(afterTyping lastChar: String?, precedingChar: String? = nil) -> String? {
        guard let lastChar = lastChar?.lowercased() else { return nil }
        if let prev = precedingChar?.lowercased() {
            let bigram = prev + lastChar
            if apostropheBigrams.contains(bigram) {
                return nil
            }
        }
        return defaults[lastChar] != nil ? lastChar : nil
    }
}
