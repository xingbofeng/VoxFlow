import VoxFlowModelStore
@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3ManifestCatalogTests: XCTestCase {
    func testQwen06CatalogBuildsSpeechSwiftModelStoreManifest() throws {
        let manifest = Qwen3ManifestCatalog.manifest(for: .qwen06SpeechSwift4Bit)
        let metadata = try Qwen3ManifestCatalog.metadata(for: manifest)

        let modelStoreManifest = try manifest.modelStoreManifest(metadata: metadata)

        XCTAssertEqual(manifest.repository, "aufklarer/Qwen3-ASR-0.6B-MLX-4bit")
        XCTAssertEqual(manifest.localDirectoryName, "qwen3-asr-0.6b-mlx-4bit")
        XCTAssertEqual(
            manifest.files.map(\.localPath),
            [
                "config.json",
                "merges.txt",
                "model.safetensors",
                "model.safetensors.index.json",
                "tokenizer_config.json",
                "vocab.json",
            ]
        )
        XCTAssertEqual(manifest.requiredLocalPaths, manifest.files.map(\.localPath))
        XCTAssertEqual(metadata.modelID.rawValue, "qwen3-asr-0.6b-mlx-4bit")
        XCTAssertEqual(metadata.version, "bc441bd1e4295c1f42d9879f056049a925b6e013")
        XCTAssertEqual(metadata.runtimeVersion, "mlx-4bit")
        XCTAssertEqual(Set(metadata.components.keys), Set(manifest.files.map(\.localPath)))
        XCTAssertEqual(
            metadata.components["model.safetensors"]?.expectedSizeBytes,
            708_236_945
        )
        XCTAssertEqual(
            metadata.components["model.safetensors"]?.sha256.rawValue,
            "70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf"
        )
        XCTAssertEqual(
            modelStoreManifest.components.map(\.expectedSizeBytes).reduce(0, +),
            712_777_119
        )
        XCTAssertTrue(modelStoreManifest.components.allSatisfy { $0.providerID.rawValue == "qwen3_asr" })
        XCTAssertTrue(modelStoreManifest.components.allSatisfy { $0.sha256.rawValue.count == 64 })
        XCTAssertTrue(
            modelStoreManifest.components.allSatisfy {
                $0.downloadURL.absoluteString.hasPrefix(
                    "https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit/resolve/main/"
                )
            }
        )
    }

    func testQwen17CatalogBuildsMLXModelStoreManifest() throws {
        let manifest = Qwen3ManifestCatalog.manifest(for: .qwen17SpeechSwift8Bit)
        let metadata = try Qwen3ManifestCatalog.metadata(for: manifest)

        let modelStoreManifest = try manifest.modelStoreManifest(metadata: metadata)

        XCTAssertEqual(manifest.repository, "aufklarer/Qwen3-ASR-1.7B-MLX-8bit")
        XCTAssertEqual(manifest.localDirectoryName, "qwen3-asr-1.7b-mlx-8bit")
        XCTAssertEqual(
            manifest.files.map(\.localPath),
            [
                "config.json",
                "merges.txt",
                "model.safetensors",
                "model.safetensors.index.json",
                "tokenizer_config.json",
                "vocab.json",
            ]
        )
        XCTAssertEqual(manifest.requiredLocalPaths, manifest.files.map(\.localPath))
        XCTAssertEqual(metadata.modelID.rawValue, "qwen3-asr-1.7b-mlx-8bit")
        XCTAssertEqual(metadata.version, "e5450a26d1fd417c45fc9c405651ddc3180a27a6")
        XCTAssertEqual(metadata.runtimeVersion, "mlx-8bit")
        XCTAssertEqual(metadata.supportedArchitectures, [.arm64])
        XCTAssertEqual(metadata.minimumOSVersion, "15.0")
        XCTAssertEqual(metadata.minimumMemoryBytes, 16 * 1_024 * 1_024 * 1_024)
        XCTAssertEqual(Set(metadata.components.keys), Set(manifest.files.map(\.localPath)))
        XCTAssertEqual(
            metadata.components["model.safetensors"]?.expectedSizeBytes,
            2_463_307_541
        )
        XCTAssertEqual(
            metadata.components["model.safetensors"]?.sha256.rawValue,
            "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c"
        )
        XCTAssertEqual(
            modelStoreManifest.components.map(\.expectedSizeBytes).reduce(0, +),
            2_467_854_870
        )
        XCTAssertTrue(modelStoreManifest.components.allSatisfy { $0.providerID.rawValue == "qwen3_asr" })
        XCTAssertTrue(modelStoreManifest.components.allSatisfy { $0.sha256.rawValue.count == 64 })
        XCTAssertTrue(
            modelStoreManifest.components.allSatisfy {
                $0.downloadURL.absoluteString.hasPrefix(
                    "https://huggingface.co/aufklarer/Qwen3-ASR-1.7B-MLX-8bit/resolve/main/"
                )
            }
        )
    }

    func testQwen17ManifestTreatsRequiredMLXFilesAsLoadableWithoutLegacyCoreMLEmbedding() throws {
        let manifest = Qwen3ManifestCatalog.manifest(for: .qwen17SpeechSwift8Bit)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qwen3ManifestCatalogTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: modelURL) }

        for relativePath in manifest.requiredLocalPaths {
            let fileURL = modelURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        }

        XCTAssertTrue(manifest.modelsExist(at: modelURL))
        XCTAssertEqual(manifest.missingRequiredLocalPaths(at: modelURL), [])
    }

    func testQwenManifestRefusesModelStoreManifestWhenIntegrityMetadataIsMissing() throws {
        let qwenManifest = Qwen3ManifestCatalog.manifest(for: .qwen17SpeechSwift8Bit)
        let metadata = Qwen3ModelStoreMetadata(
            modelID: ModelID(rawValue: "qwen3-asr-1.7b-mlx-8bit"),
            version: "2026.06.01",
            runtimeVersion: "mlx-8bit",
            supportedArchitectures: [.arm64],
            minimumOSVersion: "14.0",
            minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
            license: ModelLicense(name: "Apache-2.0", url: nil),
            components: [:]
        )

        XCTAssertThrowsError(try qwenManifest.modelStoreManifest(metadata: metadata)) { error in
            XCTAssertEqual(
                error as? Qwen3ModelStoreManifestError,
                .missingIntegrityMetadata(localPath: qwenManifest.files[0].localPath)
            )
        }
    }
}
