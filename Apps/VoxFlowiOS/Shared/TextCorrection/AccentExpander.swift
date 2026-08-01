// DictusCore/Sources/DictusCore/TextCorrection/AccentExpander.swift
// Generates accent variants of a typed word and picks the best dictionary match,
// requiring strong frequency dominance over the unaccented input.
import Foundation

/// Multiplier required for an accented variant to override the unaccented input
/// when the unaccented input itself exists in the dictionary.
///
/// Set to 5x: typical French accent pairs have wildly different frequencies
/// (e.g., "très" vs "tres" >100x), so 5x is a conservative floor that rejects
/// weak cases while keeping strong ones. Prevents `"publie"` (valid, "je publie")
/// from auto-correcting to `"publié"`.
public let accentExpansionDominanceMultiplier: Int = 5

/// Tries adding accents to `word` and returns the highest-frequency dictionary
/// match, or `nil` if no accented form exists or the unaccented input is itself
/// frequent enough to keep.
///
/// Examples (French): `"deja"` → `"déjà"`, `"apres"` → `"après"`, `"publie"` → `nil`
/// (because "publie" is a valid French verb form and not dominated 5x).
///
/// Algorithm:
///   1. Find each position in `word` whose letter has accent variants in `profile.accentMap`.
///   2. Generate single-substitution candidates and double-substitution candidates.
///   3. For each candidate, query `provider.frequency(of:)` and `provider.wordExists(_:)`.
///   4. Pick the highest-frequency candidate that exists in the dictionary.
///   5. If the unaccented input is also in the dictionary, require the candidate
///      to dominate it by `accentExpansionDominanceMultiplier` (5x) to override.
///      If the unaccented input is *not* in the dictionary, any matching candidate wins.
///
/// WHY only single and double substitutions (not all combinations):
/// Real-world accented words rarely have more than two accented characters.
/// Generating all 2^N candidates is wasteful and risks false positives.
/// Empirically, "déjà", "après", "éléphant" — all double; nothing in our corpora
/// requires triple substitution.
///
/// WHY collapse rules are tried separately:
/// Single/double character substitutions preserve word length. Some accents
/// (German `ß`, replacing `ss`) require deleting a position, so they're
/// modeled as substring substitutions in `profile.collapseRules`. Each
/// collapse occurrence is tried independently against the dictionary,
/// subject to the same 5x-dominance check.
///
/// - Parameters:
///   - profile: The active language's profile.
///   - word: The input word (any case).
///   - provider: Backend used to score candidates by frequency and existence.
/// - Returns: The best accented form or `nil`.
public func expandAccents(
    profile: LanguageProfile,
    word: String,
    provider: FrequencyProvider
) -> String? {
    guard provider.isReady else { return nil }
    let lowered = word.lowercased()
    guard lowered.count >= 2 else { return nil }

    let accentMap = profile.accentMap
    let collapseRules = profile.collapseRules
    guard !accentMap.isEmpty || !collapseRules.isEmpty else { return nil }

    var accentablePositions: [(Int, [Character])] = []
    let chars = Array(lowered)
    for (i, ch) in chars.enumerated() {
        if let accents = accentMap[ch] {
            accentablePositions.append((i, accents))
        }
    }

    var bestMatch: String?
    var bestFreq: Int = -1

    func checkCandidate(_ candidateWord: String) {
        let freq = Int(provider.frequency(of: candidateWord))
        if freq > 0 && freq > bestFreq {
            bestMatch = candidateWord
            bestFreq = freq
        } else if freq == 0 && bestFreq < 0 && provider.wordExists(candidateWord) {
            // Fallback: word exists but `frequency(of:)` returns 0 (edge case).
            bestMatch = candidateWord
            bestFreq = 0
        }
    }

    // Single substitutions.
    for (pos, accents) in accentablePositions {
        for accent in accents {
            var candidate = chars
            candidate[pos] = accent
            checkCandidate(String(candidate))
        }
    }

    // Double substitutions (déjà, après, éléphant, etc.).
    if accentablePositions.count >= 2 {
        for i in 0..<accentablePositions.count {
            for j in (i + 1)..<accentablePositions.count {
                let (pos1, accents1) = accentablePositions[i]
                let (pos2, accents2) = accentablePositions[j]
                for a1 in accents1 {
                    for a2 in accents2 {
                        var candidate = chars
                        candidate[pos1] = a1
                        candidate[pos2] = a2
                        checkCandidate(String(candidate))
                    }
                }
            }
        }
    }

    // Length-changing collapses (German `ss → ß`).
    // For each rule, find every occurrence of the `from` substring in the
    // input and try substituting that single occurrence with `to`. We try one
    // occurrence at a time rather than all combinations because German words
    // with multiple `ss → ß` collapses in the same word are exceedingly rare
    // (and the 5x-dominance check would reject ambiguous cases anyway).
    for rule in collapseRules {
        let from = rule.from
        let to = rule.to
        guard !from.isEmpty, lowered.count >= from.count else { continue }
        var searchStart = lowered.startIndex
        while let range = lowered.range(of: from, range: searchStart..<lowered.endIndex) {
            let candidate = lowered.replacingCharacters(in: range, with: to)
            checkCandidate(candidate)
            searchStart = lowered.index(after: range.lowerBound)
        }
    }

    let inputFreq = Int(provider.frequency(of: lowered))
    guard let match = bestMatch else { return nil }

    if inputFreq == 0 {
        // Unaccented form is not in the dictionary — accented version is the fix.
        return match
    }
    // Both forms valid: require strong frequency dominance to override.
    if bestFreq > inputFreq * accentExpansionDominanceMultiplier {
        return match
    }
    return nil
}
