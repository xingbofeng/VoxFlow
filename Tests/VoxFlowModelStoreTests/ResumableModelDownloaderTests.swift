import XCTest
import VoxFlowModelStore

final class ResumableModelDownloaderTests: XCTestCase {
    func testModelDownloadErrorsUseReadableLocalizedMessages() {
        XCTAssertEqual(
            ModelDownloadError.networkFailure("The Internet connection appears to be offline.").localizedDescription,
            "模型下载中断，可能是网络或代理连接失败。请检查网络后重试。详情：The Internet connection appears to be offline."
        )
        XCTAssertEqual(
            ModelDownloadError.paused.localizedDescription,
            "下载已暂停，可以稍后继续。"
        )
        XCTAssertFalse(
            ModelDownloadError.cancelled.localizedDescription.contains("ModelDownloadError")
        )
    }

    func testDownloaderRejectsNonHTTPSURLAndInsufficientDiskBeforeTransport() async throws {
        let root = try makeTemporaryDirectory()
        let transport = FakeDownloadTransport(data: Data("hello".utf8))
        let downloader = ResumableModelDownloader(transport: transport)

        await XCTAssertThrowsModelDownloadError(.nonHTTPSDownloadURL("http://example.com/encoder.bin")) {
            _ = try await downloader.download(
                manifest: manifest(downloadURL: URL(string: "http://example.com/encoder.bin")!),
                storeRoot: root,
                progress: nil
            )
        }
        await XCTAssertThrowsModelDownloadError(.insufficientDisk(requiredBytes: 5, availableBytes: 4)) {
            _ = try await downloader.download(
                manifest: manifest(),
                storeRoot: root,
                availableDiskBytes: 4,
                progress: nil
            )
        }
        let attempts = await transport.attemptCount()
        XCTAssertEqual(attempts, 0)
    }

    func testDownloaderCreatesStagingDirectoryAndReportsProgress() async throws {
        let root = try makeTemporaryDirectory()
        let transport = FakeDownloadTransport(data: Data("hello".utf8), chunkSize: 2)
        let downloader = ResumableModelDownloader(transport: transport)
        let progressRecorder = DownloadProgressRecorder()

        let stagingRoot = try await downloader.download(
            manifest: manifest(),
            storeRoot: root
        ) { update in
            await progressRecorder.append(update)
        }
        let progress = await progressRecorder.values()

        XCTAssertEqual(stagingRoot.lastPathComponent, "qwen3-asr-0.6b-2026.06.01.partial")
        XCTAssertEqual(try Data(contentsOf: stagingRoot.appendingPathComponent("encoder.bin")), Data("hello".utf8))
        XCTAssertEqual(progress.map(\.bytesWritten), [2, 4, 5])
        XCTAssertEqual(progress.last?.fractionCompleted, 1)
    }

    func testPauseAndRestartResumeFromPersistedOffset() async throws {
        let root = try makeTemporaryDirectory()
        let transport = FakeDownloadTransport(data: Data("hello".utf8), chunkSize: 2)
        let firstDownloader = ResumableModelDownloader(transport: transport)

        await XCTAssertThrowsModelDownloadError(.paused) {
            _ = try await firstDownloader.download(manifest: manifest(), storeRoot: root) { update in
                if update.bytesWritten == 2 {
                    await firstDownloader.pause()
                }
            }
        }

        let secondDownloader = ResumableModelDownloader(transport: transport)
        let stagingRoot = try await secondDownloader.download(
            manifest: manifest(),
            storeRoot: root,
            progress: nil
        )

        let resumeOffsets = await transport.recordedResumeOffsets()
        XCTAssertEqual(resumeOffsets, [0, 2])
        XCTAssertEqual(try Data(contentsOf: stagingRoot.appendingPathComponent("encoder.bin")), Data("hello".utf8))
    }

    func testResumeClampsPersistedOffsetToPartialFileSize() async throws {
        let root = try makeTemporaryDirectory()
        let key = ModelInstallKey(modelID: ModelID(rawValue: "qwen3-asr-0.6b"), version: "2026.06.01")
        let stagingRoot = ResumableModelDownloader.stagingRoot(for: key, storeRoot: root)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try Data("he".utf8).write(to: stagingRoot.appendingPathComponent("encoder.bin"))
        let staleState = ModelDownloadResumeState(componentOffsets: ["encoder.bin": 4])
        let stateData = try JSONEncoder().encode(staleState)
        try stateData.write(to: stagingRoot.appendingPathComponent(".download-state.json"))
        let transport = FakeDownloadTransport(data: Data("hello".utf8), chunkSize: 2)
        let downloader = ResumableModelDownloader(transport: transport)

        let result = try await downloader.download(
            manifest: manifest(),
            storeRoot: root,
            progress: nil
        )

        let resumeOffsets = await transport.recordedResumeOffsets()
        XCTAssertEqual(resumeOffsets, [2])
        XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("encoder.bin")), Data("hello".utf8))
    }

    func testResumeTruncatesPartialFileWhenPersistedOffsetIsBehindFileSize() async throws {
        let root = try makeTemporaryDirectory()
        let key = ModelInstallKey(modelID: ModelID(rawValue: "qwen3-asr-0.6b"), version: "2026.06.01")
        let stagingRoot = ResumableModelDownloader.stagingRoot(for: key, storeRoot: root)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try Data("hell".utf8).write(to: stagingRoot.appendingPathComponent("encoder.bin"))
        let staleState = ModelDownloadResumeState(componentOffsets: ["encoder.bin": 2])
        let stateData = try JSONEncoder().encode(staleState)
        try stateData.write(to: stagingRoot.appendingPathComponent(".download-state.json"))
        let transport = FakeDownloadTransport(data: Data("hello".utf8), chunkSize: 2)
        let downloader = ResumableModelDownloader(transport: transport)

        let result = try await downloader.download(
            manifest: manifest(),
            storeRoot: root,
            progress: nil
        )

        let resumeOffsets = await transport.recordedResumeOffsets()
        XCTAssertEqual(resumeOffsets, [2])
        XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("encoder.bin")), Data("hello".utf8))
    }

    func testCancelStopsDownloadAndKeepsPartialState() async throws {
        let root = try makeTemporaryDirectory()
        let transport = FakeDownloadTransport(data: Data("hello".utf8), chunkSize: 2)
        let downloader = ResumableModelDownloader(transport: transport)

        await XCTAssertThrowsModelDownloadError(.cancelled) {
            _ = try await downloader.download(manifest: manifest(), storeRoot: root) { update in
                if update.bytesWritten == 2 {
                    await downloader.cancel()
                }
            }
        }

        let stagingRoot = ResumableModelDownloader.stagingRoot(
            for: ModelInstallKey(modelID: ModelID(rawValue: "qwen3-asr-0.6b"), version: "2026.06.01"),
            storeRoot: root
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingRoot.appendingPathComponent("encoder.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingRoot.appendingPathComponent(".download-state.json").path))
    }

    func testRetriesNetworkFailure() async throws {
        let root = try makeTemporaryDirectory()
        let transport = FakeDownloadTransport(data: Data("hello".utf8), failuresBeforeSuccess: 1)
        let downloader = ResumableModelDownloader(transport: transport, maxNetworkRetries: 1)

        _ = try await downloader.download(manifest: manifest(), storeRoot: root, progress: nil)

        let attempts = await transport.attemptCount()
        XCTAssertEqual(attempts, 2)
    }

    func testConcurrentDownloadLockRunsOneTransportForSameModel() async throws {
        let root = try makeTemporaryDirectory()
        let transport = FakeDownloadTransport(data: Data("hello".utf8), chunkSize: 5, delayNanoseconds: 20_000_000)
        let downloader = ResumableModelDownloader(transport: transport)
        let testManifest = manifest()

        async let first = downloader.download(manifest: testManifest, storeRoot: root, progress: nil)
        async let second = downloader.download(manifest: testManifest, storeRoot: root, progress: nil)

        let firstURL = try await first
        let secondURL = try await second

        XCTAssertEqual(firstURL, secondURL)
        let attempts = await transport.attemptCount()
        XCTAssertEqual(attempts, 1)
    }

    private func manifest(downloadURL: URL = URL(string: "https://example.com/encoder.bin")!) -> ModelManifest {
        ModelManifest(
            schemaVersion: 1,
            components: [
                ModelComponentManifest(
                    providerID: ModelProviderID(rawValue: "qwen3"),
                    modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
                    version: "2026.06.01",
                    runtimeVersion: "coreml-8",
                    downloadURL: downloadURL,
                    expectedSizeBytes: 5,
                    sha256: SHA256Digest(rawValue: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
                    localPath: "encoder.bin",
                    requirement: .required,
                    supportedArchitectures: [.arm64],
                    minimumOSVersion: "14.0",
                    minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                    license: ModelLicense(name: "Apache-2.0", url: nil)
                )
            ]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private actor FakeDownloadTransport: ModelDownloadTransport {
    private let data: Data
    private let chunkSize: Int
    private let failuresBeforeSuccess: Int
    private let delayNanoseconds: UInt64
    private(set) var attempts = 0
    private(set) var resumeOffsets: [Int64] = []

    init(
        data: Data,
        chunkSize: Int = 5,
        failuresBeforeSuccess: Int = 0,
        delayNanoseconds: UInt64 = 0
    ) {
        self.data = data
        self.chunkSize = chunkSize
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.delayNanoseconds = delayNanoseconds
    }

    func download(
        component: ModelComponentManifest,
        to destinationURL: URL,
        resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink
    ) async throws {
        attempts += 1
        resumeOffsets.append(offset)
        if attempts <= failuresBeforeSuccess {
            throw ModelDownloadError.networkFailure("temporary")
        }

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if offset == 0 {
            try Data().write(to: destinationURL)
        }
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }
        try handle.seekToEnd()

        var cursor = Int(offset)
        while cursor < data.count {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            let end = min(cursor + chunkSize, data.count)
            try handle.write(contentsOf: data[cursor..<end])
            cursor = end
            try await progress(
                ModelDownloadProgress(
                    bytesWritten: Int64(cursor),
                    totalBytes: Int64(data.count),
                    componentID: ModelComponentID(rawValue: component.localPath)
                )
            )
        }
    }

    func attemptCount() -> Int {
        attempts
    }

    func recordedResumeOffsets() -> [Int64] {
        resumeOffsets
    }
}

private actor DownloadProgressRecorder {
    private var progress: [ModelDownloadProgress] = []

    func append(_ update: ModelDownloadProgress) {
        progress.append(update)
    }

    func values() -> [ModelDownloadProgress] {
        progress
    }
}

private func XCTAssertThrowsModelDownloadError(
    _ expected: ModelDownloadError,
    operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as ModelDownloadError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}
