// DictusCore/Sources/DictusCore/AutocorrectDebugLog.swift
// Debug-only autocorrect instrumentation.
// The ENTIRE body of this file is wrapped in #if DEBUG — in Release builds,
// nothing below exists in the binary. The API is also no-op by default in
// Debug builds until the user toggles SharedKeys.autocorrectDebugLogging.
//
// WHY this is separate from LogEvent:
// LogEvent is privacy-safe by design — cases like keyboardTextInserted have NO
// content parameter. Adding events that log user-typed text would break that
// invariant. AutocorrectDebugLog is the explicit, quarantined exception:
// it logs user text ONLY in Debug builds ONLY when explicitly enabled.

import Foundation

/// Debug-only logger for autocorrect decisions. Release builds contain no code.
///
/// WHY #if DEBUG around the whole type:
/// Xcode sets the DEBUG flag automatically for the Run/Debug configuration
/// (dev builds via Run button) but NOT for Release/Archive configuration
/// (TestFlight + App Store submissions). This guarantees zero risk of user
/// text being logged in shipped builds — the code physically does not exist
/// in the production binary. There is no runtime flag that can override this.
#if DEBUG
public enum AutocorrectDebugLog {

    /// Whether debug logging is enabled at runtime.
    /// Read from App Group so the toggle persists across keyboard/app launches.
    /// Defaults to false — must be explicitly enabled in Settings.
    private static var enabled: Bool {
        AppGroup.preferences.bool(forKey: SharedKeys.autocorrectDebugLogging)
    }

    /// Reusable ISO timestamp formatter (same as PersistentLog).
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Event API

    /// An autocorrect decision was made on spacebar press.
    /// - Parameters:
    ///   - original: the word as typed by the user
    ///   - corrected: the word inserted into the text (may equal original if no correction)
    ///   - branch: which pipeline branch decided this ("accent", "contraction",
    ///             "split-boundary", "split-bigram", "trie", "trie-ngram-rerank", "no-op")
    ///   - prevWord: the previous complete word for context (or nil)
    public static func autocorrectDecision(
        original: String,
        corrected: String,
        branch: String,
        prevWord: String?
    ) {
        guard enabled else { return }
        let prev = prevWord.map { "\"\($0)\"" } ?? "nil"
        write("AUTOCORRECT branch=\(branch) orig=\"\(original)\" corr=\"\(corrected)\" prev=\(prev)")
    }

    /// Autocorrect was skipped for a word.
    /// - Parameters:
    ///   - word: the word that was not corrected
    ///   - reason: why ("already-valid", "contains-digit", "rejected-by-user",
    ///             "disabled", "no-candidate")
    public static func autocorrectSkipped(word: String, reason: String) {
        guard enabled else { return }
        write("AUTOCORRECT-SKIP word=\"\(word)\" reason=\(reason)")
    }

    /// The trySplit() method's candidate evaluation summary.
    /// Logged once per spellCheck call that reaches the split stage.
    public static func splitEvaluation(
        word: String,
        boundaryBest: String?,
        bigramBest: String?,
        winner: String?
    ) {
        guard enabled else { return }
        let boundary = boundaryBest.map { "\"\($0)\"" } ?? "nil"
        let bigram = bigramBest.map { "\"\($0)\"" } ?? "nil"
        let win = winner.map { "\"\($0)\"" } ?? "nil"
        write("SPLIT word=\"\(word)\" boundary=\(boundary) bigram=\(bigram) → \(win)")
    }

    /// N-gram rerank changed the correction.
    /// Useful to diagnose bigram-based overrides that surprise the user.
    public static func bigramRerank(
        word: String,
        prevWord: String,
        before: String,
        after: String,
        beforeScore: UInt16,
        afterScore: UInt16
    ) {
        guard enabled else { return }
        write("BIGRAM-RERANK word=\"\(word)\" prev=\"\(prevWord)\" "
            + "\"\(before)\"(\(beforeScore)) → \"\(after)\"(\(afterScore))")
    }

    /// Trie candidates returned by the spell check engine for a given word.
    /// Logged when the trie produces corrections, so we can see the full candidate
    /// list (not just the winner) and diagnose cases where the trie picks the
    /// "wrong" candidate (e.g., ckavier → clapier when clavier exists).
    public static func trieCandidates(word: String, correction: String,
                                      correctionFreq: UInt16,
                                      alternatives: [(String, UInt16)]) {
        guard enabled else { return }
        let alts = alternatives
            .map { "\"\($0.0)\"(freq=\($0.1))" }
            .joined(separator: ", ")
        write("TRIE-CANDIDATES word=\"\(word)\" winner=\"\(correction)\"(freq=\(correctionFreq)) alts=[\(alts)]")
    }

    /// The autocorrect decision was actually applied to the text document
    /// (user pressed space and the word was replaced). Distinct from
    /// autocorrectDecision which also fires for suggestion-bar previews.
    public static func autocorrectApplied(original: String, corrected: String, prevWord: String?) {
        guard enabled else { return }
        let prev = prevWord.map { "\"\($0)\"" } ?? "nil"
        write("APPLIED orig=\"\(original)\" → \"\(corrected)\" prev=\(prev)")
    }

    /// The user rejected an autocorrection by tapping the "undo" slot in the
    /// suggestion bar. Critical for discovering which corrections feel wrong
    /// to users in real usage.
    public static func autocorrectUndone(original: String, rejected: String) {
        guard enabled else { return }
        write("UNDO orig=\"\(original)\" rejected=\"\(rejected)\"")
    }

    /// Free-form note (use sparingly — prefer typed events above).
    public static func note(_ message: String) {
        guard enabled else { return }
        write("NOTE \(message)")
    }

    // MARK: - Writing

    private static func write(_ body: String) {
        let timestamp = isoFormatter.string(from: Date())
        let src = PersistentLog.source
        let line = "[\(timestamp)] DEBUG   [keyboard] <\(src)> \(body)\n"
        appendToLogFile(line)
    }

    /// Appends to the same file PersistentLog uses, so logs appear together in exports.
    private static func appendToLogFile(_ line: String) {
        guard let url = AppGroup.containerURL?.appendingPathComponent("dictus_debug.log") else { return }
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error) { coordURL in
            if !FileManager.default.fileExists(atPath: coordURL.path) {
                FileManager.default.createFile(atPath: coordURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: coordURL) else { return }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }
}
#endif
