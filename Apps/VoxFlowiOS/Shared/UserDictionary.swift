// DictusCore/Sources/DictusCore/UserDictionary.swift
// Persistent user-learned words dictionary stored in App Group.
import Foundation

/// Stores words the user has taught the keyboard through usage patterns.
///
/// HOW WORDS ARE LEARNED:
/// 1. Rejection learning: user types "helo" → autocorrected to "hello" → user
///    presses backspace to undo → "helo" is immediately learned (strong signal).
/// 2. Repetition learning: user types an unknown word multiple times → after
///    `repetitionThreshold` occurrences, the word is learned.
///
/// WHY App Group UserDefaults:
/// The dictionary must be shared between DictusApp and DictusKeyboard extension.
/// UserDefaults via App Group is the simplest cross-process storage on iOS.
/// For a typical user dictionary (hundreds to low thousands of words), the
/// serialization overhead is negligible.
///
/// WHY a separate class in DictusCore:
/// Both the keyboard extension (for learning + lookup) and the main app
/// (for a future "manage learned words" UI) need access to the same data.
public final class UserDictionary {

    /// Singleton shared instance. Uses App Group storage.
    nonisolated(unsafe) public static let shared = UserDictionary()

    /// Key in App Group UserDefaults for the learned words dictionary.
    /// Stored as [String: Int] where key = lowercase word, value = usage count.
    private static let storageKey = "dictus.userDictionary"

    /// Key for the repetition counter (words being "observed" before learning).
    /// Stored as [String: Int] where key = lowercase word, value = times typed.
    private static let pendingKey = "dictus.userDictionary.pending"

    /// Number of times an unknown word must be typed/rejected before it's learned.
    /// 1 = learn immediately. Safe now that autocorrect undo requires an intentional
    /// tap in the suggestion bar (no more accidental backspace-undo learning).
    public static let repetitionThreshold = 1

    /// Maximum number of learned words. When exceeded, the least-used words
    /// are dropped. 1000 words ≈ 30 KB in UserDefaults — negligible for memory.
    /// Generous cap for personal vocabulary (names, slang, jargon, brands).
    /// Prevents unbounded growth from accidental learning over months/years.
    public static let maxLearnedWords = 1000

    /// In-memory cache of learned words. Synced to UserDefaults on mutation.
    private var learnedWords: [String: Int] = [:]

    /// Temporary counter for words being observed (not yet learned).
    private var pendingWords: [String: Int] = [:]

    private init() {
        loadFromDefaults()
    }

    // MARK: - Public API

    /// Whether a word has been learned by the user.
    public func isLearned(_ word: String) -> Bool {
        learnedWords[word.lowercased()] != nil
    }

    /// All learned words with their usage counts.
    /// Useful for a future "manage dictionary" UI in the app.
    public var allLearnedWords: [String: Int] {
        learnedWords
    }

    /// Number of learned words.
    public var count: Int { learnedWords.count }

    /// Learn a word immediately (e.g., after user rejects autocorrection).
    /// The word is stored lowercase. If already learned, increments usage count.
    public func learn(_ word: String) {
        let key = word.lowercased()
        guard !key.isEmpty, key.count > 1 else { return }
        learnedWords[key, default: 0] += 1
        // Remove from pending if it was being tracked
        pendingWords.removeValue(forKey: key)
        saveToDefaults()
    }

    /// Record that an unknown word was typed. If it reaches the repetition
    /// threshold, it's automatically learned. Returns true if the word was
    /// just learned (crossed the threshold this call).
    @discardableResult
    public func recordUsage(_ word: String) -> Bool {
        let key = word.lowercased()
        guard !key.isEmpty, key.count > 1 else { return false }

        // Already learned — just bump usage count
        if learnedWords[key] != nil {
            learnedWords[key, default: 0] += 1
            saveToDefaults()
            return false
        }

        // Increment pending counter
        pendingWords[key, default: 0] += 1

        let pendingCount = pendingWords[key, default: 0]
        if pendingCount >= Self.repetitionThreshold {
            // Threshold reached — promote to learned
            learnedWords[key] = pendingCount
            pendingWords.removeValue(forKey: key)
            saveToDefaults()
            print("[UserDictionary] Learned '\(key)' after \(Self.repetitionThreshold) uses")
            return true
        }

        savePendingToDefaults()
        return false
    }

    /// Remove a learned word (e.g., user removes it from dictionary management UI).
    public func forget(_ word: String) {
        let key = word.lowercased()
        learnedWords.removeValue(forKey: key)
        pendingWords.removeValue(forKey: key)
        saveToDefaults()
    }

    /// Remove all learned words and pending observations.
    /// Useful for a "Reset keyboard dictionary" option in settings.
    public func resetAll() {
        learnedWords.removeAll()
        pendingWords.removeAll()
        saveToDefaults()
        print("[UserDictionary] Reset — all learned words cleared")
    }

    /// Reload from App Group (useful if the other process updated the dictionary).
    public func reload() {
        loadFromDefaults()
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        let defaults = AppGroup.preferences
        learnedWords = defaults.dictionary(forKey: Self.storageKey) as? [String: Int] ?? [:]
        pendingWords = defaults.dictionary(forKey: Self.pendingKey) as? [String: Int] ?? [:]
    }

    private func saveToDefaults() {
        // Evict least-used words if we exceed the cap.
        // Keeps the dictionary bounded so it can't grow indefinitely from
        // accidental learning. Drops the words with the lowest usage count.
        if learnedWords.count > Self.maxLearnedWords {
            let sorted = learnedWords.sorted { $0.value < $1.value }
            let toRemove = learnedWords.count - Self.maxLearnedWords
            for (key, _) in sorted.prefix(toRemove) {
                learnedWords.removeValue(forKey: key)
            }
            print("[UserDictionary] Evicted \(toRemove) least-used words (cap: \(Self.maxLearnedWords))")
        }

        let defaults = AppGroup.preferences
        defaults.set(learnedWords, forKey: Self.storageKey)
        defaults.set(pendingWords, forKey: Self.pendingKey)
    }

    private func savePendingToDefaults() {
        AppGroup.preferences.set(pendingWords, forKey: Self.pendingKey)
    }
}
