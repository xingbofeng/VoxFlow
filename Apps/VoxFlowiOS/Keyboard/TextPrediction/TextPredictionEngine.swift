// DictusKeyboard/TextPrediction/TextPredictionEngine.swift
// Core prediction logic: word completions, spell-checking, and accent suggestions.
import UIKit
import Shared

/// Provides word completions, spell-checking, and accent suggestions for the keyboard.
///
/// WHY a class (not struct):
/// UITextChecker is a reference type (NSObject subclass) and maintains internal state
/// for its learned words dictionary. Using a class avoids copy-on-write issues and
/// ensures a single UITextChecker instance is reused throughout the keyboard session.
///
/// WHY UITextChecker:
/// Apple's built-in spell checker and word completion engine. It uses the system
/// dictionary which is already installed on every iOS device -- no additional data
/// download needed. We combine its completions with our FrequencyDictionary to
/// rank results by word frequency (most common words first).
@MainActor
class TextPredictionEngine {

    /// Shared instance — engines are heavy (~3 MiB FrequencyDictionary + AOSP trie mmap).
    /// Per-controller instances were leaking via SwiftUI @ObservedObject zombies that
    /// survive their owning KeyboardViewController.deinit (KeyboardRootView struct held
    /// alive by KeyboardState.shared.objectWillChange subscription). Sharing the heavy
    /// resources means the leak no longer multiplies memory per app-switch cycle.
    @MainActor static let shared = TextPredictionEngine()

    @MainActor private let textChecker = UITextChecker()
    private var frequencyDict = FrequencyDictionary()
    private let aospTrieEngine = AOSPTrieEngine()
    private var language: String = "fr"

    /// The active language's data profile, or nil if `language` is not a registered
    /// `SupportedLanguage`. Used to gate language-specific pipeline stages by
    /// reading profile data instead of hardcoded language string comparisons.
    private var profile: LanguageProfile? {
        SupportedLanguage(rawValue: language)?.profile
    }

    private init() {
        // Verify language is available in UITextChecker
        let available = UITextChecker.availableLanguages
        if !available.contains(where: { $0.hasPrefix(language) }) {
            print("[TextPredictionEngine] Warning: '\(language)' not in available languages: \(available)")
        }
        frequencyDict.load(language: language)
        aospTrieEngine.load(language: language)
    }

    /// Updates the active language for completions and spell-checking.
    /// Reloads the frequency dictionary for the new language.
    ///
    /// WHY reload on language change:
    /// We only keep one language's frequency data in memory at a time
    /// to stay within the keyboard extension's ~50MB memory budget.
    func setLanguage(_ lang: String) {
        language = lang
        let available = UITextChecker.availableLanguages
        if !available.contains(where: { $0.hasPrefix(lang) }) {
            print("[TextPredictionEngine] Warning: '\(lang)' not in available languages: \(available)")
        }
        frequencyDict.load(language: lang)
        aospTrieEngine.load(language: lang)
    }

    /// Returns up to 3 word completions for a partial word, ranked by frequency.
    ///
    /// HOW IT WORKS:
    /// 1. UITextChecker.completions() returns all possible completions from the system dictionary
    /// 2. We sort those completions by our frequency dictionary (lower rank = more common = first)
    /// 3. We return only the top 3 to fill the suggestion bar's 3 slots
    ///
    /// WHY frequency-based ranking:
    /// UITextChecker returns completions in alphabetical order by default. Ranking by
    /// word frequency ensures "les" appears before "lesparre" when typing "le".
    func suggestions(for partialWord: String) -> [String] {
        guard !partialWord.isEmpty else { return [] }

        let nsString = partialWord as NSString
        let range = NSRange(location: 0, length: nsString.length)

        guard let completions = textChecker.completions(
            forPartialWordRange: range,
            in: partialWord,
            language: language
        ) else {
            return []
        }

        let ranked = completions.sorted { frequencyDict.rank(of: $0) > frequencyDict.rank(of: $1) }
        return Array(ranked.prefix(3))
    }

    /// Returns the best correction and alternatives for a misspelled word.
    /// Returns nil if the word is correctly spelled or is a user-learned word.
    ///
    /// WHY two-pass lookup:
    /// Pass 1: Check UserDictionary first. Words the user has learned (via rejection
    /// or repetition) are always considered correct -- no trie lookup needed. This
    /// prevents the trie from "correcting" names, slang, or jargon the user has taught.
    /// Pass 2: Delegate to AOSPTrieEngine for proximity-weighted, accent-aware correction
    /// against the 100K+ word binary trie dictionary.
    ///
    /// WHY AOSPTrieEngine instead of SymSpell:
    /// The trie walks candidates during lookup with keyboard proximity scoring,
    /// supporting 100K+ words in ~0.4 MiB per language via mmap. SymSpell pre-generated
    /// all edit-distance deletes, using 15 MiB for just 10K words.
    func spellCheck(_ word: String) -> (correction: String, alternatives: [String])? {
        guard !word.isEmpty else { return nil }

        // Language-specific overrides bypass everything — e.g., "ca" is never valid French.
        // Must check before UserDictionary, otherwise typing "ca" twice
        // would "learn" it and block the ça correction permanently.
        if let result = aospTrieEngine.languageOverride(for: word) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: result.correction,
                branch: "language-override", prevWord: nil
            )
            #endif
            return result
        }

        // Apostrophe prefix fix: when the user types an apostrophe after an
        // invalid contraction prefix ("v'est"), correct the prefix via keyboard
        // proximity. Gated on the language having any contraction prefixes —
        // currently only French qualifies. Valid FR prefixes are {j,n,s,m,t,d,c,l,qu}.
        // Examples: "v'est" → "c'est", "b'est" → "c'est", "x'ai" → "j'ai".
        //
        // WHY before everything else:
        // Our downstream apostrophe split only validates the part AFTER the
        // apostrophe — "v'est" → checks "est" (valid) → returns nil (no correction).
        // We need to intercept wrong prefixes explicitly.
        if let profile = profile, !profile.contractionPrefixes.isEmpty,
           let corrected = correctApostrophePrefix(word) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: corrected, branch: "apostrophe-prefix", prevWord: nil
            )
            #endif
            return (corrected, [])
        }

        // Two-pass lookup: user dictionary first (learned words are always "correct").
        // Extract the word part after any apostrophe for user dict check, matching
        // the same apostrophe handling that AOSPTrieEngine uses internally.
        let lowered = word.lowercased()
        let wordToCheck: String
        if let apoIndex = lowered.lastIndex(of: "'") {
            wordToCheck = String(lowered[lowered.index(after: apoIndex)...])
        } else {
            wordToCheck = lowered
        }
        if UserDictionary.shared.isLearned(wordToCheck) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "user-learned")
            #endif
            return nil  // User-learned word: no correction needed
        }

        // Accent expansion runs BEFORE wordExists check.
        // "tres" may exist in the trie as a low-frequency word, but "très" is far
        // more common. The accent expansion uses frequency comparison to decide.
        // "deja" → "déjà", "apres" → "après", "tres" → "très"
        if let accented = aospTrieEngine.accentExpansion(wordToCheck) {
            let isCapitalized = word.first?.isUppercase == true
            let corrected = isCapitalized ? accented.capitalized : accented
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: corrected, branch: "accent", prevWord: nil
            )
            #endif
            return (corrected, [])
        }

        // Valid word guard: if the word exists in the trie dictionary, it's correct.
        // This prevents aggressive corrections like "fais" → "vais".
        // Runs AFTER accent expansion so "tres" → "très" still works.
        if aospTrieEngine.wordExists(wordToCheck) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "already-valid")
            #endif
            return nil
        }

        // Contraction expansion: "Cest" → "C'est", "jai" → "j'ai"
        if let expanded = aospTrieEngine.contractionExpansion(word) {
            let isCapitalized = word.first?.isUppercase == true
            let corrected = isCapitalized ? expanded.capitalized : expanded
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: corrected, branch: "contraction", prevWord: nil
            )
            #endif
            return (corrected, [])
        }

        // Word splitting + single-word correction comparison.
        //
        // Strategy (informed by real user feedback + debug log analysis):
        //
        // 1. Split with bigram evidence (any strategy) → accept. The n-gram
        //    model confirms this is a real phrase pattern.
        //
        // 2. Split with boundary signal but NO bigram evidence → compare ED.
        //    Our Wikipedia corpus misses colloquial phrases like "pas mal"
        //    (bigram score 0) but the spacebar-neighbor key proves a missed
        //    space. Accept the split only when it fits the input noticeably
        //    better than the trie's single-word correction (split ED + 1 ≤
        //    single ED). This rejects "fonction agités" cases where single-
        //    word correction is at ED 0 or 1 but keeps "pas mal" cases
        //    where single-word "Pascal" is at ED 2 and split ED is 1.
        //
        // 3. No split → fall through to trie single-word correction.
        let (splitResult, splitHasBoundary, splitHasBigram) = trySplitWithSignal(wordToCheck)
        if let split = splitResult {
            let useSplit: Bool
            if splitHasBigram {
                useSplit = true  // bigram confirmed, accept
            } else if splitHasBoundary {
                // Boundary-only (no bigram): compare with single-word correction via ED
                if let single = aospTrieEngine.spellCheck(word) {
                    let splitJoined = split.replacingOccurrences(of: " ", with: "").lowercased()
                    let splitED = Self.editDistance(wordToCheck, splitJoined)
                    let singleLower = single.correction.lowercased()
                    let singleWordPart: String
                    if let idx = singleLower.lastIndex(of: "'") {
                        singleWordPart = String(singleLower[singleLower.index(after: idx)...])
                    } else {
                        singleWordPart = singleLower
                    }
                    let singleED = Self.editDistance(wordToCheck, singleWordPart)
                    // Accept split only if strictly better fit (split + 1 ≤ single).
                    // "pasnmal": split "pasmal" ED 1, single "pascal" ED 2 → 1+1=2 ≤ 2 ✓
                    // "fonctionnalités": split "fonctionagités" ED ~3, single ED 0/1 → reject ✓
                    useSplit = (splitED + 1) <= singleED
                } else {
                    useSplit = true  // no single-word alternative, accept split
                }
            } else {
                useSplit = false  // direct split rejected without bigram (prevented by trySplit)
            }

            if useSplit {
                let isCapitalized = word.first?.isUppercase == true
                let result = isCapitalized ? (split.prefix(1).uppercased() + split.dropFirst()) : split
                #if DEBUG
                AutocorrectDebugLog.autocorrectDecision(
                    original: word, corrected: result,
                    branch: splitHasBoundary ? "split-boundary" : "split-bigram",
                    prevWord: nil
                )
                #endif
                return (result, [])
            }
            #if DEBUG
            AutocorrectDebugLog.note("split \"\(split)\" rejected (ED comparison favored single-word)")
            #endif
        }

        // Pass 5: trie spell check (proximity-weighted, accent-aware)
        let trieResult = aospTrieEngine.spellCheck(word)
        #if DEBUG
        if let r = trieResult {
            let corrFreq = aospTrieEngine.wordFrequency(r.correction.lowercased())
            let altsWithFreq = r.alternatives.map { alt in
                (alt, aospTrieEngine.wordFrequency(alt.lowercased()))
            }
            AutocorrectDebugLog.trieCandidates(
                word: word, correction: r.correction,
                correctionFreq: corrFreq, alternatives: altsWithFreq
            )
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: r.correction, branch: "trie", prevWord: nil
            )
        } else {
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "no-trie-candidate")
        }
        #endif
        return trieResult
    }

    /// Predict next words based on context (1-2 previous words).
    /// Falls back to top frequent words when no n-gram match exists.
    ///
    /// WHY fallback to frequency:
    /// When the user types a word not in the n-gram model (rare word, name, etc.),
    /// showing the most common words is better than an empty suggestion bar.
    /// These are the words most likely to follow any context.
    func predictNextWords(after words: [String]) -> [String] {
        let predictions = aospTrieEngine.predictNextWords(after: words)
        if predictions.isEmpty {
            return frequencyDict.topWords(count: 3)
        }
        return predictions
    }

    /// Spell check with n-gram context boosting.
    /// Uses two strategies to find context-appropriate corrections:
    /// 1. Rerank existing spell corrections using bigram scores
    /// 2. Check if n-gram predictions are close to the typed word (prediction-based)
    ///
    /// Strategy 2 is the key insight: instead of asking "what are the corrections for sui?"
    /// and hoping "suis" appears, we ask "what does the n-gram model predict after je?"
    /// and check if any prediction (like "suis") is close to what was typed ("sui").
    func spellCheck(_ word: String, previousWord: String?) -> (correction: String, alternatives: [String])? {
        let result = spellCheck(word)

        // If no previous word context or n-grams not loaded, return standard result
        guard let prev = previousWord, !prev.isEmpty, aospTrieEngine.ngramsLoaded else {
            return result
        }

        let lowered = word.lowercased()
        let wordToCheck: String
        let prefix: String?
        if let apoIdx = lowered.lastIndex(of: "'") {
            wordToCheck = String(lowered[lowered.index(after: apoIdx)...])
            prefix = String(lowered[...apoIdx])
        } else {
            wordToCheck = lowered
            prefix = nil
        }

        let prevLower = prev.lowercased()

        // Get n-gram predictions close to the typed word (edit distance exactly 1).
        // Only for words of 3+ characters — short words like "a", "à", "un" have too
        // many neighbors at distance 1-2, causing false corrections (e.g., "a" → "la").
        // Max distance 1 (not 2): distance 2 is too permissive even for longer words
        // (e.g., "suis" → "vais" at distance 2 would be a false correction).
        let closePredictions: [(String, UInt16)]
        if wordToCheck.count >= 3 {
            let predictions = aospTrieEngine.predictNextWords(after: [prevLower], maxResults: 8)
            closePredictions = predictions.compactMap { prediction in
                let dist = Self.editDistance(wordToCheck, prediction)
                guard dist == 1 else { return nil }
                let score = aospTrieEngine.bigramScore(for: prediction, after: prevLower)
                return score > 0 ? (prediction, score) : nil
            }
        } else {
            closePredictions = []
        }

        if let result = result {
            // Have base corrections — merge with close predictions and rerank
            var candidateSet: [String: UInt16] = [:]

            // Score existing corrections
            for candidate in [result.correction] + result.alternatives {
                let lowerCandidate = candidate.lowercased()
                let wordPart: String
                if let apoIdx = lowerCandidate.lastIndex(of: "'") {
                    wordPart = String(lowerCandidate[lowerCandidate.index(after: apoIdx)...])
                } else {
                    wordPart = lowerCandidate
                }
                candidateSet[candidate] = aospTrieEngine.bigramScore(for: wordPart, after: prevLower)
            }

            // Add close predictions (may introduce new candidates like "suis")
            let isCapitalized = word.first?.isUppercase == true
            for (prediction, score) in closePredictions {
                let full = prefix.map { $0 + prediction } ?? prediction
                let display = isCapitalized ? full.capitalized : full
                if let existing = candidateSet[display] {
                    candidateSet[display] = max(existing, score)
                } else {
                    candidateSet[display] = score
                }
            }

            // CRITICAL: if no candidate has ANY bigram evidence (all scores = 0),
            // the rerank becomes a random pick based on Dictionary iteration order.
            // This corrupted good trie corrections like "main" → "mais" with no
            // real justification. In this case, keep the trie's original result.
            let hasAnyBigramEvidence = candidateSet.values.contains { $0 > 0 }
            guard hasAnyBigramEvidence else {
                #if DEBUG
                AutocorrectDebugLog.note(
                    "bigram-rerank skipped (no evidence) for \"\(word)\" prev=\"\(prev)\", keeping \"\(result.correction)\""
                )
                #endif
                return result
            }

            // CRITICAL: the rerank must not pick a candidate that's FARTHER from
            // the typed input than the original trie winner. Example from debug
            // logs: pejx → trie chose "peux" (ED 1), but bigram("veux" after "tu")
            // = 49828 while bigram("peux" after "tu") = 0 (data gap, our corpus
            // lacks common colloquial phrases). Rerank promoted "veux" (ED 2)
            // over "peux" (ED 1), forcing the user to undo.
            //
            // Fix: filter candidates to those at ED ≤ original winner's ED. The
            // rerank may still reorder within this set, but can never move to a
            // less-proximal candidate. Prevents bigram data gaps from overriding
            // the trie's proximity scoring.
            let originalWordPart: String = {
                let ol = result.correction.lowercased()
                if let idx = ol.lastIndex(of: "'") {
                    return String(ol[ol.index(after: idx)...])
                } else {
                    return ol
                }
            }()
            let originalED = Self.editDistance(wordToCheck, originalWordPart)

            let eligible = candidateSet.filter { candidate, _ in
                let cl = candidate.lowercased()
                let cWordPart: String
                if let idx = cl.lastIndex(of: "'") {
                    cWordPart = String(cl[cl.index(after: idx)...])
                } else {
                    cWordPart = cl
                }
                return Self.editDistance(wordToCheck, cWordPart) <= originalED
            }
            // Safety: if filter removed everything (shouldn't happen — original is always eligible),
            // fall back to full set.
            let candidates = eligible.isEmpty ? candidateSet : eligible

            let reranked = candidates.sorted { $0.value > $1.value }
            let newCorrection = reranked[0].key
            let newAlternatives = reranked.dropFirst().map { $0.key }
            #if DEBUG
            if newCorrection != result.correction {
                let beforeScore = candidateSet[result.correction] ?? 0
                let afterScore = reranked[0].value
                AutocorrectDebugLog.bigramRerank(
                    word: word, prevWord: prev,
                    before: result.correction, after: newCorrection,
                    beforeScore: beforeScore, afterScore: afterScore
                )
            }
            #endif
            return (newCorrection, Array(newAlternatives.prefix(2)))
        }

        // Word is valid (spellCheck returned nil) — do not override with n-gram
        // predictions. This prevents "je fais" → "je vais" when "fais" is valid.
        return nil
    }

    /// Levenshtein edit distance between two strings. O(n*m) but strings are
    /// short (< 20 chars) so this is sub-microsecond.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                if a[i - 1] == b[j - 1] {
                    dp[j] = prev
                } else {
                    dp[j] = min(prev, dp[j], dp[j - 1]) + 1
                }
                prev = temp
            }
        }
        return dp[b.count]
    }

    /// No-op: user words are handled by the two-pass lookup in spellCheck().
    /// The mmap'd trie is read-only; user words live in UserDictionary (App Group).
    func injectUserWord(_ word: String) {
        // No-op: UserDictionary.shared is checked before trie in spellCheck()
    }

    // MARK: - Word Splitting

    /// Keys adjacent to the spacebar on each keyboard layout.
    /// When the user presses one of these instead of space, two words get fused.
    /// On AZERTY: bottom row is W-X-C-V-B-N — only N (rightmost, next to space/comma)
    /// and B are truly adjacent to the spacebar. V was previously included but is
    /// 3 keys from space, causing false splits like "calvier" → "cal hier".
    /// On QWERTY: bottom row is Z-X-C-V-B-N-M — M is rightmost (next to space),
    /// N and B are close enough to count.
    private static let azertySpacebarNeighbors: Set<Character> = ["n", "b", ","]
    private static let qwertySpacebarNeighbors: Set<Character> = ["n", "b", "m"]

    /// Short French words (2 chars) that are allowed to appear as split parts.
    /// Standard split requires ≥3 chars per part to avoid noise like "ho ne",
    /// but French has many 2-char pronouns/articles/connectives that commonly
    /// start missed-space compounds (e.g., "tuboeux" should split as "tu peux",
    /// "jepense" as "je pense"). This whitelist restricts the 2-char relaxation
    /// to words that are structurally plausible as a left/right split half.
    private static let shortSplitWhitelist: Set<String> = [
        "je", "tu", "il", "on", "me", "te", "se", "ne",
        "le", "la", "un", "du", "au", "en",
        "et", "ou", "ni", "si", "ça", "où", "ce"
    ]

    /// Whether a split part is long enough or belongs to the short-word whitelist.
    private static func isValidSplitPart(_ part: String) -> Bool {
        return part.count >= 3 || (part.count == 2 && shortSplitWhitelist.contains(part))
    }

    // MARK: - Apostrophe Prefix Correction

    /// Valid single-char contraction prefixes in French.
    /// "qu'" is handled separately since it's 2 chars.
    private static let validFrenchApostrophePrefixes: Set<Character> =
        ["j", "n", "s", "m", "t", "d", "c", "l"]

    /// Proximity groups for AZERTY — each key maps to the valid apostrophe prefix
    /// it likely substitutes when typed by mistake. Built from AZERTY bottom/middle
    /// row adjacency:
    /// - V is next to C → v'est → c'est
    /// - B is next to N → b'est → n'est (less common but possible)
    /// - G, H are next to J → g'ai/h'ai → j'ai
    private static let azertyApostrophePrefixFix: [Character: Character] = [
        "v": "c",  // v'est → c'est
        "x": "c",  // x'est → c'est (x is left of c on AZERTY)
        "f": "d",  // f'est → d'est (not a real contraction, skip?)
        "g": "j",  // g'ai → j'ai (g is left of h which is left of j)
        "h": "j",  // h'ai → j'ai
        "k": "j",  // k'ai → j'ai
        "b": "n",  // b'est → n'est
        "y": "t",  // y'es → t'es (adjacent on AZERTY top row)
        "r": "t",  // r'es → t'es
        "u": "t",  // u'es → t'es
    ]

    /// Correct a word with invalid apostrophe prefix via keyboard proximity.
    /// "v'est" → "c'est", "b'a" → "n'a", etc.
    /// Returns nil if no fix applies.
    private func correctApostrophePrefix(_ word: String) -> String? {
        let lower = word.lowercased()
        guard let apoIdx = lower.firstIndex(of: "'") else { return nil }

        // Only 1-char prefix is handled here (qu' is 2-char and handled elsewhere).
        let prefixDistance = lower.distance(from: lower.startIndex, to: apoIdx)
        guard prefixDistance == 1 else { return nil }

        let prefixChar = lower[lower.startIndex]
        let suffix = String(lower[lower.index(after: apoIdx)...])
        guard !suffix.isEmpty else { return nil }

        // Prefix is already valid — let the normal pipeline handle it.
        if Self.validFrenchApostrophePrefixes.contains(prefixChar) {
            return nil
        }

        // Look up the proximity fix for this prefix character.
        guard let fixedPrefix = Self.azertyApostrophePrefixFix[prefixChar] else {
            return nil
        }

        // Verify the suffix is a real word (avoids correcting random typos like
        // "v'azxy" where the suffix is garbage).
        guard aospTrieEngine.wordExists(suffix) else { return nil }

        // Reassemble with the corrected prefix and original casing.
        let isCapitalized = word.first?.isUppercase == true
        let corrected = "\(fixedPrefix)'\(suffix)"
        return isCapitalized ? (corrected.prefix(1).uppercased() + corrected.dropFirst()) : corrected
    }

    /// Wrapper around trySplit that returns the winning split plus flags
    /// describing the evidence backing it. Caller decides whether to accept.
    ///
    /// Evidence sources:
    /// - boundarySignal: split used a spacebar-neighbor char — strong physical evidence
    /// - bigramEvidence: pair (left, right) has bigram score > 0 — linguistic evidence
    ///
    /// Rules for returning a candidate:
    /// - Direct split (no boundary): REQUIRES bigram. Prevents "honnête lent".
    /// - Boundary split: allowed WITHOUT bigram (our n-gram corpus misses
    ///   colloquial phrases like "pas mal"). Caller applies an ED comparison
    ///   with the single-word correction to decide.
    ///
    /// Boundary splits with bigram evidence win over those without.
    private func trySplitWithSignal(_ word: String)
        -> (split: String?, hasBoundarySignal: Bool, hasBigramEvidence: Bool)
    {
        let chars = Array(word)
        // Minimum absolute part length 2; each part must also pass isValidSplitPart
        // which requires either ≥3 chars or membership in the short-word whitelist.
        // This lets "tu peux" split from "tuboeux" while still blocking "ho ne"
        // from "honne" (since "ho" is not whitelisted).
        let minPartLength = 2
        guard chars.count >= 4 else { return (nil, false, false) }

        let spacebarNeighbors = LayoutType.active == .azerty
            ? Self.azertySpacebarNeighbors
            : Self.qwertySpacebarNeighbors

        var bestBoundary: (split: String, score: UInt32, hasBigram: Bool)?
        var bestBigram: (split: String, score: UInt32)?

        /// Score a candidate pair. Returns (score, hasBigram).
        /// Candidates with bigram get a large bonus (1000×bigram), making them
        /// strictly win over non-bigram candidates at the same freq product.
        func scorePair(left: String, right: String) -> (UInt32, Bool) {
            let bigram = aospTrieEngine.bigramScore(for: right, after: left)
            let freqProduct = UInt32(aospTrieEngine.wordFrequency(left))
                            * UInt32(aospTrieEngine.wordFrequency(right))
            if bigram > 0 {
                return (freqProduct + UInt32(bigram) * 1000, true)
            } else {
                return (freqProduct, false)
            }
        }

        for splitPos in minPartLength...(chars.count - minPartLength) {
            let left = String(chars[0..<splitPos])
            let right = String(chars[splitPos...])

            // Both parts must meet the length/whitelist requirement.
            guard Self.isValidSplitPart(left) else { continue }

            let leftExists = aospTrieEngine.wordExists(left)
            let rightExists = aospTrieEngine.wordExists(right)

            // Boundary-char removal at spacebar neighbor (bigram OPTIONAL)
            if splitPos < chars.count, spacebarNeighbors.contains(chars[splitPos]) {
                let rightAfter = String(chars[(splitPos + 1)...])
                if Self.isValidSplitPart(rightAfter) {
                    // Case A: both halves valid as-is
                    if leftExists && aospTrieEngine.wordExists(rightAfter) {
                        let (s, hasBi) = scorePair(left: left, right: rightAfter)
                        if bestBoundary.map({ s > $0.score }) ?? true {
                            bestBoundary = ("\(left) \(rightAfter)", s, hasBi)
                        }
                    }
                    // Case B: right half needs spell correction (min 3 chars to avoid
                    // correcting short garbage into arbitrary words).
                    if leftExists && !aospTrieEngine.wordExists(rightAfter) && rightAfter.count >= 3,
                       let c = aospTrieEngine.spellCheck(rightAfter) {
                        let (s, hasBi) = scorePair(left: left, right: c.correction)
                        if bestBoundary.map({ s > $0.score }) ?? true {
                            bestBoundary = ("\(left) \(c.correction)", s, hasBi)
                        }
                    }
                }
            }

            // Direct split — REQUIRES bigram evidence (no boundary signal to fall back on)
            guard Self.isValidSplitPart(right) else { continue }
            if leftExists && rightExists {
                let (s, hasBi) = scorePair(left: left, right: right)
                if hasBi, bestBigram.map({ s > $0.score }) ?? true {
                    bestBigram = ("\(left) \(right)", s)
                }
            }
        }

        // Priority: boundary > direct bigram (boundary has stronger physical signal)
        let winner: String?
        let hasBoundary: Bool
        let hasBigramEv: Bool
        if let b = bestBoundary {
            winner = b.split
            hasBoundary = true
            hasBigramEv = b.hasBigram
        } else if let bg = bestBigram {
            winner = bg.split
            hasBoundary = false
            hasBigramEv = true
        } else {
            winner = nil
            hasBoundary = false
            hasBigramEv = false
        }

        #if DEBUG
        if winner != nil {
            AutocorrectDebugLog.splitEvaluation(
                word: word, boundaryBest: bestBoundary?.split,
                bigramBest: bestBigram?.split, winner: winner
            )
        }
        #endif
        return (winner, hasBoundary, hasBigramEv)
    }

}
