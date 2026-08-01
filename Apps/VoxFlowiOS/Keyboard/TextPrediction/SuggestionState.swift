// DictusKeyboard/TextPrediction/SuggestionState.swift
// Observable state for the suggestion bar UI, bridging TextPredictionEngine to SwiftUI.
import UIKit
import Shared
import ChineseInput

/// The current mode of the suggestion bar.
///
/// WHY an enum:
/// The suggestion bar displays different content depending on context:
/// - idle: empty bar (user just typed a space or field is empty)
/// - completions: showing word completions for partial input
/// - corrections: showing spell corrections for a complete misspelled word
/// The UI layer uses this to style the bar differently per mode.
enum SuggestionMode {
    case idle
    case completions
    case corrections
    case predictions      // After space: showing n-gram predicted next words
    case undoAvailable    // After autocorrect: showing undo option for previous correction
    case chineseCandidates
}

/// Tracks the last autocorrection so the user can undo it.
///
/// WHY:
/// Autocorrect can be wrong. iOS convention is that tapping the suggestion bar
/// after an autocorrection undoes it. We store the original + corrected word
/// and whether a space was auto-inserted, so undo can restore exact state.
struct AutocorrectState {
    let originalWord: String
    let correctedWord: String
    let insertedSpace: Bool
}

/// Observable suggestion state for SwiftUI binding.
///
/// WHY ObservableObject:
/// The suggestion bar is a SwiftUI view that needs to reactively update when
/// suggestions change. @Published properties trigger SwiftUI re-renders
/// automatically when the engine produces new suggestions.
///
/// WHY a separate class from TextPredictionEngine:
/// Separation of concerns: TextPredictionEngine is pure logic (testable without UI),
/// SuggestionState is the UI-facing adapter that holds @Published state and
/// handles UITextDocumentProxy interaction.
@MainActor
class SuggestionState: ObservableObject {

    /// Process-wide shared instance.
    /// Per-controller instances were being retained by SwiftUI's @ObservedObject backing
    /// store past their owning KeyboardViewController.deinit (#134). Sharing makes the
    /// leak no-op since all observers point to the same instance — only one keyboard
    /// is visible at a time.
    @MainActor static let shared = SuggestionState()

    @Published var suggestions: [String] = []
    @Published var mode: SuggestionMode = .idle
    @Published var currentWord: String = ""
    @Published var chinesePreedit: String = ""
    /// Typed Chinese candidates preserving Rime metadata (index / label / subtitle /
    /// comment). Display titles are in `suggestions`; the typed list is used for
    /// accurate Rime candidate selection and paging.
    @Published var chineseCandidates: [CandidateSuggestion] = []
    @Published var chineseHasMoreCandidates = false
    @Published var chinesePinyinCandidates: [String] = []
    @Published var chineseSelectedPinyin: String?
    /// Total candidate count for the active Chinese composition. May exceed
    /// `chineseCandidates.count` when paging; the UI uses it to show a "more
    /// candidates" count badge / footer. Nil when not composing.
    @Published var chineseCandidateTotalCount: Int? = nil

    var toolbarSuggestions: [String] {
        if mode == .chineseCandidates, suggestions.isEmpty, !chinesePreedit.isEmpty {
            guard !chinesePreedit.contains(where: \.isNumber) else { return [] }
            return [chinesePreedit]
        }
        return suggestions
    }

    /// Tracks an autocorrection that can be undone by tapping the suggestion bar.
    /// Set when autocorrect fires on space, cleared on next space or undo tap.
    @Published var pendingUndo: AutocorrectState?

    /// Words the user has rejected autocorrection for (undo'd).
    /// After undo, the same word should not be re-corrected on the next space.
    /// Cleared when the user starts typing a new word.
    var rejectedWords: Set<String> = []

    /// Shared engine — accessed lazily so keyboard cold start can draw the key grid
    /// before loading frequency dictionaries / trie resources.
    private var engine: TextPredictionEngine { TextPredictionEngine.shared }

    private init() {}

    /// Monotonic token used to ignore stale suggestion updates.
    /// Keep this on MainActor with the rest of SuggestionState. The previous GCD
    /// worker touched this @MainActor object and UITextChecker from a background
    /// queue, which is fragile inside keyboard extensions.
    private var suggestionUpdateGeneration = 0

    /// Whether autocorrect is enabled (reads from App Group shared preferences).
    var autocorrectEnabled: Bool {
        AppGroup.preferences.object(forKey: SharedKeys.autocorrectEnabled) as? Bool ?? true
    }

    /// Updates suggestions based on the current text input state.
    ///
    /// Called on every keystroke from the keyboard view.
    ///
    /// HOW IT WORKS:
    /// 1. Extract the last partial word from the text before the cursor
    /// 2. Check spell correction engine (same engine that fires on space)
    /// 3. If correction found: show [original | **correction** | alternative] (standard mobile layout)
    /// 4. If no correction: show UITextChecker completions
    /// 5. If no partial word (after space/newline), go idle
    ///
    /// WHY show correction in bar:
    /// The bar must preview what space will do. Standard iOS keyboard behavior:
    /// center slot (bold) = what gets auto-applied on space. If the bar shows
    /// completions but space applies a different correction, that's confusing.
    func update(proxy: UITextDocumentProxy) {
        guard let context = proxy.documentContextBeforeInput, !context.isEmpty else {
            clear()
            return
        }

        // If text ends with space or newline, no partial word to complete.
        // Don't clear predictions — they were set by handleSpace()/updatePredictions().
        if let lastChar = context.last, lastChar.isWhitespace || lastChar.isNewline {
            if mode != .predictions {
                clear()
            }
            return
        }

        // Extract the last word using substring enumeration
        let partial = extractLastWord(from: context)
        guard !partial.isEmpty else {
            clear()
            return
        }

        currentWord = partial

        // Guard: skip spell correction for tokens containing digits (#74)
        let containsDigit = partial.unicodeScalars.contains {
            CharacterSet.decimalDigits.contains($0)
        }
        if containsDigit {
            // Show completions only (no corrections) for numeric tokens
            let completions = engine.suggestions(for: partial)
            suggestions = completions.isEmpty ? [] : completions
            mode = completions.isEmpty ? .idle : .completions
            return
        }

        // Extract previous word for n-gram context boosting
        let previousWord = extractPreviousWord(from: context, currentWord: partial)

        // Check spell correction first (mirrors what handleSpace will do)
        if autocorrectEnabled,
           !rejectedWords.contains(partial.lowercased()),
           let result = engine.spellCheck(partial, previousWord: previousWord),
           result.correction.lowercased() != partial.lowercased() {
            // Standard mobile layout: [original | correction (bold) | alternative]
            var correctionSuggestions = [partial, result.correction]
            if let firstAlt = result.alternatives.first {
                correctionSuggestions.append(firstAlt)
            }
            suggestions = correctionSuggestions
            mode = .corrections
            return
        }

        // No correction — show word completions
        let completions = engine.suggestions(for: partial)
        if completions.isEmpty {
            suggestions = []
            mode = .idle
        } else {
            suggestions = completions
            mode = .completions
        }
    }

    /// Async suggestion update: takes pre-read context string (read on main thread),
    /// then dispatches computation to background. Cancels previous in-flight work.
    ///
    /// WHY a separate method from update(proxy:):
    /// update(proxy:) reads UITextDocumentProxy directly and runs synchronously on main.
    /// updateAsync takes a pre-read context string so the heavy computation
    /// (extractLastWord + engine lookups) runs on a background queue.
    /// The synchronous update() is still used by delete/undo paths where fresh proxy
    /// context is needed immediately.
    func updateAsync(context: String?) {
        guard let context = context, !context.isEmpty else {
            clear()
            return
        }

        // If text ends with whitespace, no partial word to complete.
        // BUT don't clear if we're showing predictions — handleSpace() already
        // triggered updatePredictions(), and clearing here would race with the
        // async prediction result. Predictions are the correct state after space.
        if let lastChar = context.last, lastChar.isWhitespace || lastChar.isNewline {
            if mode != .predictions && mode != .undoAvailable {
                clear()
            }
            return
        }

        suggestionUpdateGeneration += 1
        let generation = suggestionUpdateGeneration

        let partial = extractLastWord(from: context)
        guard !partial.isEmpty else {
            clear()
            return
        }

        let containsDigit = partial.unicodeScalars.contains {
            CharacterSet.decimalDigits.contains($0)
        }
        let previousWord = containsDigit ? nil : extractPreviousWord(from: context, currentWord: partial)
        let spellResult: (correction: String, alternatives: [String])?
        if !containsDigit,
           autocorrectEnabled,
           !rejectedWords.contains(partial.lowercased()) {
            spellResult = engine.spellCheck(partial, previousWord: previousWord)
        } else {
            spellResult = nil
        }
        let completions = engine.suggestions(for: partial)

        guard generation == suggestionUpdateGeneration else { return }
        currentWord = partial

        if containsDigit {
            suggestions = completions.isEmpty ? [] : completions
            mode = completions.isEmpty ? .idle : .completions
        } else if let undo = pendingUndo {
            var undoSuggestions = [undo.originalWord]
            undoSuggestions.append(contentsOf: completions.prefix(2))
            suggestions = undoSuggestions
            mode = .undoAvailable
        } else if let result = spellResult,
                  result.correction.lowercased() != partial.lowercased() {
            var correctionSuggestions = [partial, result.correction]
            if let firstAlt = result.alternatives.first {
                correctionSuggestions.append(firstAlt)
            }
            suggestions = correctionSuggestions
            mode = .corrections
        } else if !completions.isEmpty {
            suggestions = completions
            mode = .completions
        } else {
            suggestions = []
            mode = .idle
        }
    }

    /// Delegates spell-checking to the engine.
    /// Returns the best correction and alternatives for a misspelled word, or nil if correct.
    func performSpellCheck(_ word: String) -> (correction: String, alternatives: [String])? {
        return engine.spellCheck(word)
    }

    /// Spell check with optional previous word context for n-gram boosting.
    /// When previousWord is provided, correction candidates are reranked by bigram frequency.
    func performSpellCheck(_ word: String, previousWord: String?) -> (correction: String, alternatives: [String])? {
        return engine.spellCheck(word, previousWord: previousWord)
    }

    /// Resets the suggestion state to idle.
    func clear() {
        suggestionUpdateGeneration += 1
        suggestions = []
        mode = .idle
        currentWord = ""
        chinesePreedit = ""
        chineseCandidates = []
        chineseHasMoreCandidates = false
        chinesePinyinCandidates = []
        chineseSelectedPinyin = nil
        chineseCandidateTotalCount = nil
    }

    func updateChineseComposition(_ composition: ChineseCompositionState) {
        suggestionUpdateGeneration += 1
        currentWord = composition.preedit
        chinesePreedit = composition.preedit
        chineseCandidates = composition.candidates
        chineseHasMoreCandidates = composition.hasMoreCandidates
        chinesePinyinCandidates = composition.pinyinCandidates
        chineseSelectedPinyin = composition.selectedPinyin
        suggestions = composition.candidates.map(\.title)
        chineseCandidateTotalCount = composition.candidates.isEmpty ? nil : composition.candidates.count
        mode = composition.candidates.isEmpty && composition.preedit.isEmpty ? .idle : .chineseCandidates
    }

    func updateChineseComposition(preedit: String, candidates: [CandidateSuggestion], totalCandidateCount: Int? = nil) {
        updateChineseComposition(.init(preedit: preedit, candidates: candidates))
        chineseCandidateTotalCount = totalCandidateCount ?? (candidates.isEmpty ? nil : candidates.count)
    }

    func rimeCandidateIndex(atVisibleIndex visibleIndex: Int) -> Int? {
        guard chineseCandidates.indices.contains(visibleIndex) else { return nil }
        return chineseCandidates[visibleIndex].index
    }

    /// Updates the prediction engine's language.
    func setLanguage(_ lang: String) {
        engine.setLanguage(lang)
    }

    /// Learn a word and notify the prediction engine (no-op for trie engine).
    func learnWord(_ word: String) {
        engine.injectUserWord(word)
    }

    // MARK: - N-gram Predictions

    /// Updates suggestion bar with n-gram predicted next words.
    /// Called after space insertion (handleSpace) and after prediction tap (chaining).
    ///
    /// WHY a separate method from update/updateAsync:
    /// Predictions use a different data path: instead of extracting the current partial
    /// word and running spell check, we extract the last 1-2 complete words and query
    /// the n-gram engine. The result is displayed in .predictions mode, not .corrections.
    func updatePredictions(context: String?) {
        guard let context = context, !context.isEmpty else {
            clear()
            return
        }

        suggestionUpdateGeneration += 1
        let generation = suggestionUpdateGeneration

        let words = extractLastWords(from: context, count: 2)
        guard !words.isEmpty else {
            clear()
            return
        }

        let predictions = engine.predictNextWords(after: words)
        print("[SuggestionState] updatePredictions context=\(words) results=\(predictions)")
        guard generation == suggestionUpdateGeneration else { return }

        if let undo = pendingUndo {
            var undoSuggestions = [undo.originalWord]
            undoSuggestions.append(contentsOf: predictions.prefix(2))
            suggestions = undoSuggestions
            mode = .undoAvailable
        } else if predictions.isEmpty {
            suggestions = []
            mode = .idle
        } else {
            suggestions = Array(predictions.prefix(3))
            mode = .predictions
        }
    }

    /// Extracts the last N complete words from text context.
    /// Used for n-gram context: "Je suis en " -> ["suis", "en"]
    ///
    /// WHY not reuse extractLastWord: that returns the partial word being typed
    /// (before cursor, no trailing space). For predictions, we need the complete
    /// words before the space -- the n-gram engine looks up what comes AFTER these words.
    private func extractLastWords(from text: String, count: Int) -> [String] {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring {
                words.append(word)
            }
        }
        let start = max(0, words.count - count)
        return Array(words[start...])
    }

    // MARK: - Private

    /// Extract the word before the current partial word in the text context.
    /// "Je sui" with currentWord "sui" returns "Je".
    /// "J'ai un prblm" with currentWord "prblm" returns "un".
    ///
    /// WHY not just split on spaces: Swift's enumerateSubstrings handles
    /// Unicode word boundaries correctly (apostrophes, hyphens, etc.).
    private func extractPreviousWord(from text: String, currentWord: String) -> String? {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring {
                words.append(word)
            }
        }
        // The last word should be currentWord; the one before it is previousWord
        guard words.count >= 2, words.last?.lowercased() == currentWord.lowercased() else {
            return nil
        }
        return words[words.count - 2]
    }

    /// Extracts the last word from a text context string.
    ///
    /// WHY manual extraction:
    /// We use Swift's built-in word boundary detection via enumerateSubstrings
    /// to correctly handle Unicode, apostrophes in French (l'homme), and
    /// other edge cases. This is more reliable than splitting on spaces.
    private func extractLastWord(from text: String) -> String {
        var lastWord = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring {
                lastWord = word
            }
        }
        return lastWord
    }
}
