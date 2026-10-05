import CryptoKit
import Foundation
import VoxFlowModelStore
@testable import VoxFlowProviderR2T2
import XCTest

final class R2T2ModelStoreDownloaderTests: XCTestCase {
    func testDownloadInstallsEveryRequiredComponent() async throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let manifest = try testManifest()
        let downloader = R2T2ModelStoreDownloader(
            storeRoot: root,
            transport: R2T2FakeModelDownloadTransport(),
            manifestProvider: { manifest }
        )

        let installedRoot = try await downloader.download { _ in }

        XCTAssertEqual(installedRoot.deletingLastPathComponent().lastPathComponent, "test-model")
        XCTAssertEqual(installedRoot.lastPathComponent, "test-version")
        for component in manifest.components {
            let installed = installedRoot.appendingPathComponent(component.localPath)
            XCTAssertEqual(
                try Data(contentsOf: installed),
                R2T2FakeModelDownloadTransport.content(for: component.localPath),
                "\(component.localPath) 未按内容安装"
            )
        }
    }

    func testDownloadReportsProgressAcrossEveryComponent() async throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let manifest = try testManifest()
        let downloader = R2T2ModelStoreDownloader(
            storeRoot: root,
            transport: R2T2FakeModelDownloadTransport(),
            manifestProvider: { manifest }
        )
        let recorder = R2T2ProgressRecorder()

        _ = try await downloader.download { progress in
            await recorder.append(progress)
        }

        let observations = await recorder.values()
        XCTAssertFalse(observations.isEmpty)
        XCTAssertEqual(observations.map(\.fileCount).max(), manifest.components.count)
        XCTAssertEqual(Set(observations.map(\.fileIndex)), Set(0..<manifest.components.count))
        XCTAssertEqual(observations.last?.fileProgress, 1)
        XCTAssertEqual(observations.last?.overallProgress, 1)

        let overall = observations.map(\.overallProgress)
        XCTAssertEqual(overall, overall.sorted(), "整体进度不应回退")
        XCTAssertEqual(observations.last?.fileName, manifest.components.last?.localPath)
    }

    func testDownloadReusesValidInstallationWithoutRedownloading() async throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let manifest = try testManifest()
        let transport = R2T2FakeModelDownloadTransport()
        let downloader = R2T2ModelStoreDownloader(
            storeRoot: root,
            transport: transport,
            manifestProvider: { manifest }
        )

        let firstRoot = try await downloader.download { _ in }
        let attemptsAfterFirstInstall = await transport.attemptCount()
        XCTAssertEqual(attemptsAfterFirstInstall, manifest.components.count)

        let secondDownloader = R2T2ModelStoreDownloader(
            storeRoot: root,
            transport: transport,
            manifestProvider: { manifest }
        )
        let secondRoot = try await secondDownloader.download { _ in }
        let attemptsAfterSecondInstall = await transport.attemptCount()

        XCTAssertEqual(secondRoot, firstRoot)
        XCTAssertEqual(
            attemptsAfterSecondInstall,
            attemptsAfterFirstInstall,
            "已有有效安装时不应重新下载"
        )
    }

    /// `ResumableModelDownloader.precheckDisk` 只有在拿到可用空间时才生效。传 `nil` 等于没有
    /// 空间预检，2.46 GB 的权重会下载到一半才失败。
    func testDownloadFailsBeforeFetchingWhenDiskSpaceIsInsufficient() async throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let transport = R2T2FakeModelDownloadTransport()
        let downloader = R2T2ModelStoreDownloader(
            storeRoot: root,
            transport: transport,
            manifestProvider: { Self.oversizedManifest() }
        )

        do {
            _ = try await downloader.download { _ in }
            XCTFail("空间不足时必须在下载前失败")
        } catch let error as ModelDownloadError {
            guard case .insufficientDisk = error else {
                return XCTFail("期望 insufficientDisk，实际为 \(error)")
            }
        }

        let attempts = await transport.attemptCount()
        XCTAssertEqual(attempts, 0, "预检失败不得发起任何下载请求")
    }

    func testAvailableDiskBytesResolvesTheNearestExistingAncestor() throws {
        let root = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let notCreatedYet = root
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("confucius4-r2t2-8bit", isDirectory: true)

        let bytes = try XCTUnwrap(
            R2T2ModelStoreDownloader.availableDiskBytes(at: notCreatedYet),
            "首次安装时 storeRoot 还不存在，必须回退到已存在的祖先目录取容量"
        )

        XCTAssertGreaterThan(bytes, 0)
    }

    func testExpectedDownloadBytesMatchesPinnedCatalogTotal() {
        let catalogTotal = R2T2ManifestCatalog.metadata.components.values
            .reduce(Int64(0)) { $0 + $1.expectedSizeBytes }

        let downloader = R2T2ModelStoreDownloader(
            storeRoot: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )

        XCTAssertEqual(downloader.expectedDownloadBytes(), catalogTotal)
        XCTAssertEqual(
            catalogTotal,
            2_479_303_980,
            "模型体积变化必须同步更新设置页展示与清单"
        )
    }

    private func testManifest() throws -> ModelManifest {
        let components = R2T2FakeModelDownloadTransport.contentByLocalPath
            .sorted { $0.key < $1.key }
            .map { localPath, data in
                ModelComponentManifest(
                    providerID: ModelProviderID(rawValue: "confucius4_r2t2"),
                    modelID: ModelID(rawValue: "test-model"),
                    version: "test-version",
                    runtimeVersion: "test-runtime",
                    downloadURL: URL(string: "https://example.com/\(localPath)")!,
                    expectedSizeBytes: Int64(data.count),
                    sha256: SHA256Digest(rawValue: Self.sha256Hex(of: data)),
                    localPath: localPath,
                    requirement: .required,
                    supportedArchitectures: [.arm64],
                    minimumOSVersion: "15.0",
                    minimumMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
                    license: ModelLicense(name: "Test License", url: nil)
                )
            }
        return ModelManifest(schemaVersion: 1, components: components)
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 体积远超任何真实磁盘，用来把空间预检逼到失败分支。
    private static func oversizedManifest() -> ModelManifest {
        let component = ModelComponentManifest(
            providerID: ModelProviderID(rawValue: "confucius4_r2t2"),
            modelID: ModelID(rawValue: "test-model"),
            version: "test-version",
            runtimeVersion: "test-runtime",
            downloadURL: URL(string: "https://example.com/model.safetensors")!,
            expectedSizeBytes: Int64.max / 2,
            sha256: SHA256Digest(rawValue: String(repeating: "0", count: 64)),
            localPath: "model.safetensors",
            requirement: .required,
            supportedArchitectures: [.arm64],
            minimumOSVersion: "15.0",
            minimumMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
            license: ModelLicense(name: "Test License", url: nil)
        )
        return ModelManifest(schemaVersion: 1, components: [component])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor R2T2ProgressRecorder {
    private var stored: [R2T2ModelDownloadProgress] = []

    func append(_ progress: R2T2ModelDownloadProgress) {
        stored.append(progress)
    }

    func values() -> [R2T2ModelDownloadProgress] {
        stored
    }
}

private actor R2T2FakeModelDownloadTransport: ModelDownloadTransport {
    static let contentByLocalPath: [String: Data] = [
        "config.json": Data("{\"model\":\"r2t2\"}".utf8),
        "model.safetensors": Data("weights".utf8),
        "tokenizer.json": Data("{\"vocab\":1}".utf8),
    ]

    static func content(for localPath: String) -> Data {
        contentByLocalPath[localPath] ?? Data()
    }

    private var attempts = 0

    func download(
        component: ModelComponentManifest,
        to destinationURL: URL,
        resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink
    ) async throws {
        attempts += 1
        let data = Self.content(for: component.localPath)
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
        try handle.write(contentsOf: data)

        try await progress(
            ModelDownloadProgress(
                bytesWritten: Int64(data.count),
                totalBytes: Int64(data.count),
                componentID: ModelComponentID(rawValue: component.localPath)
            )
        )
    }

    func attemptCount() -> Int {
        attempts
    }
}
