import Foundation
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

/// Tests for HotwordFileSyncService — hotwords.txt parsing, sync, writeback,
/// and blocklist restoration.
///
/// Covers tasks 3.1-3.10 from redesign-vocabulary-hotwords-learning.
final class HotwordFileSyncServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileURL: URL!
    private var queue: DatabaseQueue!
    private var repository: SQLiteCorrectionTargetRepository!
    private var service: HotwordFileSyncService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        fileURL = tempDirectory.appendingPathComponent("hotwords.txt")
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        service = HotwordFileSyncService(
            fileURL: fileURL,
            repository: repository,
            writebackQueue: DispatchQueue(label: "test.hotwords.writeback"),
            writebackDelay: 0
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        service = nil
        repository = nil
        queue = nil
        fileURL = nil
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Task 3.2: Parsing

    func testParseIgnoresEmptyLinesAndComments() {
        let content = """
        VoxFlow

        # This is a comment
        Qwen3-ASR
        # Another comment

        ContextBoost
        """
        let hotwords = HotwordFileSyncService.parse(content)
        XCTAssertEqual(hotwords, ["VoxFlow", "Qwen3-ASR", "ContextBoost"])
    }

    func testParseDeduplicatesByNormalizedForm() {
        let content = """
        VoxFlow
        voxflow
        VOXFLOW
        Qwen3-ASR
        """
        let hotwords = HotwordFileSyncService.parse(content)
        XCTAssertEqual(hotwords, ["VoxFlow", "Qwen3-ASR"])
    }

    // MARK: - Task 3.1 & 3.3: File existence and system open

    func testEnsureFileExistsCreatesFromRepository() throws {
        try repository.save(makeHotword(text: "VoxFlow"))
        try repository.save(makeHotword(text: "Qwen3-ASR"))

        try service.ensureFileExists()

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("VoxFlow"))
        XCTAssertTrue(content.contains("Qwen3-ASR"))
    }

    func testEnsureFileExistsNoOpIfFileExists() throws {
        try Data("Existing\n".utf8).write(to: fileURL)
        try service.ensureFileExists()

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(content, "Existing\n")
    }

    // MARK: - Task 3.4: File save triggers sync

    func testReloadFromFileSyncsNewHotwordsToRepository() throws {
        let content = """
        # My hotwords
        VoxFlow
        Qwen3-ASR
        """
        try Data(content.utf8).write(to: fileURL)

        let result = try service.reloadFromFile(source: .manualReload)

        XCTAssertEqual(result.validHotwords, 2)
        XCTAssertEqual(result.failures, 0)

        let hotwords = try repository.listHotwords()
        XCTAssertEqual(Set(hotwords.map(\.text)), ["VoxFlow", "Qwen3-ASR"])
    }

    func testReloadFromFileSkipsAlreadyExistingHotwords() throws {
        try repository.save(makeHotword(text: "VoxFlow"))
        let content = "VoxFlow\nQwen3-ASR\n"
        try Data(content.utf8).write(to: fileURL)

        let result = try service.reloadFromFile(source: .manualReload)

        XCTAssertEqual(result.validHotwords, 1)
        let hotwords = try repository.listHotwords()
        XCTAssertEqual(hotwords.count, 2)
    }

    func testReloadFromFileCountsNormalizedDuplicates() throws {
        let content = """
        VoxFlow
        voxflow
          VOXFLOW
        Qwen3-ASR
        """
        try Data(content.utf8).write(to: fileURL)

        let result = try service.reloadFromFile(source: .manualReload)

        XCTAssertEqual(result.duplicates, 2)
        XCTAssertEqual(result.validHotwords, 2)
        XCTAssertEqual(Set(try repository.listHotwords().map(\.text)), ["VoxFlow", "Qwen3-ASR"])
    }

    // MARK: - Task 3.6: Prevent sync loops

    func testReloadSkipsWhenHashUnchanged() throws {
        let content = "VoxFlow\n"
        try Data(content.utf8).write(to: fileURL)

        _ = try service.reloadFromFile(source: .manualReload)
        let result = try service.reloadFromFile(source: .manualReload)

        XCTAssertEqual(result.linesRead, 0)
        XCTAssertEqual(result.validHotwords, 0)
    }

    func testWriteBackUpdatesHashToPreventLoop() throws {
        try repository.save(makeHotword(text: "VoxFlow"))

        service.writeBackFromRepository(debounced: false)

        // Wait for writeback to complete
        let expectation = expectation(description: "writeback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        let result = try service.reloadFromFile(source: .fileWatcher)
        // Should skip because writeBack set the hash
        XCTAssertEqual(result.linesRead, 0)
    }

    // MARK: - Task 3.5: Atomic writeback

    func testWriteBackWritesAllHotwords() throws {
        try repository.save(makeHotword(text: "VoxFlow"))
        try repository.save(makeHotword(text: "Qwen3-ASR"))
        try repository.save(makeHotword(text: "ContextBoost"))

        service.writeBackFromRepository(debounced: false)

        let expectation = expectation(description: "writeback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("VoxFlow"))
        XCTAssertTrue(content.contains("Qwen3-ASR"))
        XCTAssertTrue(content.contains("ContextBoost"))
    }

    // MARK: - Task 3.9: Blocklist restoration

    func testManuallyRestoringBlocklistedHotwordUnblocklists() throws {
        let target = makeHotword(text: "PostgreSQL")
        try repository.save(target)
        try repository.blocklist(id: target.id)

        // User writes it back to file
        let content = "PostgreSQL\n"
        try Data(content.utf8).write(to: fileURL)

        let result = try service.reloadFromFile(source: .manualReload)

        XCTAssertEqual(result.restoredFromBlocklist, 1)
        let hotwords = try repository.listHotwords()
        XCTAssertTrue(hotwords.contains { $0.text == "PostgreSQL" })
    }

    // MARK: - Task 3.10: Error handling

    func testReloadFromFileReturnsFailureWhenFileMissing() throws {
        let result = try service.reloadFromFile(source: .manualReload)

        XCTAssertEqual(result.failures, 1)
        XCTAssertEqual(result.validHotwords, 0)
    }

    // MARK: - Production lifecycle

    func testStartWatchingImportsExistingFileContent() throws {
        try Data("VoxFlow\nQwen3-ASR\n".utf8).write(to: fileURL)

        try service.startWatching()
        defer { service.stopWatching() }

        let hotwords = try repository.listHotwords().map(\.text)
        XCTAssertEqual(Set(hotwords), ["VoxFlow", "Qwen3-ASR"])
    }

    func testWatcherReloadsWhenFileChanges() throws {
        try service.startWatching()
        defer { service.stopWatching() }
        let expectation = expectation(description: "watcher reloads hotwords.txt")
        expectation.assertForOverFulfill = false

        service.stopWatching()
        service = HotwordFileSyncService(
            fileURL: fileURL,
            repository: repository,
            writebackQueue: DispatchQueue(label: "test.hotwords.writeback.reload"),
            fileWatcherQueue: DispatchQueue(label: "test.hotwords.filewatcher.reload"),
            writebackDelay: 0,
            reloadDebounceDelay: 0.05
        )
        try service.startWatching { result in
            if result.source == .fileWatcher, result.validHotwords == 1 {
                expectation.fulfill()
            }
        }

        try Data("ContextBoost\n".utf8).write(to: fileURL)

        wait(for: [expectation], timeout: 2)
        let hotwords = try repository.listHotwords().map(\.text)
        XCTAssertTrue(hotwords.contains("ContextBoost"))
    }

    // MARK: - Helpers

    private func makeHotword(text: String) -> CorrectionTargetTerm {
        CorrectionTargetTerm(
            text: text,
            lifecycle: .active,
            source: .manual
        )
    }
}
