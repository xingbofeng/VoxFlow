import XCTest
@testable import VoxFlowApp

final class ScreenRecordingFileStorageTests: XCTestCase {
    private func makeStorage() throws -> (storage: ScreenRecordingFileStorage, paths: ApplicationSupportPaths, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowRec-\(UUID().uuidString)", isDirectory: true)
        let paths = ApplicationSupportPaths(applicationSupportDirectory: root)
        try paths.ensureDirectories()
        return (ScreenRecordingFileStorage(paths: paths), paths, root)
    }

    func testFinalizeMovesTemporaryToFinalMP4() throws {
        let (storage, _, root) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = storage.makeID()
        let temp = storage.temporaryURL(for: id)
        let final = storage.finalURL(for: id)
        try Data("video-bytes".utf8).write(to: temp)

        try storage.finalize(temporaryURL: temp, finalURL: final)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path), "临时文件应被移走")
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.path), "最终 mp4 应存在")
        XCTAssertTrue(final.pathExtension == "mp4")
        XCTAssertEqual(storage.fileSize(at: final), 11)
    }

    func testFinalizeFailsWhenTemporaryMissing() throws {
        let (storage, _, root) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = storage.makeID()
        let temp = storage.temporaryURL(for: id)
        let final = storage.finalURL(for: id)

        XCTAssertThrowsError(try storage.finalize(temporaryURL: temp, finalURL: final))
        XCTAssertFalse(FileManager.default.fileExists(atPath: final.path))
    }

    func testRemoveTemporaryDeletesFile() throws {
        let (storage, _, root) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = storage.makeID()
        let temp = storage.temporaryURL(for: id)
        try Data("tmp".utf8).write(to: temp)

        storage.removeTemporary(at: temp)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }

    func testRemoveTemporaryIsNoopWhenMissing() throws {
        let (storage, _, root) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let temp = storage.temporaryURL(for: "missing")
        storage.removeTemporary(at: temp)  // 不应抛错
    }

    func testFinalizeOverwritesExistingFinalFile() throws {
        let (storage, _, root) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = storage.makeID()
        let final = storage.finalURL(for: id)
        try Data("old".utf8).write(to: final)

        let temp = storage.temporaryURL(for: id)
        try Data("new-content".utf8).write(to: temp)
        try storage.finalize(temporaryURL: temp, finalURL: final)

        XCTAssertEqual(storage.fileSize(at: final), 11)
    }

    func testCleanupStaleTemporaryFilesRemovesOldEntries() throws {
        let (storage, paths, root) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let stale = paths.screenRecordingTemporaryDirectory.appendingPathComponent("stale.tmp.mp4")
        try Data("stale".utf8).write(to: stale)
        // 把修改时间设为很久以前。
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: stale.path)

        let fresh = paths.screenRecordingTemporaryDirectory.appendingPathComponent("fresh.tmp.mp4")
        try Data("fresh".utf8).write(to: fresh)

        storage.cleanupStaleTemporaryFiles(olderThan: Date(timeIntervalSinceNow: -60))

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "过期临时文件应被清理")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path), "新临时文件应保留")
    }

    func testThumbnailURLUsesJpgExtension() throws {
        let (storage, _, root) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = storage.thumbnailURL(for: "abc")
        XCTAssertEqual(url.pathExtension, "jpg")
        XCTAssertTrue(url.lastPathComponent == "abc.jpg")
    }
}
