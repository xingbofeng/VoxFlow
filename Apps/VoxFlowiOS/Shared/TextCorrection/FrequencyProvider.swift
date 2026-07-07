// DictusCore/Sources/DictusCore/TextCorrection/FrequencyProvider.swift
// Protocol that abstracts the dictionary backend used by autocorrect helpers.
import Foundation

/// Abstracts the dictionary backend so autocorrect helpers (`AccentExpander`,
/// `ContractionExpander`) can be unit-tested without the C++ trie bridge.
///
/// Production: `AOSPTrieEngine` adapts the AOSP trie via this protocol.
/// Tests: a stub provider returns controlled frequencies for golden inputs.
///
/// WHY this exists:
/// The autocorrect algorithms (5x-dominance accent expansion, contraction split,
/// override lookup) are pure logic that depends only on per-word frequency and
/// existence checks. Decoupling them from `AOSPTrieBridge` lets the regression
/// tests live in `DictusCoreTests` without dragging the C++ bridge into the
/// test bundle.
public protocol FrequencyProvider {
    /// Whether the underlying dictionary is loaded and ready for lookups.
    /// Algorithms early-return when false.
    var isReady: Bool { get }

    /// Returns the frequency of `word` in the dictionary, or 0 if not present.
    func frequency(of word: String) -> UInt16

    /// Returns true if `word` exists in the dictionary.
    /// Used as a fallback when frequency is 0 but the word may still be valid.
    func wordExists(_ word: String) -> Bool
}
