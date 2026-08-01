// DictusCore/Sources/DictusCore/PersistentLog.swift
// File-based structured logging that persists in the App Group container.
// Readable even when the Xcode debugger disconnects (Signal 9).
import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Persistent file-based logger for debugging without Xcode console.
///
/// WHY this exists:
/// When the app is opened via URL scheme from the keyboard, iOS often kills the
/// debugger connection (Signal 9). os.log messages are lost. This logger writes
/// to a file in the App Group container that can be read later from the Settings
/// screen or from a subsequent debug session.
///
/// WHY App Group container (not Documents):
/// The log file needs to be accessible from both the main app and the keyboard
/// extension for cross-process debugging.
///
/// WHY NSFileCoordinator:
/// Both DictusApp and DictusKeyboard write to the same log file. Without
/// coordination, concurrent writes corrupt the file. NSFileCoordinator
/// serializes cross-process access via the App Group.
public enum PersistentLog {

    /// Process source tag — set once at app/extension launch.
    /// WHY static var (not auto-detected): Bundle.main.bundleIdentifier is
    /// unreliable in keyboard extensions (can return the host app's ID).
    nonisolated(unsafe) public static var source: String = "?"

    /// Human-readable code revision marker, auto-injected at build time.
    ///
    /// The "Inject Git SHA into Info.plist" Xcode build phase writes `GitCommitSHA`
    /// (and `GitBranch`) into every target's built Info.plist on each build. This
    /// computed property reads that value at runtime, so every log export carries
    /// the exact commit the binary was built from with zero manual discipline.
    ///
    /// Fallbacks: returns "unknown" in environments where the Info.plist keys are
    /// missing (unit tests linking DictusCore standalone, Swift Package previews,
    /// or a build done outside the Xcode build phase).
    public static var codeRevision: String {
        let info = Bundle.main.infoDictionary
        let sha = info?["GitCommitSHA"] as? String ?? "unknown"
        if let branch = info?["GitBranch"] as? String, !branch.isEmpty, branch != "unknown" {
            return "\(sha)@\(branch)"
        }
        return sha
    }

    // MARK: - Constants

    /// Maximum log file size in bytes (~200KB = ~1300 lines at ~150 bytes/line).
    /// WHY size-based (not line-based): Checking file size is O(1) via FileManager
    /// attributes, while counting lines requires reading the entire file O(n).
    /// The old line-counting approach caused write amplification on every log() call.
    static let maxFileSize: UInt64 = 200_000

    /// Retention period in seconds (7 days).
    /// WHY 7 days: Keeps logs relevant for debugging recent issues while preventing
    /// unbounded growth. Pruning happens before export (not on every write) because
    /// date parsing is more expensive than the O(1) size check.
    static let retentionPeriod: TimeInterval = 7 * 24 * 3600

    private static let fileName = "mashangxie_debug.log"

    /// Serial queue for ordering writes within a single process.
    /// Cross-process safety is handled by NSFileCoordinator.
    private static let writeQueue = DispatchQueue(label: "com.mashangxie.ios.persistentlog", qos: .utility)

    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    // MARK: - Public API (Structured)

    /// Log a structured event to the persistent file.
    /// This is the primary public API — callers pass typed LogEvent cases.
    public static func log(_ event: LogEvent) {
        let line = event.formatted() + "\n"

        // Forward to os.log for Xcode console visibility
        forwardToOSLog(event)

        guard let url = fileURL else { return }

        writeQueue.async {
            coordinatedAppend(line, to: url)
            coordinatedTrim(url: url)
        }
    }

    /// Read the full log contents.
    public static func read() -> String {
        guard let url = fileURL else { return "(no logs)" }
        return coordinatedRead(from: url)
    }

    /// Clear all logs.
    public static func clear() {
        guard let url = fileURL else { return }
        coordinatedWrite("", to: url)
    }

    /// Remove log entries older than retentionPeriod (7 days).
    /// Called before export to keep exported logs relevant and file size manageable.
    /// WHY not on every write: Date parsing is more expensive than size check.
    /// Pruning before export is sufficient -- size-based trim handles per-write limits.
    public static func pruneOldEntries() {
        guard let url = fileURL else { return }
        pruneOldEntries(url: url, cutoffDate: Date().addingTimeInterval(-retentionPeriod))
    }

    /// Internal pruning with injectable cutoff date (shared by public API and tests).
    static func pruneOldEntries(url: URL, cutoffDate: Date) {
        let formatter = ISO8601DateFormatter()

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            guard let content = try? String(contentsOf: coordURL, encoding: .utf8) else { return }
            let filtered = content
                .components(separatedBy: "\n")
                .filter { line in
                    // Log format: [2026-03-27T10:30:00Z] ...
                    guard line.count > 2,
                          let closeBracket = line.firstIndex(of: "]"),
                          line.first == "[" else {
                        return true // keep unparseable lines
                    }
                    let dateStr = String(line[line.index(after: line.startIndex)..<closeBracket])
                    guard let date = formatter.date(from: dateStr) else {
                        return true // keep unparseable dates
                    }
                    return date > cutoffDate
                }
                .joined(separator: "\n")
            try? filtered.write(to: coordURL, atomically: true, encoding: .utf8)
        }
    }

    /// Export log with device header for sharing.
    /// Returns header + full log content.
    #if canImport(UIKit)
    @MainActor public static func exportContent() -> String {
        pruneOldEntries()  // Remove entries older than 7 days before export
        let iosVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let provider = AppGroup.preferences.string(forKey: SharedKeys.provider) ?? "none"

        let header = buildExportHeader(
            iosVersion: iosVersion,
            appVersion: appVersion,
            buildNumber: buildNumber,
            deviceModel: deviceModel,
            provider: provider,
            codeRevision: codeRevision
        )
        return header + read()
    }
    #endif

    /// Testable header builder — accepts injected values so tests don't need UIDevice.
    static func buildExportHeader(
        iosVersion: String,
        appVersion: String,
        buildNumber: String,
        deviceModel: String,
        provider: String,
        codeRevision: String = PersistentLog.codeRevision
    ) -> String {
        "Mashangxie Debug Log\niOS \(iosVersion) | App \(appVersion) (\(buildNumber)) | rev \(codeRevision) | \(deviceModel) | Model: \(provider)\n---\n"
    }

    // MARK: - Legacy API (Deprecated)

    /// Legacy free-text log method. Use `log(_ event: LogEvent)` instead.
    @available(*, deprecated, message: "Use log(_ event: LogEvent) instead")
    public static func log(_ message: String, function: String = #function) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(function): \(message)\n"

        if #available(iOS 14.0, *) {
            AppLogger.app.info("\(message, privacy: .public)")
        }

        guard let url = fileURL else { return }

        writeQueue.async {
            coordinatedAppend(entry, to: url)
            coordinatedTrim(url: url)
        }
    }

    // MARK: - NSFileCoordinator Helpers

    private static func coordinatedAppend(_ text: String, to url: URL) {
        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error) { coordURL in
            if !FileManager.default.fileExists(atPath: coordURL.path) {
                FileManager.default.createFile(atPath: coordURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: coordURL) else { return }
            handle.seekToEndOfFile()
            if let data = text.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }

    private static func coordinatedRead(from url: URL) -> String {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var result = "(no logs)"

        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordURL in
            if let content = try? String(contentsOf: coordURL, encoding: .utf8) {
                result = content
            }
        }
        return result
    }

    private static func coordinatedWrite(_ text: String, to url: URL) {
        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            try? text.write(to: coordURL, atomically: true, encoding: .utf8)
        }
    }

    private static func coordinatedTrim(url: URL) {
        // O(1) size check -- no file read needed
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxFileSize else { return }

        // Only read file when we actually need to trim
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            guard let data = try? Data(contentsOf: coordURL) else { return }
            // Keep the last maxFileSize bytes (most recent logs)
            let trimmedData = data.suffix(Int(maxFileSize))
            // Find first newline in trimmed data to avoid partial first line
            if let newlineIndex = trimmedData.firstIndex(of: UInt8(ascii: "\n")) {
                let cleanData = trimmedData.suffix(from: trimmedData.index(after: newlineIndex))
                try? cleanData.write(to: coordURL)
            } else {
                try? trimmedData.write(to: coordURL)
            }
        }
    }

    // MARK: - os.log Forwarding

    private static func forwardToOSLog(_ event: LogEvent) {
        guard #available(iOS 14.0, *) else { return }

        let logger: Logger
        switch event.subsystem {
        case .dictation, .audio, .transcription, .model, .lifecycle:
            logger = AppLogger.app
        case .keyboard:
            logger = AppLogger.keyboard
        }

        // WHY privacy: .public — LogEvent is privacy-safe by design (no user text,
        // no keystrokes). Without .public, os.log masks ALL interpolated values as
        // <private> in the Xcode console, making debugging impossible.
        let msg = "\(event.name) \(event.message)"
        switch event.level {
        case .debug: logger.debug("\(msg, privacy: .public)")
        case .info: logger.info("\(msg, privacy: .public)")
        case .warning: logger.warning("\(msg, privacy: .public)")
        case .error: logger.error("\(msg, privacy: .public)")
        }
    }

    // MARK: - Test Helpers

    /// Append text to an arbitrary URL (for unit tests with temp files).
    static func appendForTesting(_ text: String, to url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        if let data = text.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    }

    /// Read from an arbitrary URL (for unit tests with temp files).
    static func readForTesting(from url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "(no logs)"
    }

    /// Check if a file exceeds maxFileSize (for unit tests).
    static func shouldTrimForTesting(url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return false }
        return size > maxFileSize
    }

    /// Trim an arbitrary URL using size-based logic (for unit tests).
    static func trimBySizeForTesting(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > maxFileSize else { return }

        guard let data = try? Data(contentsOf: url) else { return }
        let trimmedData = data.suffix(Int(maxFileSize))
        if let newlineIndex = trimmedData.firstIndex(of: UInt8(ascii: "\n")) {
            let cleanData = trimmedData.suffix(from: trimmedData.index(after: newlineIndex))
            try? cleanData.write(to: url)
        } else {
            try? trimmedData.write(to: url)
        }
    }

    /// Prune old entries from an arbitrary URL with custom cutoff (for unit tests).
    static func pruneOldEntriesForTesting(url: URL, cutoffDate: Date) {
        pruneOldEntries(url: url, cutoffDate: cutoffDate)
    }

    /// Clear an arbitrary URL (for unit tests).
    static func clearForTesting(url: URL) {
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    /// Expose maxFileSize for test assertions.
    static var testableMaxFileSize: UInt64 { maxFileSize }
}
