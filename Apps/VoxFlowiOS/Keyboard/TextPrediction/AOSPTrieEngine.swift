// DictusKeyboard/TextPrediction/AOSPTrieEngine.swift
// Wraps the AOSP-inspired C++ trie engine via ObjC++ bridge.
import Foundation
import Shared

/// Wraps the AOSP-inspired C++ trie engine via ObjC++ bridge.
///
/// WHY replacing SymSpell:
/// SymSpell pre-generates all edit-distance deletes (~7 per word at distance 1), using 15 MiB
/// for 10K words. The trie walks candidates during lookup, supporting 100K+ words in ~3-5 MiB
/// via mmap, with keyboard proximity scoring and accent-aware costs.
final class AOSPTrieEngine {

    private let bridge = AOSPTrieBridge()
    private var wordCount: Int = 0

    /// Serial queue for dictionary loading. Ensures only one load runs at a time.
    private let loadQueue = DispatchQueue(
        label: "com.mashangxie.ios.aosptrie-load",
        qos: .userInitiated
    )

    /// True while a background load is in progress.
    private(set) var isLoading: Bool = false

    /// The currently loaded language code ("fr", "en", "es").
    /// Set by load(language:) so overrides and apostrophe handling can be language-aware.
    private var currentLanguage: String = "fr"

    /// The active language's data profile, or nil if `currentLanguage` is not a
    /// registered `SupportedLanguage`. All per-language data (overrides, accentMap,
    /// contractionPrefixes) is read from here so adding a language is a matter of
    /// authoring `Languages/<Lang>.swift` in DictusCore.
    private var currentProfile: LanguageProfile? {
        SupportedLanguage(rawValue: currentLanguage)?.profile
    }

    /// Loads binary .dict file for the given language.
    /// Replaces any previously loaded dictionary.
    ///
    /// WHY async: Prevents blocking the main thread during keyboard init.
    /// The keyboard appears instantly; spell correction becomes available after mmap load.
    func load(language: String, bundle: Bundle = .main) {
        isLoading = true
        currentLanguage = language
        bridge.unloadDictionary()
        wordCount = 0

        loadQueue.async { [weak self] in
            guard let self = self else { return }

            guard let path = bundle.path(
                forResource: "\(language)_spellcheck", ofType: "dict"
            ) else {
                print("[AOSPTrieEngine] Failed to find \(language)_spellcheck.dat")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            let success = self.bridge.loadDictionary(atPath: path)

            // Set proximity map based on active keyboard layout.
            // AZERTY is default because Dictus targets French-speaking users.
            if LayoutType.active == .azerty {
                self.bridge.setProximityMapAZERTY()
            } else {
                self.bridge.setProximityMapQWERTY()
            }

            // Load n-gram data on the same queue, right after the spell dict.
            // WHY here: n-grams are only useful after the dictionary is loaded,
            // and loading both on the same serial queue ensures correct ordering.
            if success {
                self.loadNgrams(language: language, bundle: bundle)
            }

            DispatchQueue.main.async {
                if success {
                    self.wordCount = Int(self.bridge.wordCount())
                    print("[AOSPTrieEngine] Loaded \(language)_spellcheck.dat (\(self.wordCount) words)")
                } else {
                    print("[AOSPTrieEngine] Failed to load \(language)_spellcheck.dat")
                }
                self.isLoading = false
            }
        }
    }

    /// Check language-specific overrides only (no trie lookup). Returns nil if no override applies.
    /// Used by TextPredictionEngine to check overrides BEFORE UserDictionary,
    /// since words like "ca" must always correct to "ça" even if "ca" was learned.
    func languageOverride(for word: String) -> (correction: String, alternatives: [String])? {
        guard let profile = currentProfile,
              let corrected = applyOverride(profile: profile, word: word) else { return nil }
        return (corrected, [])
    }

    /// Returns best correction and alternatives, or nil if word is correct.
    /// Handles language-specific overrides, apostrophe splitting, and case restoration.
    ///
    /// Rules:
    /// 1. Language overrides checked first (e.g., French "ca" -> "ça").
    /// 2. Apostrophe words: only the part after the last apostrophe is checked
    ///    ("qu'il" -> checks "il", not the whole string).
    /// 3. Case restoration: if input starts with uppercase, correction is capitalized.
    func spellCheck(_ word: String) -> (correction: String, alternatives: [String])? {
        let lowered = word.lowercased()

        // Check language-specific overrides first (works even before dictionary loads)
        if let profile = currentProfile,
           let corrected = applyOverride(profile: profile, word: word) {
            return (corrected, [])
        }

        guard bridge.isLoaded(), !word.isEmpty else { return nil }

        // Handle apostrophe words: "qu'il" -> check "il", "l'homme" -> check "homme"
        // French contractions split at the apostrophe; only the main word can be misspelled.
        let wordToCheck: String
        let prefix: String?
        if let apoIndex = lowered.lastIndex(of: "'") {
            let afterApo = String(lowered[lowered.index(after: apoIndex)...])
            if afterApo.isEmpty { return nil }
            wordToCheck = afterApo
            prefix = String(lowered[...apoIndex])
        } else {
            wordToCheck = lowered
            prefix = nil
        }

        guard let result = bridge.spellCheck(wordToCheck, maxEditDistance: 2.0) else {
            return nil
        }

        // Restore case and reassemble with prefix if present
        let isCapitalized = word.first?.isUppercase == true
        let correction = prefix.map { $0 + result.correction } ?? result.correction
        let fullCorrection = isCapitalized ? correction.capitalized : correction

        let alts = result.alternatives.prefix(2).map { alt -> String in
            let full = prefix.map { $0 + alt } ?? alt
            return isCapitalized ? full.capitalized : full
        }

        return (fullCorrection, Array(alts))
    }

    /// No-op for trie engine. User words are checked separately via UserDictionary.
    /// The mmap'd trie is read-only; user words are handled as a two-pass lookup
    /// in TextPredictionEngine (user dict first, then trie).
    func injectUserWord(_ word: String) {
        // No-op: user dictionary is checked before trie in TextPredictionEngine
    }

    /// Whether a dictionary is loaded and ready for lookups.
    var isLoaded: Bool { bridge.isLoaded() }

    /// Number of words in the loaded dictionary.
    var dictionarySize: Int { wordCount }

    /// Check if a word exists in the trie dictionary.
    func wordExists(_ word: String) -> Bool {
        guard bridge.isLoaded() else { return false }
        return bridge.wordExists(word)
    }

    /// Get the frequency of a word in the trie (0 if not found).
    func wordFrequency(_ word: String) -> UInt16 {
        guard bridge.isLoaded() else { return 0 }
        return UInt16(bridge.getFrequency(word))
    }

    /// Try to expand a word into an apostrophe contraction for the active language.
    /// French: "Cest" → "c'est", "lhomme" → "l'homme", "jai" → "j'ai".
    /// Returns nil for languages whose `LanguageProfile.contractionPrefixes` is empty.
    func contractionExpansion(_ word: String) -> String? {
        guard let profile = currentProfile else { return nil }
        return expandContractions(profile: profile, word: word, provider: self)
    }

    /// Try adding accents to an unaccented word and check if the result exists.
    /// French: "deja" → "déjà", "apres" → "après", "tres" → "très".
    /// Spanish: "espanol" → "español".
    ///
    /// Returns nil for languages whose `LanguageProfile.accentMap` is empty (English).
    func accentExpansion(_ word: String) -> String? {
        guard let profile = currentProfile else { return nil }
        return expandAccents(profile: profile, word: word, provider: self)
    }

    // MARK: - N-gram prediction

    /// Load n-gram binary for the given language.
    /// Called after the spellcheck dictionary loads on the same loadQueue,
    /// so n-gram data is ready shortly after spell correction is available.
    func loadNgrams(language: String, bundle: Bundle = .main) {
        guard let path = bundle.path(forResource: "\(language)_ngrams", ofType: "dict") else {
            print("[AOSPTrieEngine] No n-gram data for \(language)")
            return
        }
        let success = bridge.loadNgrams(atPath: path)
        // Log file size to confirm the correct binary is loaded (769 bigrams = 38 KiB old, 1589 = 58 KiB new)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        print("[AOSPTrieEngine] N-grams \(language): \(success ? "loaded" : "failed") (\(fileSize / 1024) KiB)")

        // Write diagnostic only when App Group is actually available. Free-signed
        // keyboard extensions must not touch the suite directly at startup.
        if let defaults = AppGroup.defaultsIfAvailable {
            defaults.set("lang=\(language) ok=\(success) size=\(fileSize)", forKey: "ngramDiagnostic")
        }
    }

    /// Predict next words given 1-2 previous words.
    /// Uses trigram+bigram backoff when 2 words provided, bigram only for 1 word.
    ///
    /// WHY [String] input instead of String:
    /// The n-gram engine supports both bigram (1 word context) and trigram (2 word context).
    /// Passing an array lets the caller provide as much context as available without
    /// needing separate methods for each n-gram order.
    func predictNextWords(after words: [String], maxResults: Int = 3) -> [String] {
        guard bridge.ngramsLoaded() else { return [] }
        if words.count >= 2 {
            let result = bridge.predict(
                afterWord1: words[words.count - 2],
                word2: words[words.count - 1],
                maxResults: UInt(maxResults)
            )
            return result
        } else if words.count == 1 {
            let result = bridge.predict(
                afterWord: words[0],
                maxResults: UInt(maxResults)
            )
            return result
        }
        return []
    }

    /// Get bigram score for a candidate correction given previous word context.
    /// Returns 0 if no n-gram data or no match.
    /// Used by the prediction pipeline to boost corrections that match n-gram patterns.
    func bigramScore(for word: String, after prevWord: String) -> UInt16 {
        guard bridge.ngramsLoaded() else { return 0 }
        return bridge.bigramScore(forWord: word, afterWord: prevWord)
    }

    /// Returns nearby words (edit distance candidates) for a word, excluding the word itself.
    /// Unlike spellCheck, this returns results even for correctly-spelled words.
    /// Used by n-gram context boosting to find alternatives for valid-but-rare words
    /// (e.g., "sui" is valid but "suis" is much more likely after "je").
    func nearbyWords(for word: String) -> [String] {
        guard bridge.isLoaded(), !word.isEmpty else { return [] }
        return bridge.nearbyWords(word, maxEditDistance: 2.0, maxResults: 5)
    }

    /// Whether n-gram data is loaded and ready for predictions.
    var ngramsLoaded: Bool { bridge.ngramsLoaded() }
}

// MARK: - FrequencyProvider conformance
//
// Lets DictusCore autocorrect helpers (`expandAccents`, `expandContractions`)
// query the trie via the protocol without importing the bridge. `wordExists(_:)`
// is already defined on the class and matches the protocol signature.
extension AOSPTrieEngine: FrequencyProvider {
    var isReady: Bool { isLoaded }
    func frequency(of word: String) -> UInt16 { wordFrequency(word) }
}
