import XCTest
import VoxFlowModelStore

final class ModelManifestTests: XCTestCase {
    func testVersionedManifestCarriesRequiredComponentMetadata() throws {
        let component = ModelComponentManifest(
            providerID: ModelProviderID(rawValue: "qwen3"),
            modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
            version: "2026.06.01",
            runtimeVersion: "coreml-8",
            downloadURL: try XCTUnwrap(URL(string: "https://example.com/qwen3/audio_encoder.mlpackage.zip")),
            expectedSizeBytes: 1_024,
            sha256: SHA256Digest(rawValue: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"),
            localPath: "qwen3/0.6b/audio_encoder.mlpackage",
            requirement: .required,
            supportedArchitectures: [.arm64, .x86_64],
            minimumOSVersion: "14.0",
            minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
            license: ModelLicense(name: "Apache-2.0", url: try XCTUnwrap(URL(string: "https://example.com/license")))
        )

        let manifest = ModelManifest(
            schemaVersion: 1,
            components: [component]
        )

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(component.providerID.rawValue, "qwen3")
        XCTAssertEqual(component.modelID.rawValue, "qwen3-asr-0.6b")
        XCTAssertEqual(component.version, "2026.06.01")
        XCTAssertEqual(component.runtimeVersion, "coreml-8")
        XCTAssertEqual(component.downloadURL.scheme, "https")
        XCTAssertEqual(component.expectedSizeBytes, 1_024)
        XCTAssertEqual(component.sha256.rawValue.count, 64)
        XCTAssertEqual(component.localPath, "qwen3/0.6b/audio_encoder.mlpackage")
        XCTAssertEqual(component.requirement, .required)
        XCTAssertEqual(component.supportedArchitectures, [.arm64, .x86_64])
        XCTAssertEqual(component.minimumOSVersion, "14.0")
        XCTAssertEqual(component.minimumMemoryBytes, 8 * 1_024 * 1_024 * 1_024)
        XCTAssertEqual(component.license.name, "Apache-2.0")
    }

    func testManifestRoundTripsThroughJSON() throws {
        let manifest = ModelManifest(
            schemaVersion: 1,
            components: [
                ModelComponentManifest(
                    providerID: ModelProviderID(rawValue: "whisper"),
                    modelID: ModelID(rawValue: "whisper-large-v3"),
                    version: "2026.06.01",
                    runtimeVersion: "whisperkit-1",
                    downloadURL: try XCTUnwrap(URL(string: "https://example.com/whisper.bin")),
                    expectedSizeBytes: 2_048,
                    sha256: SHA256Digest(rawValue: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"),
                    localPath: "whisper/large-v3/model.bin",
                    requirement: .optional,
                    supportedArchitectures: [.arm64],
                    minimumOSVersion: "14.0",
                    minimumMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
                    license: ModelLicense(name: "MIT", url: nil)
                )
            ]
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(ModelManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }
}
