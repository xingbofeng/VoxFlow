import XCTest
@testable import VoxFlowApp

final class ApplicationSupportPathsTests: XCTestCase {
    func testPathsUseVoxFlowApplicationSupportLayout() {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        let paths = ApplicationSupportPaths(applicationSupportDirectory: applicationSupportURL)

        XCTAssertEqual(paths.rootDirectory.path, "/tmp/Application Support/VoxFlow")
        XCTAssertEqual(paths.databaseURL.path, "/tmp/Application Support/VoxFlow/voxflow.sqlite")
        XCTAssertEqual(paths.exportsDirectory.path, "/tmp/Application Support/VoxFlow/Exports")
        XCTAssertEqual(paths.modelsDirectory.path, "/tmp/Application Support/VoxFlow/Models")
        XCTAssertEqual(paths.screenRecordingsDirectory.path, "/tmp/Application Support/VoxFlow/ScreenRecordings")
        XCTAssertEqual(paths.screenRecordingTemporaryDirectory.path, "/tmp/Application Support/VoxFlow/ScreenRecordings/Temporary")
        XCTAssertEqual(paths.screenRecordingURL(forID: "abc").path, "/tmp/Application Support/VoxFlow/ScreenRecordings/abc.mp4")
    }

    func testSubtitleArtifactPathsAreIsolatedFromOriginalRecording() {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let paths = ApplicationSupportPaths(applicationSupportDirectory: applicationSupportURL)

        XCTAssertEqual(paths.recordingSubtitleArtifactsDirectory.path, "/tmp/Application Support/VoxFlow/ScreenRecordings/Subtitles")
        XCTAssertEqual(paths.recordingSubtitleDraftURL(forID: "abc").path, "/tmp/Application Support/VoxFlow/ScreenRecordings/Subtitles/abc.subtitle.json")
        XCTAssertEqual(paths.recordingSubtitleSRTURL(forID: "abc").path, "/tmp/Application Support/VoxFlow/ScreenRecordings/Subtitles/abc.srt")
        XCTAssertEqual(paths.recordingSubtitledVideoURL(forID: "abc").path, "/tmp/Application Support/VoxFlow/ScreenRecordings/Subtitles/abc.subtitled.mp4")
        // 带字幕视频路径必须独立于原录屏，不能覆盖原 mp4。
        XCTAssertNotEqual(paths.recordingSubtitledVideoURL(forID: "abc").path, paths.screenRecordingURL(forID: "abc").path)
    }

    func testEnsureDirectoriesCreatesRequiredDirectories() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowPaths-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let paths = ApplicationSupportPaths(applicationSupportDirectory: temporaryRoot)

        try paths.ensureDirectories()

        XCTAssertTrue(FileManager.default.directoryExists(at: paths.rootDirectory))
        XCTAssertTrue(FileManager.default.directoryExists(at: paths.exportsDirectory))
        XCTAssertTrue(FileManager.default.directoryExists(at: paths.modelsDirectory))
        XCTAssertTrue(FileManager.default.directoryExists(at: paths.screenRecordingsDirectory))
        XCTAssertTrue(FileManager.default.directoryExists(at: paths.screenRecordingTemporaryDirectory))
    }
}

private extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
