import VoxFlowModelStore
@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3ModelStoreDownloaderTests: XCTestCase {
    func testModelStoreInstallerDownloadsThenAtomicallyInstallsManifest() async throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let transport = Qwen3FakeModelDownloadTransport(
            data: Data("hello".utf8),
            chunkSize: 2
        )
        let progressRecorder = ModelStoreProgressRecorder()
        let installer = Qwen3ModelStoreInstaller(
            downloader: ResumableModelDownloader(transport: transport),
            atomicInstaller: ModelAtomicInstaller(),
            storeRoot: root.appendingPathComponent("models", isDirectory: true),
            runtimeVersion: "coreml-8"
        )

        let installedRoot = try await installer.install(manifest: modelStoreManifest()) { progress in
            await progressRecorder.append(progress)
        }

        let installedFile = installedRoot.appendingPathComponent("encoder.bin")
        let progress = await progressRecorder.values()
        XCTAssertEqual(installedRoot.lastPathComponent, "2026.06.01")
        XCTAssertEqual(installedRoot.deletingLastPathComponent().lastPathComponent, "qwen3-asr-0.6b")
        XCTAssertEqual(try Data(contentsOf: installedFile), Data("hello".utf8))
        XCTAssertEqual(progress.map(\.bytesWritten), [2, 4, 5])
    }

    func testLiveInstallerDownloadsIntoProvidedStoreRoot() async throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let installer = Qwen3ModelStoreLiveInstaller(
            storeRoot: root.appendingPathComponent("models", isDirectory: true),
            transport: Qwen3FakeModelDownloadTransport(
                data: Data("hello".utf8),
                chunkSize: 5
            )
        )

        let installedRoot = try await installer.install(
            manifest: modelStoreManifest(),
            progress: nil
        )

        XCTAssertEqual(installedRoot.lastPathComponent, "2026.06.01")
        XCTAssertEqual(installedRoot.deletingLastPathComponent().lastPathComponent, "qwen3-asr-0.6b")
        XCTAssertEqual(try Data(contentsOf: installedRoot.appendingPathComponent("encoder.bin")), Data("hello".utf8))
    }

    func testLiveInstallerDeduplicatesConcurrentInstallsForSameManifest() async throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let transport = Qwen3FakeModelDownloadTransport(
            data: Data("hello".utf8),
            chunkSize: 5,
            delayNanoseconds: 20_000_000
        )
        let installer = Qwen3ModelStoreLiveInstaller(
            storeRoot: root.appendingPathComponent("models", isDirectory: true),
            transport: transport
        )
        let manifest = modelStoreManifest()

        async let first = installer.install(manifest: manifest, progress: nil)
        async let second = installer.install(manifest: manifest, progress: nil)

        let firstRoot = try await first
        let secondRoot = try await second

        XCTAssertEqual(firstRoot, secondRoot)
        let attempts = await transport.attemptCount()
        XCTAssertEqual(attempts, 1)
    }

    func testLiveInstallerReturnsExistingValidInstallationWithoutDownloading() async throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let storeRoot = root.appendingPathComponent("models", isDirectory: true)
        let existingRoot = storeRoot
            .appendingPathComponent("qwen3-asr-0.6b", isDirectory: true)
            .appendingPathComponent("coreml-8", isDirectory: true)
        try FileManager.default.createDirectory(at: existingRoot, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: existingRoot.appendingPathComponent("encoder.bin"))
        let installer = Qwen3ModelStoreLiveInstaller(
            storeRoot: storeRoot,
            transport: FailingQwen3ModelDownloadTransport()
        )

        let installedRoot = try await installer.install(
            manifest: modelStoreManifest(),
            progress: nil
        )

        XCTAssertEqual(installedRoot, existingRoot)
    }

    func testModelStoreBackedDownloaderConvertsManifestAndMapsProgress() async throws {
        let qwenManifest = Qwen3ManifestCatalog.manifest(for: .qwen06SpeechSwift4Bit)
        let metadata = try Qwen3ManifestCatalog.metadata(for: qwenManifest)
        let installedRoot = URL(fileURLWithPath: "/tmp/qwen3-provider-installed", isDirectory: true)
        let installer = CapturingQwen3ModelStoreInstaller(installedRoot: installedRoot)
        let downloader = Qwen3ModelStoreBackedDownloader(
            metadataProvider: { manifest in
                XCTAssertEqual(manifest, qwenManifest)
                return metadata
            },
            installer: installer
        )
        let recorder = Qwen3ProgressRecorder()

        let result = try await downloader.download(manifest: qwenManifest) { progress in
            await recorder.append(progress)
        }

        let installedManifest = await installer.installedManifest()
        let progressValues = await recorder.values()
        XCTAssertEqual(result, installedRoot)
        XCTAssertEqual(installedManifest?.components.count, qwenManifest.files.count)
        XCTAssertEqual(installedManifest?.components.first?.localPath, qwenManifest.files.first?.localPath)
        XCTAssertEqual(progressValues.last?.fileName, qwenManifest.files.first?.localPath)
        XCTAssertEqual(progressValues.last?.fileProgress, 0.5)
        XCTAssertEqual(progressValues.last?.fileCount, qwenManifest.files.count)
    }

    func testURLSessionTransportCancelsOnlyActiveDownloadTask() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowProviders/VoxFlowProviderQwen3/Lifecycle/Qwen3ModelStoreDownloader.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("activeDownloadTask?.cancel()"))
        XCTAssertFalse(source.contains("invalidateAndCancel()"))
        XCTAssertTrue(source.contains("defer { clearActiveDownloadState() }"))
    }

    func testURLSessionTransportAppendsValidPartialContentResponse() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("encoder.bin")
        let downloaded = directory.appendingPathComponent("download.tmp")
        try Data("he".utf8).write(to: destination)
        try Data("llo".utf8).write(to: downloaded)

        try Qwen3URLSessionModelDownloadTransport.moveDownloadedFile(
            from: downloaded,
            to: destination,
            resumeOffset: 2,
            response: httpResponse(statusCode: 206, headers: ["Content-Range": "bytes 2-4/5"]),
            fileManager: .default
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("hello".utf8))
    }

    func testURLSessionTransportOverwritesPartialWhenRangeRequestReturnsFullContent() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("encoder.bin")
        let downloaded = directory.appendingPathComponent("download.tmp")
        try Data("he".utf8).write(to: destination)
        try Data("hello".utf8).write(to: downloaded)

        try Qwen3URLSessionModelDownloadTransport.moveDownloadedFile(
            from: downloaded,
            to: destination,
            resumeOffset: 2,
            response: httpResponse(statusCode: 200),
            fileManager: .default
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("hello".utf8))
    }

    func testURLSessionTransportRejectsMismatchedContentRange() throws {
        let directory = try makeTemporaryDirectory()
        let destination = directory.appendingPathComponent("encoder.bin")
        let downloaded = directory.appendingPathComponent("download.tmp")
        try Data("he".utf8).write(to: destination)
        try Data("llo".utf8).write(to: downloaded)

        XCTAssertThrowsError(
            try Qwen3URLSessionModelDownloadTransport.moveDownloadedFile(
                from: downloaded,
                to: destination,
                resumeOffset: 2,
                response: httpResponse(statusCode: 206, headers: ["Content-Range": "bytes 0-4/5"]),
                fileManager: .default
            )
        ) { error in
            XCTAssertEqual(error as? Qwen3ModelStoreDownloadError, .invalidContentRange("bytes 0-4/5"))
        }
    }

    private func httpResponse(statusCode: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/encoder.bin")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private static func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private actor Qwen3FakeModelDownloadTransport: ModelDownloadTransport {
    private let data: Data
    private let chunkSize: Int
    private let delayNanoseconds: UInt64
    private var attempts = 0

    init(data: Data, chunkSize: Int, delayNanoseconds: UInt64 = 0) {
        self.data = data
        self.chunkSize = chunkSize
        self.delayNanoseconds = delayNanoseconds
    }

    func download(
        component: ModelComponentManifest,
        to destinationURL: URL,
        resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink
    ) async throws {
        attempts += 1
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
}

private struct FailingQwen3ModelDownloadTransport: ModelDownloadTransport {
    func download(
        component: ModelComponentManifest,
        to destinationURL: URL,
        resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink
    ) async throws {
        XCTFail("Existing valid installations should not trigger a download.")
        throw UnexpectedQwen3DownloadError()
    }
}

private struct UnexpectedQwen3DownloadError: Error {}

private actor ModelStoreProgressRecorder {
    private var progress: [ModelDownloadProgress] = []

    func append(_ update: ModelDownloadProgress) {
        progress.append(update)
    }

    func values() -> [ModelDownloadProgress] {
        progress
    }
}

private actor CapturingQwen3ModelStoreInstaller: Qwen3ModelStoreInstalling {
    private let installedRoot: URL
    private var manifest: ModelManifest?

    init(installedRoot: URL) {
        self.installedRoot = installedRoot
    }

    func install(
        manifest: ModelManifest,
        progress: ModelDownloadObserver?
    ) async throws -> URL {
        self.manifest = manifest
        if let firstComponent = manifest.components.first {
            await progress?(
                ModelDownloadProgress(
                    bytesWritten: 1,
                    totalBytes: 2,
                    componentID: ModelComponentID(rawValue: firstComponent.localPath)
                )
            )
        }
        return installedRoot
    }

    func installedManifest() -> ModelManifest? {
        manifest
    }
}

private actor Qwen3ProgressRecorder {
    private var progress: [Qwen3ModelDownloadProgress] = []

    func append(_ progress: Qwen3ModelDownloadProgress) {
        self.progress.append(progress)
    }

    func values() -> [Qwen3ModelDownloadProgress] {
        progress
    }
}

private func modelStoreManifest() -> ModelManifest {
    ModelManifest(
        schemaVersion: 1,
        components: [
            ModelComponentManifest(
                providerID: ModelProviderID(rawValue: "qwen3_asr"),
                modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
                version: "2026.06.01",
                runtimeVersion: "coreml-8",
                downloadURL: URL(string: "https://example.com/encoder.bin")!,
                expectedSizeBytes: 5,
                sha256: SHA256Digest(
                    rawValue: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
                ),
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
    return url
}
