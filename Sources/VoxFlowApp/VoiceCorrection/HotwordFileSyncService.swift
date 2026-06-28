import AppKit
import Darwin
import Foundation
import VoxFlowVoiceCorrection

/// Result of a hotword file sync operation, used for logging and toast feedback.
struct HotwordFileSyncResult: Equatable {
    let source: HotwordFileSyncSource
    let linesRead: Int
    let validHotwords: Int
    let duplicates: Int
    let restoredFromBlocklist: Int
    let failures: Int

    static let empty = HotwordFileSyncResult(
        source: .initial,
        linesRead: 0,
        validHotwords: 0,
        duplicates: 0,
        restoredFromBlocklist: 0,
        failures: 0
    )
}

enum HotwordFileSyncSource: String, Equatable {
    case initial
    case fileWatcher
    case manualReload
    case appWriteback
}

/// Parses and synchronizes the `hotwords.txt` file with the hotword repository.
///
/// Design (from research-decisions.md §4):
/// - One hotword per line; empty lines and `#` comments ignored.
/// - File save triggers reload → repository sync (debounced).
/// - App-internal changes write back atomically with debounce.
/// - Normalized snapshot/hash/generation prevents sync loops.
/// - Manually writing a blocklisted hotword back to file = user restore.
final class HotwordFileSyncService {
    private static let logger = AppLogger.general

    private let fileURL: URL
    private let repository: any CorrectionTargetRepository
    private let fileManager: FileManager
    private let writebackQueue: DispatchQueue
    private let fileWatcherQueue: DispatchQueue
    private let writebackDelay: TimeInterval
    private let reloadDebounceDelay: TimeInterval

    /// Generation counter to distinguish app writebacks from external saves.
    private var generation: Int64 = 0
    /// The last file content hash we processed, to skip no-op reloads.
    private var lastProcessedHash: String?
    private var writebackWorkItem: DispatchWorkItem?
    private var reloadWorkItem: DispatchWorkItem?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileWatcherDescriptor: CInt?
    private var onSync: ((HotwordFileSyncResult) -> Void)?

    init(
        fileURL: URL,
        repository: any CorrectionTargetRepository,
        fileManager: FileManager = .default,
        writebackQueue: DispatchQueue = DispatchQueue(label: "com.voxflow.hotwords.writeback"),
        fileWatcherQueue: DispatchQueue = DispatchQueue(label: "com.voxflow.hotwords.filewatcher"),
        writebackDelay: TimeInterval = 0.5,
        reloadDebounceDelay: TimeInterval = 0.25
    ) {
        self.fileURL = fileURL
        self.repository = repository
        self.fileManager = fileManager
        self.writebackQueue = writebackQueue
        self.fileWatcherQueue = fileWatcherQueue
        self.writebackDelay = writebackDelay
        self.reloadDebounceDelay = reloadDebounceDelay
    }

    deinit {
        stopWatching()
    }

    // MARK: - File parsing

    /// Parses hotword file content into a list of hotword strings.
    /// Empty lines and lines starting with `#` are ignored.
    /// Duplicates are deduplicated by normalized form, keeping the first writing.
    static func parse(_ content: String) -> [String] {
        var seen = Set<String>()
        var hotwords: [String] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let normalized = CorrectionTargetTerm.normalize(trimmed)
            guard seen.insert(normalized).inserted else { continue }
            hotwords.append(trimmed)
        }
        return hotwords
    }

    // MARK: - File → Database sync

    /// Starts the hotword file sync lifecycle:
    /// 1. ensure `hotwords.txt` exists;
    /// 2. import current file content into the repository;
    /// 3. watch future file saves and reload with debounce.
    func startWatching(onSync: ((HotwordFileSyncResult) -> Void)? = nil) throws {
        self.onSync = onSync
        try ensureFileExists()
        let initialResult = try reloadFromFile(source: .initial)
        onSync?(initialResult)
        try installFileWatcher()
        Self.logger.info("hotwords_file_watcher_started path=\(fileURL.path)")
    }

    /// Stops file watching and cancels pending debounced reloads.
    func stopWatching() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        fileWatcher?.cancel()
        fileWatcher = nil
        fileWatcherDescriptor = nil
        Self.logger.debug("hotwords_file_watcher_stopped path=\(fileURL.path)")
    }

    /// Ensures the hotword file exists; creates it from current repository state if missing.
    func ensureFileExists() throws {
        guard !fileManager.fileExists(atPath: fileURL.path) else { return }
        let hotwords = try repository.listHotwords()
        let content = hotwords.map(\.text).joined(separator: "\n") + "\n"
        try writeContentAtomically(content)
        Self.logger.info("hotwords_file_created path=\(fileURL.path) count=\(hotwords.count)")
    }

    /// Reloads the file and syncs parsed hotwords to the repository.
    /// Returns a sync result with statistics for logging and toast feedback.
    func reloadFromFile(source: HotwordFileSyncSource = .fileWatcher) throws -> HotwordFileSyncResult {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            Self.logger.error("hotwords_file_read_failed path=\(fileURL.path) error=\(error)")
            return HotwordFileSyncResult(
                source: source,
                linesRead: 0,
                validHotwords: 0,
                duplicates: 0,
                restoredFromBlocklist: 0,
                failures: 1
            )
        }

        let hash = contentStableHash(content)
        if let lastProcessedHash, hash == lastProcessedHash {
            Self.logger.debug("hotwords_file_skipped_no_change hash=\(hash)")
            return HotwordFileSyncResult(
                source: source,
                linesRead: 0,
                validHotwords: 0,
                duplicates: 0,
                restoredFromBlocklist: 0,
                failures: 0
            )
        }
        lastProcessedHash = hash

        let lines = content.components(separatedBy: .newlines)
        let parsed = Self.parse(content)
        var seenNormalized = Set<String>()
        let duplicates = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { return false }
            return !seenNormalized.insert(CorrectionTargetTerm.normalize(trimmed)).inserted
        }.count

        var validCount = 0
        var restoredCount = 0
        var failures = 0

        let existingHotwords = try repository.listHotwords()
        let existingNormalized = Set(existingHotwords.map { $0.normalizedText })

        for hotword in parsed {
            let normalized = CorrectionTargetTerm.normalize(hotword)
            if existingNormalized.contains(normalized) {
                continue
            }
            do {
                let target = CorrectionTargetTerm(
                    text: hotword,
                    lifecycle: .active,
                    source: .imported
                )
                let saved = try repository.saveHotwordIfNotBlocklisted(target)
                if saved {
                    validCount += 1
                } else {
                    restoredCount += 1
                    try repository.unblocklist(normalizedText: normalized)
                    try repository.save(target)
                }
            } catch {
                failures += 1
                Self.logger.error("hotwords_file_sync_failed word=\(hotword) error=\(error)")
            }
        }

        Self.logger.info(
            "hotwords_file_synced source=\(source.rawValue) lines=\(lines.count) " +
            "valid=\(validCount) duplicates=\(duplicates) restored=\(restoredCount) failures=\(failures)"
        )

        return HotwordFileSyncResult(
            source: source,
            linesRead: lines.count,
            validHotwords: validCount,
            duplicates: duplicates,
            restoredFromBlocklist: restoredCount,
            failures: failures
        )
    }

    // MARK: - Database → File writeback

    /// Writes current hotwords from the repository back to the file.
    /// Uses debounce to coalesce rapid changes. Uses atomic write to prevent
    /// partial reads by the file watcher. Increments generation to help the
    /// watcher distinguish app writebacks from external saves.
    func writeBackFromRepository(debounced: Bool = true) {
        if debounced {
            writebackWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.performWriteback()
            }
            writebackWorkItem = workItem
            writebackQueue.asyncAfter(deadline: .now() + writebackDelay, execute: workItem)
        } else {
            performWriteback()
        }
    }

    private func performWriteback() {
        do {
            let hotwords = try repository.listHotwords()
            let content = hotwords.map(\.text).joined(separator: "\n") + "\n"
            generation += 1
            try writeContentAtomically(content)
            let hash = contentStableHash(content)
            lastProcessedHash = hash
            Self.logger.info("hotwords_file_writeback generation=\(generation) count=\(hotwords.count)")
        } catch {
            Self.logger.error("hotwords_file_writeback_failed error=\(error)")
        }
    }

    /// Returns the current generation counter, used by file watchers to
    /// distinguish app writebacks from external saves.
    var currentGeneration: Int64 { generation }

    /// Resets the last processed hash, forcing the next reload to process
    /// even if content is unchanged. Used after app writebacks.
    func resetProcessedHash() {
        lastProcessedHash = nil
    }

    // MARK: - System open

    /// Opens the hotword file in the system default application.
    func openInSystemEditor() {
        NSWorkspace.shared.open(fileURL)
    }

    // MARK: - Private

    private func installFileWatcher() throws {
        fileWatcher?.cancel()
        fileWatcher = nil
        fileWatcherDescriptor = nil

        let descriptor = Darwin.open(fileURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            let code = errno
            Self.logger.error("hotwords_file_watcher_open_failed path=\(fileURL.path) errno=\(code)")
            throw HotwordFileSyncError.openWatcherFailed(errno: code)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: fileWatcherQueue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReloadFromWatcher()
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        fileWatcherDescriptor = descriptor
        fileWatcher = source
        source.resume()
    }

    private func scheduleReloadFromWatcher() {
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try self.ensureFileExists()
                let result = try self.reloadFromFile(source: .fileWatcher)
                self.onSync?(result)
                try self.installFileWatcher()
            } catch {
                Self.logger.error("hotwords_file_watcher_reload_failed path=\(self.fileURL.path) error=\(error)")
            }
        }
        reloadWorkItem = workItem
        fileWatcherQueue.asyncAfter(deadline: .now() + reloadDebounceDelay, execute: workItem)
    }

    private func writeContentAtomically(_ content: String) throws {
        let data = Data(content.utf8)
        try data.write(to: fileURL, options: .atomic)
    }

    private func contentStableHash(_ content: String) -> String {
        var hash = Hasher()
        hash.combine(content)
        return String(hash.finalize(), radix: 16)
    }
}

enum HotwordFileSyncError: Error, Equatable {
    case openWatcherFailed(errno: Int32)
}
