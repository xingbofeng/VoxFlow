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

    func testModelStoreBackedDownloaderConvertsManifestAndMapsProgress() async throws {
        let qwenManifest = Qwen3ManifestCatalog.manifest(for: .qwen06CoreMLInt8)
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
}

private actor Qwen3FakeModelDownloadTransport: ModelDownloadTransport {
    private let data: Data
    private let chunkSize: Int

    init(data: Data, chunkSize: Int) {
        self.data = data
        self.chunkSize = chunkSize
    }

    func download(
        component: ModelComponentManifest,
        to destinationURL: URL,
        resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink
    ) async throws {
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
}

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
