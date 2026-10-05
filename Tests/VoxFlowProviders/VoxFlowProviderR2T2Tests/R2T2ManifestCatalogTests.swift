import VoxFlowModelStore
@testable import VoxFlowProviderR2T2
import XCTest

final class R2T2ManifestCatalogTests: XCTestCase {
    private let manifest = R2T2ManifestCatalog.manifest

    func testManifestPinsRepositoryAndImmutableRevision() {
        XCTAssertEqual(manifest.repository, "mlx-community/Confucius4-R2T2-8bit")
        XCTAssertEqual(
            manifest.revision,
            "2d6d997c3e09c65a65b1b2576b6b9b7728df8eab",
            "必须固定 commit，不能跟随可变分支"
        )
        XCTAssertEqual(manifest.localDirectoryName, "confucius4-r2t2-8bit")
    }

    func testRemoteURLsResolveThroughThePinnedRevisionNotMain() {
        for file in manifest.files {
            let url = manifest.remoteURL(for: file)
            XCTAssertFalse(
                url.absoluteString.contains("/resolve/main/"),
                "\(file.remotePath) 仍指向可变分支 main：\(url.absoluteString)"
            )
            XCTAssertTrue(
                url.absoluteString.contains("/resolve/2d6d997c3e09c65a65b1b2576b6b9b7728df8eab/"),
                "\(file.remotePath) 未使用固定 revision：\(url.absoluteString)"
            )
        }
    }

    func testRequiredFilesCoverRuntimeInputsAndTheModelLicence() {
        XCTAssertEqual(
            Set(manifest.requiredLocalPaths),
            [
                "LICENSE",
                "MODEL_LICENSE_zh",
                "NOTICE",
                "config.json",
                "merges.txt",
                "model.safetensors",
                "model.safetensors.index.json",
                "tokenizer.json",
                "tokenizer_config.json",
                "vocab.json",
            ],
            """
            运行时文件必须齐全（上游 Qwen3ASRModel.loadTokenizer 强制要求 tokenizer.json）；\
            权重许可与归属说明也必须随模型一起落地到用户本机
            """
        )
    }

    func testModelStoreManifestCarriesIntegrityForEveryDownloadedFile() throws {
        let storeManifest = try manifest.modelStoreManifest(metadata: R2T2ManifestCatalog.metadata)
        let byPath = Dictionary(uniqueKeysWithValues: storeManifest.components.map { ($0.localPath, $0) })

        XCTAssertEqual(byPath.count, manifest.files.count)
        XCTAssertEqual(
            byPath["model.safetensors"]?.expectedSizeBytes,
            2_463_307_541,
            "权重体积是磁盘预检与空间校验的依据"
        )
        XCTAssertEqual(
            byPath["model.safetensors"]?.sha256.rawValue,
            "49b41186fbd139d0c9b3ec50f31834e47b93a6617c9271cb7c28793822ac6a98"
        )
        XCTAssertEqual(
            byPath["tokenizer.json"]?.expectedSizeBytes,
            11_429_499
        )
        for component in storeManifest.components {
            XCTAssertEqual(component.providerID.rawValue, "confucius4_r2t2")
            XCTAssertEqual(component.requirement, .required)
        }
    }

    func testMetadataDeclaresArm64OnlyAndModelLicenceIsNotProjectLicence() {
        let metadata = R2T2ManifestCatalog.metadata

        XCTAssertEqual(metadata.modelID.rawValue, "confucius4-r2t2-8bit")
        XCTAssertEqual(metadata.version, "2d6d997c3e09c65a65b1b2576b6b9b7728df8eab")
        XCTAssertEqual(metadata.supportedArchitectures, [.arm64])
        XCTAssertEqual(metadata.minimumOSVersion, "15.0")
        XCTAssertEqual(metadata.minimumMemoryBytes, 16 * 1_024 * 1_024 * 1_024)
        XCTAssertNotEqual(
            metadata.license.name,
            "Apache-2.0",
            "权重适用有道模型使用许可，不是上游代码的 MIT/Apache-2.0"
        )
    }

    func testMissingRequiredPathsDetectsPartialInstall() {
        let directory = URL(fileURLWithPath: "/tmp/r2t2-manifest-test-\(UUID().uuidString)")

        XCTAssertEqual(manifest.missingRequiredLocalPaths(at: directory).count, manifest.requiredLocalPaths.count)
        XCTAssertFalse(manifest.modelsExist(at: directory))
    }

    func testPartialInstallIsDetectedFileByFile() throws {
        let directory = URL(fileURLWithPath: "/tmp/r2t2-manifest-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))

        XCTAssertFalse(manifest.modelsExist(at: directory))
        XCTAssertEqual(
            manifest.missingRequiredLocalPaths(at: directory).count,
            manifest.requiredLocalPaths.count - 1
        )
    }

    func testDownloadedSizeBasisMatchesWhatTheDiskPrecheckWillSum() throws {
        let storeManifest = try manifest.modelStoreManifest(metadata: R2T2ManifestCatalog.metadata)
        // ResumableModelDownloader.precheckDisk 就是对 components 的 expectedSizeBytes 求和；
        // 这里钉住这个总量，以便 manifest 变化时磁盘门槛同步可见。
        let total = storeManifest.components.reduce(Int64(0)) { $0 + $1.expectedSizeBytes }

        XCTAssertEqual(total, 2_479_303_980)
    }

    func testEveryDownloadURLIsHTTPSBecauseTheDownloaderRejectsAnythingElse() throws {
        let storeManifest = try manifest.modelStoreManifest(metadata: R2T2ManifestCatalog.metadata)

        for component in storeManifest.components {
            XCTAssertEqual(component.downloadURL.scheme?.lowercased(), "https")
        }
    }
}
