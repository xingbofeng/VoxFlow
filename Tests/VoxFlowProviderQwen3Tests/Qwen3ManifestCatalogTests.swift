import VoxFlowModelStore
@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3ManifestCatalogTests: XCTestCase {
    func testQwen06CatalogBuildsInstallableModelStoreManifest() throws {
        let manifest = Qwen3ManifestCatalog.manifest(for: .qwen06CoreMLInt8)
        let metadata = try Qwen3ManifestCatalog.metadata(for: manifest)

        let modelStoreManifest = try manifest.modelStoreManifest(metadata: metadata)

        XCTAssertEqual(manifest.repository, "FluidInference/qwen3-asr-0.6b-coreml")
        XCTAssertEqual(manifest.localDirectoryName, "qwen3-asr-0.6b-coreml-int8")
        XCTAssertEqual(manifest.files.count, 13)
        XCTAssertEqual(metadata.modelID.rawValue, "qwen3-asr-0.6b-coreml-int8")
        XCTAssertEqual(metadata.version, "c081689ec58bcf29c2ef7c474ef78a164bda672b")
        XCTAssertEqual(Set(metadata.components.keys), Set(manifest.files.map(\.localPath)))
        XCTAssertEqual(
            metadata.components["qwen3_asr_embeddings.bin"]?.expectedSizeBytes,
            311_164_936
        )
        XCTAssertEqual(
            metadata.components["qwen3_asr_embeddings.bin"]?.sha256.rawValue,
            "dd1da448e68e0ee14a74f024ebfad964f39c9abcd30ac70632796c7ce76de873"
        )
        XCTAssertEqual(
            modelStoreManifest.components.map(\.expectedSizeBytes).reduce(0, +),
            1_285_889_106
        )
        XCTAssertTrue(modelStoreManifest.components.allSatisfy { $0.providerID.rawValue == "qwen3_asr" })
        XCTAssertTrue(modelStoreManifest.components.allSatisfy { $0.sha256.rawValue.count == 64 })
    }

    func testQwen17CatalogBuildsMLXModelStoreManifest() throws {
        let manifest = Qwen3ManifestCatalog.manifest(for: .qwen17MLX4Bit)
        let metadata = try Qwen3ManifestCatalog.metadata(for: manifest)

        let modelStoreManifest = try manifest.modelStoreManifest(metadata: metadata)

        XCTAssertEqual(manifest.repository, "mlx-community/Qwen3-ASR-1.7B-4bit")
        XCTAssertEqual(manifest.localDirectoryName, "qwen3-asr-1.7b-mlx-4bit")
        XCTAssertEqual(
            manifest.files.map(\.localPath),
            [
                "chat_template.json",
                "config.json",
                "generation_config.json",
                "merges.txt",
                "model.safetensors",
                "model.safetensors.index.json",
                "preprocessor_config.json",
                "tokenizer_config.json",
                "vocab.json",
            ]
        )
        XCTAssertEqual(manifest.requiredLocalPaths, manifest.files.map(\.localPath))
        XCTAssertEqual(metadata.modelID.rawValue, "qwen3-asr-1.7b-mlx-4bit")
        XCTAssertEqual(metadata.version, "78a389c776a5483b2d0d4ea5494e11012e0d6159")
        XCTAssertEqual(metadata.runtimeVersion, "mlx-4bit")
        XCTAssertEqual(metadata.supportedArchitectures, [.arm64])
        XCTAssertEqual(metadata.minimumMemoryBytes, 16 * 1_024 * 1_024 * 1_024)
        XCTAssertEqual(Set(metadata.components.keys), Set(manifest.files.map(\.localPath)))
        XCTAssertEqual(
            metadata.components["model.safetensors"]?.expectedSizeBytes,
            1_603_081_617
        )
        XCTAssertEqual(
            metadata.components["model.safetensors"]?.sha256.rawValue,
            "9848eaf7a5c1589c671b35035ac27b72e248dd0c604eacae547e7e403d29db45"
        )
        XCTAssertEqual(
            modelStoreManifest.components.map(\.expectedSizeBytes).reduce(0, +),
            1_607_630_579
        )
        XCTAssertTrue(modelStoreManifest.components.allSatisfy { $0.providerID.rawValue == "qwen3_asr" })
        XCTAssertTrue(modelStoreManifest.components.allSatisfy { $0.sha256.rawValue.count == 64 })
        XCTAssertTrue(
            modelStoreManifest.components.allSatisfy {
                $0.downloadURL.absoluteString.hasPrefix(
                    "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-4bit/resolve/main/"
                )
            }
        )
    }

    func testQwen17ManifestTreatsRequiredMLXFilesAsLoadableWithoutCoreMLEmbedding() throws {
        let manifest = Qwen3ManifestCatalog.manifest(for: .qwen17MLX4Bit)
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
        let qwenManifest = Qwen3ManifestCatalog.manifest(for: .qwen06CoreMLInt8)
        let metadata = Qwen3ModelStoreMetadata(
            modelID: ModelID(rawValue: "qwen3-asr-0.6b-coreml-int8"),
            version: "2026.06.01",
            runtimeVersion: "coreml-int8",
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
