import CryptoKit
import Foundation
import VoxFlowModelStore
@testable import VoxFlowProviderXASR
import XCTest

final class XASRDownloaderTests: XCTestCase {
    func testDownloadVerifiesAndAtomicallyInstallsFourComponentsWithProgress() async throws {
        let root = try temporaryRoot()
        let manifest = fixtureManifest()
        let transport = XASRFixtureTransport()
        let recorder = XASRDownloadRecorder()
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: transport, manifestProvider: { manifest })
        let installed = try await downloader.download { await recorder.append($0) }

        XCTAssertEqual(installed.path, root.appendingPathComponent("fixture-model/revision").path)
        for component in manifest.components {
            XCTAssertEqual(try Data(contentsOf: installed.appendingPathComponent(component.localPath)), XASRFixtureTransport.content(component.localPath))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: ResumableModelDownloader.stagingRoot(for: key(manifest), storeRoot: root).path))
        let values = await recorder.values()
        XCTAssertEqual(Set(values.map(\.fileIndex)), Set(0..<4))
        XCTAssertEqual(Set(values.map(\.fileName)), Set(XASRModel.requiredPaths))
        XCTAssertEqual(Set(values.map(\.fileCount)), [4])
        XCTAssertEqual(values.last?.overallProgress, 1)
        XCTAssertEqual(values.map(\.overallProgress), values.map(\.overallProgress).sorted())
        XCTAssertEqual(values.last?.bytesWritten, Int64(XASRFixtureTransport.content(XASRModel.tokensPath).count))
        XCTAssertEqual(values.last?.totalBytes, values.last?.bytesWritten)
    }

    func testValidInstallIsHashedBeforeSkippingNetworkEvenWithNoFreeSpace() async throws {
        let root = try temporaryRoot()
        let manifest = fixtureManifest()
        let installed = try installFixture(manifest, root: root)
        let transport = XASRFixtureTransport()
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: transport,
            manifestProvider: { manifest }, availableDiskBytesProvider: { _ in 0 })
        let result = try await downloader.download { _ in }
        XCTAssertEqual(result, installed)
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSameSizeDamagedInstalledComponentDoesNotSkipDownload() async throws {
        let root = try temporaryRoot()
        let manifest = fixtureManifest()
        let installed = try installFixture(manifest, root: root)
        let path = installed.appendingPathComponent(XASRModel.encoderPath)
        try Data(repeating: 0, count: XASRFixtureTransport.content(XASRModel.encoderPath).count).write(to: path)
        let transport = XASRFixtureTransport()
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: transport, manifestProvider: { manifest })
        _ = try await downloader.download { _ in }
        XCTAssertEqual(try Data(contentsOf: path), XASRFixtureTransport.content(XASRModel.encoderPath))
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 4)
    }

    func testBadHashAndWrongSizePreserveExistingInstallation() async throws {
        for damage in [XASRFixtureTransport.Damage.hash, .size] {
            let root = try temporaryRoot()
            let old = fixtureManifest(version: "old-revision")
            let oldRoot = try installFixture(old, root: root)
            let manifest = fixtureManifest()
            let transport = XASRFixtureTransport(damage: damage)
            let downloader = XASRModelStoreDownloader(storeRoot: root, transport: transport, manifestProvider: { manifest })
            do {
                _ = try await downloader.download { _ in }
                XCTFail("损坏文件不能安装")
            } catch let error as ModelInstallError {
                guard case .integrityFailed(let report) = error else { return XCTFail("unexpected \(error)") }
                XCTAssertFalse(report.isValid)
            }
            XCTAssertEqual(try Data(contentsOf: oldRoot.appendingPathComponent(XASRModel.encoderPath)), XASRFixtureTransport.content(XASRModel.encoderPath))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fixture-model/revision").path))
        }
    }

    func testDiskBudgetKeepsOldInstallationAndStageBeforeAnyRequest() async throws {
        let root = try temporaryRoot()
        let oldRoot = try installFixture(fixtureManifest(version: "old-revision"), root: root)
        let manifest = fixtureManifest()
        let stage = ResumableModelDownloader.stagingRoot(for: key(manifest), storeRoot: root)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let partial = Data("part".utf8)
        try partial.write(to: stage.appendingPathComponent(XASRModel.encoderPath))
        let total = manifest.components.reduce(Int64(0)) { $0 + $1.expectedSizeBytes }
        let transport = XASRFixtureTransport()
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: transport,
            manifestProvider: { manifest }, availableDiskBytesProvider: { _ in total - 1 })
        do {
            _ = try await downloader.download { _ in }
            XCTFail("不足以同时保留旧版本及完整 stage 时不能下载")
        } catch let error as ModelDownloadError {
            XCTAssertEqual(error, .insufficientDisk(requiredBytes: total, availableBytes: total - 1))
        }
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(try Data(contentsOf: stage.appendingPathComponent(XASRModel.encoderPath)), partial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldRoot.path))
    }

    func testCancelPreservesOldInstallAndResumesPartialOnNextAttempt() async throws {
        let root = try temporaryRoot()
        let oldRoot = try installFixture(fixtureManifest(version: "old-revision"), root: root)
        let manifest = fixtureManifest()
        let transport = XASRFixtureTransport()
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: transport, manifestProvider: { manifest })
        do {
            _ = try await downloader.download { progress in
                if progress.fileIndex == 0 { await downloader.cancelDownload() }
            }
            XCTFail("取消不能换入安装")
        } catch let error as ModelDownloadError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fixture-model/revision").path))
        let result = try await downloader.download { _ in }
        let requests = await transport.requests()
        let encoderRequests = requests.filter { $0.path == XASRModel.encoderPath }
        XCTAssertEqual(encoderRequests.map(\.offset), [0, Int64(XASRFixtureTransport.content(XASRModel.encoderPath).count / 2)])
        XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent(XASRModel.encoderPath)), XASRFixtureTransport.content(XASRModel.encoderPath))
    }

    func testCancellationAfterLastComponentDoesNotCommitAndCanRetry() async throws {
        let root = try temporaryRoot()
        let manifest = fixtureManifest()
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: XASRFixtureTransport(), manifestProvider: { manifest })
        do {
            _ = try await downloader.download { progress in
                if progress.overallProgress == 1 { await downloader.cancelDownload() }
            }
            XCTFail("最后一条进度中取消也不能提交安装")
        } catch let error as ModelDownloadError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("fixture-model/revision").path))
        let installed = try await downloader.download { _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
    }

    func testConcurrentCallsShareDownloadAndAtomicInstallation() async throws {
        let root = try temporaryRoot()
        let manifest = fixtureManifest()
        let transport = XASRFixtureTransport(holdFirstRequest: true)
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: transport, manifestProvider: { manifest })
        let first = Task { try await downloader.download { _ in } }
        await transport.waitForFirstRequest()
        let second = Task { try await downloader.download { _ in } }
        for _ in 0..<20 { await Task.yield() }
        await transport.releaseFirstRequest()
        let firstRoot = try await first.value
        let secondRoot = try await second.value
        XCTAssertEqual(firstRoot, secondRoot)
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 4, "下载和安装应共享一个任务，不能第二次消费已移走的 stage")
    }

    func testNetworkFailurePreservesOldInstallation() async throws {
        let root = try temporaryRoot()
        let oldRoot = try installFixture(fixtureManifest(version: "old-revision"), root: root)
        let manifest = fixtureManifest()
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: XASRFixtureTransport(damage: .network), manifestProvider: { manifest })
        do {
            _ = try await downloader.download { _ in }
            XCTFail("网络失败不能安装")
        } catch let error as ModelDownloadError {
            guard case .networkFailure = error else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: oldRoot.appendingPathComponent(XASRModel.encoderPath)), XASRFixtureTransport.content(XASRModel.encoderPath))
    }

    func testCompletedStagedComponentIsNotRequestedAsAnEmptyRange() async throws {
        let root = try temporaryRoot()
        let manifest = fixtureManifest()
        let stage = ResumableModelDownloader.stagingRoot(for: key(manifest), storeRoot: root)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try XASRFixtureTransport.content(XASRModel.encoderPath).write(to: stage.appendingPathComponent(XASRModel.encoderPath))
        let transport = XASRFixtureTransport()
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: transport, manifestProvider: { manifest })
        let installed = try await downloader.download { _ in }
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.path), Array(XASRModel.requiredPaths.dropFirst()), "完成文件不应发起 Range: bytes=size- 请求")
        XCTAssertEqual(try Data(contentsOf: installed.appendingPathComponent(XASRModel.encoderPath)), XASRFixtureTransport.content(XASRModel.encoderPath))
    }

    func testDamagedCompletedStageIsRejectedWithoutRedownloadOrReplacingOldInstall() async throws {
        let root = try temporaryRoot()
        let oldRoot = try installFixture(fixtureManifest(version: "old-revision"), root: root)
        let manifest = fixtureManifest()
        let stage = ResumableModelDownloader.stagingRoot(for: key(manifest), storeRoot: root)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        for path in XASRModel.requiredPaths {
            let data = path == XASRModel.encoderPath ? Data(repeating: 0, count: XASRFixtureTransport.content(path).count) : XASRFixtureTransport.content(path)
            try data.write(to: stage.appendingPathComponent(path))
        }
        let transport = XASRFixtureTransport()
        let downloader = XASRModelStoreDownloader(storeRoot: root, transport: transport, manifestProvider: { manifest })
        do {
            _ = try await downloader.download { _ in }
            XCTFail("完整大小仍须验证 SHA256")
        } catch let error as ModelInstallError {
            guard case .integrityFailed = error else { return XCTFail("unexpected \(error)") }
        }
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldRoot.path))
    }

    func testExpectedBytesAndAncestorCapacity() throws {
        let root = try temporaryRoot()
        let downloader = XASRModelStoreDownloader(storeRoot: root)
        XCTAssertEqual(downloader.expectedDownloadBytes(), 614_596_718)
        XCTAssertGreaterThan(try XCTUnwrap(XASRModelStoreDownloader.availableDiskBytes(at: root.appendingPathComponent("not/created"))), 0)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func fixtureManifest(version: String = "revision") -> ModelManifest {
        ModelManifest(schemaVersion: 1, components: XASRModel.requiredPaths.map { path in
            let data = XASRFixtureTransport.content(path)
            return ModelComponentManifest(providerID: .init(rawValue: "xasr"), modelID: .init(rawValue: "fixture-model"),
                version: version, runtimeVersion: "fixture-runtime", downloadURL: URL(string: "https://example.com/\(path)")!,
                expectedSizeBytes: Int64(data.count), sha256: .init(rawValue: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()),
                localPath: path, requirement: .required, supportedArchitectures: [.arm64], minimumOSVersion: "15.0",
                minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024, license: .init(name: "Fixture", url: nil))
        })
    }

    private func key(_ manifest: ModelManifest) -> ModelInstallKey {
        .init(modelID: manifest.components[0].modelID, version: manifest.components[0].version)
    }

    private func installFixture(_ manifest: ModelManifest, root: URL) throws -> URL {
        let stage = ResumableModelDownloader.stagingRoot(for: key(manifest), storeRoot: root)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        for component in manifest.components {
            try XASRFixtureTransport.content(component.localPath).write(to: stage.appendingPathComponent(component.localPath))
        }
        return try ModelAtomicInstaller().install(manifest: manifest, stagingRoot: stage, storeRoot: root, runtimeVersion: "fixture-runtime").installedRoot
    }
}

private actor XASRDownloadRecorder {
    private var updates: [XASRModelDownloadProgress] = []
    func append(_ update: XASRModelDownloadProgress) { updates.append(update) }
    func values() -> [XASRModelDownloadProgress] { updates }
}

private actor XASRFixtureTransport: ModelDownloadTransport {
    enum Damage: Sendable { case hash, size, network }
    struct Request: Sendable { let path: String; let offset: Int64 }
    private let damage: Damage?
    private let holdFirstRequest: Bool
    private var captured: [Request] = []
    private var entered: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    init(damage: Damage? = nil, holdFirstRequest: Bool = false) {
        self.damage = damage
        self.holdFirstRequest = holdFirstRequest
    }

    static func content(_ path: String) -> Data { Data("fixture-content-for-\(path)".utf8) }
    func requests() -> [Request] { captured }
    func waitForFirstRequest() async {
        if !captured.isEmpty { return }
        await withCheckedContinuation { entered = $0 }
    }
    func releaseFirstRequest() { release?.resume(); release = nil }

    func download(component: ModelComponentManifest, to url: URL, resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink) async throws {
        captured.append(Request(path: component.localPath, offset: offset))
        if holdFirstRequest && captured.count == 1 {
            await withCheckedContinuation { continuation in
                release = continuation
                entered?.resume()
                entered = nil
            }
        }
        if damage == .network { throw ModelDownloadError.networkFailure("fixture connection closed") }
        var data = Self.content(component.localPath)
        if component.localPath == XASRModel.encoderPath {
            if damage == .hash { data[0] = 0 }
            if damage == .size { data = data.dropLast() }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if offset == 0 { try Data().write(to: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let middle = max(Int(offset), data.count / 2)
        for end in [middle, data.count] {
            let start = Int(try handle.offset())
            if end > start { try handle.write(contentsOf: data[start..<end]) }
            try await progress(.init(bytesWritten: Int64(end), totalBytes: component.expectedSizeBytes,
                componentID: .init(rawValue: component.localPath)))
        }
    }
}
