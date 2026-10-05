import CryptoKit
import Foundation
import VoxFlowModelStore
@testable import VoxFlowProviderFireRedASR
import XCTest

/// 记录被请求的组件，并按 `payload` 把内容写到目标路径；不触碰网络。
private final class StubModelDownloadTransport: ModelDownloadTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requested: [String] = []
    private let payload: Data
    /// 在写出 `payload` 之前先追加这些字节，用来构造「归档被篡改」的场景。
    private let corruptionPrefix: Data

    init(payload: Data, corruptionPrefix: Data = Data()) {
        self.payload = payload
        self.corruptionPrefix = corruptionPrefix
    }

    var requestedComponents: [String] {
        lock.withLock { requested }
    }

    func download(
        component: ModelComponentManifest,
        to destinationURL: URL,
        resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink
    ) async throws {
        lock.withLock { requested.append(component.localPath) }
        var data = Data()
        if corruptionPrefix.isEmpty {
            data = payload
        } else {
            data = corruptionPrefix + payload.dropLast(corruptionPrefix.count)
        }
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL)
        try await progress(
            ModelDownloadProgress(
                bytesWritten: Int64(data.count),
                totalBytes: Int64(data.count),
                componentID: ModelComponentID(rawValue: component.localPath)
            )
        )
    }
}

final class FireRedASRModelStoreDownloaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fra-downloader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    // MARK: - 磁盘预检

    func testDiskPrecheckUsesArchivePlusUnpackedRequirement() {
        let required = FireRedASRManifestCatalog.requiredDiskBytes

        XCTAssertThrowsError(
            try FireRedASRModelStoreDownloader.precheckDisk(availableDiskBytes: required - 1)
        ) { error in
            guard case ModelDownloadError.insufficientDisk(let requiredBytes, let availableBytes) = error else {
                return XCTFail("expected insufficientDisk, got \(error)")
            }
            XCTAssertEqual(requiredBytes, required)
            XCTAssertEqual(availableBytes, required - 1)
        }
    }

    func testDiskPrecheckAcceptsExactlyEnoughSpaceAndUnknownSpace() throws {
        try FireRedASRModelStoreDownloader.precheckDisk(
            availableDiskBytes: FireRedASRManifestCatalog.requiredDiskBytes
        )
        try FireRedASRModelStoreDownloader.precheckDisk(availableDiskBytes: nil)
    }

    func testDownloadFailsOnDiskBeforeRequestingAnyBytes() async {
        let transport = StubModelDownloadTransport(payload: Data())
        let downloader = makeDownloader(transport: transport, availableDiskOverride: 1_024)

        do {
            _ = try await downloader.download { _ in }
            XCTFail("expected insufficientDisk")
        } catch {
            guard case ModelDownloadError.insufficientDisk = error else {
                return XCTFail("expected insufficientDisk, got \(error)")
            }
        }
        XCTAssertEqual(transport.requestedComponents, [], "空间不足时不得发起下载")
    }

    // MARK: - 摘要

    func testSHA256HexMatchesAKnownDigest() throws {
        let url = root.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: url)

        XCTAssertEqual(
            try FireRedASRModelStoreDownloader.sha256Hex(at: url),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    // MARK: - 归档校验

    func testCorruptedArchiveIsRejectedBeforeUnpacking() async throws {
        let fixture = try makeArchiveFixture()
        // 前缀会改变归档字节，sha256 必然不匹配。
        let transport = StubModelDownloadTransport(
            payload: fixture.archiveData,
            corruptionPrefix: Data([0x00, 0x01, 0x02, 0x03])
        )
        let downloader = makeDownloader(
            transport: transport,
            installedManifest: fixture.installedManifest,
            archiveManifest: fixture.archiveManifest,
            availableDiskOverride: Int64.max
        )

        do {
            _ = try await downloader.download { _ in }
            XCTFail("expected archiveChecksumMismatch")
        } catch let error as FireRedASRModelDownloadError {
            guard case .archiveChecksumMismatch = error else {
                return XCTFail("expected archiveChecksumMismatch, got \(error)")
            }
        }
    }

    // MARK: - 解包与安装

    func testUnpacksFlattensVerifiesAndInstallsAtomically() async throws {
        let fixture = try makeArchiveFixture()
        let transport = StubModelDownloadTransport(payload: fixture.archiveData)
        let storeRoot = root.appendingPathComponent("store", isDirectory: true)
        let downloader = makeDownloader(
            transport: transport,
            installedManifest: fixture.installedManifest,
            archiveManifest: fixture.archiveManifest,
            storeRoot: storeRoot,
            availableDiskOverride: Int64.max
        )

        let installedRoot = try await downloader.download { _ in }

        XCTAssertEqual(transport.requestedComponents, [FireRedASRModel.archiveName])
        for (path, contents) in fixture.fileContents {
            let installed = try Data(
                contentsOf: installedRoot.appendingPathComponent(path)
            )
            XCTAssertEqual(installed, contents, "\(path) 内容不一致")
        }
        // 归档不能留在安装目录里。
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: installedRoot.appendingPathComponent(FireRedASRModel.archiveName).path
            )
        )
        // tar 的顶层目录也不应该被搬进安装目录。
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: installedRoot.appendingPathComponent(FireRedASRModel.directoryName).path
            )
        )
        // staging 已经被原子换入消费掉（父目录可以留空，但不得再有 .partial）。
        XCTAssertEqual(try partialStagingEntries(in: storeRoot), [])

        let report = try ModelIntegrityValidator().validate(
            manifest: fixture.installedManifest,
            installedRoot: installedRoot,
            runtimeVersion: FireRedASRManifestCatalog.runtimeVersion
        )
        XCTAssertTrue(report.isValid, "\(report.issues)")
    }

    func testArchiveWhoseTopLevelDirectoryDoesNotMatchTheLayoutIsRejected() async throws {
        let contents = ["encoder.int8.onnx": Data("encoder".utf8)]
        let archiveURL = try makeTarball(
            topLevelDirectory: "some-other-directory",
            contents: contents
        )
        let archiveData = try Data(contentsOf: archiveURL)
        let manifest = installed(
            contents: contents,
            modelID: ModelID(rawValue: "fra-layout-\(UUID().uuidString)")
        )
        let downloader = makeDownloader(
            transport: StubModelDownloadTransport(payload: archiveData),
            installedManifest: manifest,
            archiveManifest: archive(
                size: Int64(archiveData.count),
                sha256: try FireRedASRModelStoreDownloader.sha256Hex(at: archiveURL)
            ),
            availableDiskOverride: Int64.max
        )

        do {
            _ = try await downloader.download { _ in }
            XCTFail("expected unexpectedArchiveLayout")
        } catch let error as FireRedASRModelDownloadError {
            guard case .unexpectedArchiveLayout(let missing) = error else {
                return XCTFail("expected unexpectedArchiveLayout, got \(error)")
            }
            XCTAssertEqual(missing.sorted(), FireRedASRModel.requiredPaths.sorted())
        }
    }

    func testArchiveThatFailsComponentVerificationDoesNotReplaceAnExistingInstall() async throws {
        let fixture = try makeArchiveFixture()
        // 清单声明的 sha256 与实际解包结果不符：模拟「归档完好但内容被换过」。
        let tampered = replacedManifest(
            fixture.installedManifest,
            localPath: "decoder.int8.onnx",
            sha256: String(repeating: "0", count: 64)
        )
        let storeRoot = root.appendingPathComponent("store", isDirectory: true)
        let downloader = makeDownloader(
            transport: StubModelDownloadTransport(payload: fixture.archiveData),
            installedManifest: tampered,
            archiveManifest: fixture.archiveManifest,
            storeRoot: storeRoot,
            availableDiskOverride: Int64.max
        )

        do {
            _ = try await downloader.download { _ in }
            XCTFail("expected integrity failure")
        } catch {
            // ModelInstallError.integrityFailed 是共享层定义的失败语义。
            guard case ModelInstallError.integrityFailed(let report) = error else {
                return XCTFail("expected integrityFailed, got \(error)")
            }
            XCTAssertFalse(report.isValid)
        }
        // 校验失败时不能出现安装目录；staging 残留由共享层的清理路径负责。
        XCTAssertEqual(try installedRoots(in: storeRoot), [], "校验失败时不得留下安装目录")
    }

    func testExistingValidInstallationIsReusedWithoutDownloading() async throws {
        let fixture = try makeArchiveFixture()
        let storeRoot = root.appendingPathComponent("store", isDirectory: true)
        let component = fixture.installedManifest.components[0]
        let installedRoot = storeRoot
            .appendingPathComponent(component.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(component.version, isDirectory: true)
        try FileManager.default.createDirectory(at: installedRoot, withIntermediateDirectories: true)
        for (path, contents) in fixture.fileContents {
            try contents.write(to: installedRoot.appendingPathComponent(path))
        }

        let transport = StubModelDownloadTransport(payload: Data())
        let downloader = makeDownloader(
            transport: transport,
            installedManifest: fixture.installedManifest,
            archiveManifest: fixture.archiveManifest,
            storeRoot: storeRoot,
            availableDiskOverride: Int64.max
        )

        let resolved = try await downloader.download { _ in }

        XCTAssertEqual(resolved, installedRoot)
        XCTAssertEqual(transport.requestedComponents, [], "有效安装不应重新下载 838 MB 归档")
    }

    // MARK: - Fixtures

    private struct ArchiveFixture {
        let archiveData: Data
        let archiveManifest: ModelManifest
        let installedManifest: ModelManifest
        let fileContents: [String: Data]
    }

    private func makeDownloader(
        transport: StubModelDownloadTransport,
        installedManifest: ModelManifest? = nil,
        archiveManifest: ModelManifest? = nil,
        storeRoot: URL? = nil,
        availableDiskOverride: Int64?
    ) -> FireRedASRModelStoreDownloader {
        FireRedASRModelStoreDownloader(
            storeRoot: storeRoot ?? root.appendingPathComponent("store", isDirectory: true),
            transport: transport,
            manifestProvider: { archiveManifest ?? FireRedASRManifestCatalog.archiveManifest() },
            installedManifestProvider: {
                installedManifest ?? FireRedASRManifestCatalog.installedManifest()
            },
            availableDiskBytesProvider: { _ in availableDiskOverride }
        )
    }

    private func makeArchiveFixture() throws -> ArchiveFixture {
        let contents: [String: Data] = [
            "encoder.int8.onnx": Data("encoder-bytes".utf8),
            "decoder.int8.onnx": Data("decoder-bytes".utf8),
            "tokens.txt": Data("tokens\n".utf8),
        ]
        let archiveURL = try makeTarball(
            topLevelDirectory: FireRedASRModel.directoryName,
            contents: contents
        )
        let archiveData = try Data(contentsOf: archiveURL)
        return ArchiveFixture(
            archiveData: archiveData,
            archiveManifest: archive(
                size: Int64(archiveData.count),
                sha256: try FireRedASRModelStoreDownloader.sha256Hex(at: archiveURL)
            ),
            installedManifest: installed(
                contents: contents,
                modelID: ModelID(rawValue: "fra-test-\(UUID().uuidString)")
            ),
            fileContents: contents
        )
    }

    /// 用真实的 `/usr/bin/tar` 造一个与上游同形状的 tar.bz2，测的是真实解包路径。
    private func makeTarball(
        topLevelDirectory: String,
        contents: [String: Data]
    ) throws -> URL {
        let buildRoot = root.appendingPathComponent("build-\(UUID().uuidString)", isDirectory: true)
        let payloadRoot = buildRoot.appendingPathComponent(topLevelDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
        for (name, data) in contents {
            try data.write(to: payloadRoot.appendingPathComponent(name))
        }

        let archiveURL = buildRoot.appendingPathComponent(FireRedASRModel.archiveName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-cjf", archiveURL.path, "-C", buildRoot.path, topLevelDirectory]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCTSkip("tar 无法创建测试归档（status \(process.terminationStatus)）")
        }
        return archiveURL
    }

    private func archive(size: Int64, sha256: String) -> ModelManifest {
        let template = FireRedASRManifestCatalog.archiveManifest()
        let component = template.components[0]
        return ModelManifest(
            schemaVersion: 1,
            components: [
                ModelComponentManifest(
                    providerID: component.providerID,
                    modelID: component.modelID,
                    version: component.version,
                    runtimeVersion: component.runtimeVersion,
                    downloadURL: component.downloadURL,
                    expectedSizeBytes: size,
                    sha256: SHA256Digest(rawValue: sha256),
                    localPath: component.localPath,
                    requirement: .required,
                    supportedArchitectures: component.supportedArchitectures,
                    minimumOSVersion: component.minimumOSVersion,
                    minimumMemoryBytes: component.minimumMemoryBytes,
                    license: component.license
                )
            ]
        )
    }

    private func installed(contents: [String: Data], modelID: ModelID) -> ModelManifest {
        let template = FireRedASRManifestCatalog.installedManifest()
        let components = FireRedASRModel.requiredPaths.map { path -> ModelComponentManifest in
            let source = template.components.first { $0.localPath == path }!
            let data = contents[path] ?? Data()
            return ModelComponentManifest(
                providerID: source.providerID,
                modelID: modelID,
                version: source.version,
                runtimeVersion: source.runtimeVersion,
                downloadURL: source.downloadURL,
                expectedSizeBytes: Int64(data.count),
                sha256: SHA256Digest(rawValue: Self.sha256Hex(data)),
                localPath: path,
                requirement: .required,
                supportedArchitectures: source.supportedArchitectures,
                minimumOSVersion: source.minimumOSVersion,
                minimumMemoryBytes: source.minimumMemoryBytes,
                license: source.license
            )
        }
        return ModelManifest(schemaVersion: 1, components: components)
    }

    private func replacedManifest(
        _ manifest: ModelManifest,
        localPath: String,
        sha256: String
    ) -> ModelManifest {
        ModelManifest(
            schemaVersion: manifest.schemaVersion,
            components: manifest.components.map { component in
                guard component.localPath == localPath else { return component }
                return ModelComponentManifest(
                    providerID: component.providerID,
                    modelID: component.modelID,
                    version: component.version,
                    runtimeVersion: component.runtimeVersion,
                    downloadURL: component.downloadURL,
                    expectedSizeBytes: component.expectedSizeBytes,
                    sha256: SHA256Digest(rawValue: sha256),
                    localPath: component.localPath,
                    requirement: component.requirement,
                    supportedArchitectures: component.supportedArchitectures,
                    minimumOSVersion: component.minimumOSVersion,
                    minimumMemoryBytes: component.minimumMemoryBytes,
                    license: component.license
                )
            }
        )
    }

    private func partialStagingEntries(in storeRoot: URL) throws -> [String] {
        let staging = storeRoot.appendingPathComponent("staging", isDirectory: true)
        guard FileManager.default.fileExists(atPath: staging.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(atPath: staging.path)
            .filter { $0.hasSuffix(".partial") }
            .sorted()
    }

    /// `storeRoot` 下除 `staging` 之外的顶层条目，也就是真正被换入的安装目录。
    private func installedRoots(in storeRoot: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: storeRoot.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(atPath: storeRoot.path)
            .filter { $0 != "staging" }
            .sorted()
    }

    private static func sha256Hex(_ data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
