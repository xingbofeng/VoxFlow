// DictusCore/Sources/DictusCore/TextCorrection/ContractionExpander.swift
// Splits a word like "lhomme" or "Cest" into its apostrophe contraction
// when the suffix exists as a real word in the dictionary.
import Foundation

/// Tries to expand `word` into a contraction with apostrophe by matching its
/// leading characters against `profile.contractionPrefixes`.
///
/// Examples (French): `"Cest"` → `"c'est"`, `"lhomme"` → `"l'homme"`,
/// `"jai"` → `"j'ai"`, `"quelle"` → `"qu'elle"` (when the suffix is a real word).
///
/// Returns `nil` if no prefix match is found, the suffix doesn't exist in the
/// dictionary, or the language has no contraction prefixes.
///
/// WHY shorter prefixes are tried first:
/// The original implementation tried 1-character prefixes (`l'`, `d'`, ...)
/// before 2-character prefixes (`qu'`). This preserves that precedence:
/// for input `"quelle"`, we want `"qu'elle"` (matched 2-char) rather than
/// `"q'uelle"` (matched 1-char) — but `"q'"` isn't a real prefix so it can't
/// match, leaving the 2-char path. Sorting by ascending length and returning
/// on first match yields the same result.
///
/// - Parameters:
///   - profile: The active language's profile.
///   - word: The input word (any case).
///   - provider: Backend used to verify that the suffix is a real word.
/// - Returns: The expanded form (apostrophe included) or `nil`.
public func expandContractions(
    profile: LanguageProfile,
    word: String,
    provider: FrequencyProvider
) -> String? {
    guard provider.isReady else { return nil }
    let lowered = word.lowercased()
    guard lowered.count >= 2 else { return nil }
    guard !profile.contractionPrefixes.isEmpty else { return nil }

    // Try shorter prefixes first to preserve the original lookup precedence.
    let prefixesByLength = profile.contractionPrefixes
        .sorted { $0.count < $1.count }

    for prefix in prefixesByLength {
        // The prefix string includes the trailing apostrophe; strip it for the letter count.
        let letterCount = prefix.count - 1
        guard letterCount > 0, lowered.count > letterCount else { continue }

        let candidatePrefix = String(lowered.prefix(letterCount)) + "'"
        let suffix = String(lowered.dropFirst(letterCount))

        if candidatePrefix == prefix, !suffix.isEmpty, provider.wordExists(suffix) {
            return candidatePrefix + suffix
        }
    }
    return nil
}
