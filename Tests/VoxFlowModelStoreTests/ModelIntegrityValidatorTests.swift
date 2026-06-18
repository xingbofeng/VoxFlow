import XCTest
import VoxFlowModelStore

final class ModelIntegrityValidatorTests: XCTestCase {
    func testValidatorRequiresSizeSHARequiredPathAndRuntimeVersion() throws {
        let root = try makeTemporaryDirectory()
        try Data("hello".utf8).write(to: root.appendingPathComponent("encoder.bin"))

        let manifest = ModelManifest(
            schemaVersion: 1,
            components: [
                component(
                    localPath: "encoder.bin",
                    expectedSizeBytes: 5,
                    sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
                    requirement: .required
                )
            ]
        )

        let report = try ModelIntegrityValidator().validate(
            manifest: manifest,
            installedRoot: root,
            runtimeVersion: "coreml-8"
        )

        XCTAssertTrue(report.isValid)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testValidatorDoesNotAcceptNonEmptyWrongFileAsReady() throws {
        let root = try makeTemporaryDirectory()
        try Data("wrong".utf8).write(to: root.appendingPathComponent("encoder.bin"))

        let manifest = ModelManifest(
            schemaVersion: 1,
            components: [
                component(
                    localPath: "encoder.bin",
                    expectedSizeBytes: 5,
                    sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
                    requirement: .required
                )
            ]
        )

        let report = try ModelIntegrityValidator().validate(
            manifest: manifest,
            installedRoot: root,
            runtimeVersion: "coreml-8"
        )

        XCTAssertFalse(report.isValid)
        XCTAssertEqual(
            report.issues,
            [
                .sha256Mismatch(
                    localPath: "encoder.bin",
                    expected: SHA256Digest(rawValue: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
                    actual: SHA256Digest(rawValue: "8810ad581e59f2bc3928b261707a71308f7e139eb04820366dc4d5c18d980225")
                ),
            ]
        )
    }

    func testValidatorReportsMissingRequiredPathButIgnoresMissingOptionalComponent() throws {
        let root = try makeTemporaryDirectory()
        let manifest = ModelManifest(
            schemaVersion: 1,
            components: [
                component(localPath: "required.bin", requirement: .required),
                component(localPath: "optional.bin", requirement: .optional),
            ]
        )

        let report = try ModelIntegrityValidator().validate(
            manifest: manifest,
            installedRoot: root,
            runtimeVersion: "coreml-8"
        )

        XCTAssertEqual(report.issues, [.missingRequiredComponent(localPath: "required.bin")])
    }

    func testValidatorReportsRuntimeVersionMismatch() throws {
        let root = try makeTemporaryDirectory()
        try Data("hello".utf8).write(to: root.appendingPathComponent("encoder.bin"))
        let manifest = ModelManifest(
            schemaVersion: 1,
            components: [
                component(
                    localPath: "encoder.bin",
                    expectedSizeBytes: 5,
                    sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
                    requirement: .required
                )
            ]
        )

        let report = try ModelIntegrityValidator().validate(
            manifest: manifest,
            installedRoot: root,
            runtimeVersion: "coreml-7"
        )

        XCTAssertEqual(
            report.issues,
            [.runtimeVersionMismatch(localPath: "encoder.bin", expected: "coreml-8", actual: "coreml-7")]
        )
    }

    func testValidatorReportsInvalidMetadataEvenWhenFileExists() throws {
        let root = try makeTemporaryDirectory()
        try Data("hello".utf8).write(to: root.appendingPathComponent("encoder.bin"))
        let manifest = ModelManifest(
            schemaVersion: 1,
            components: [
                ModelComponentManifest(
                    providerID: ModelProviderID(rawValue: ""),
                    modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
                    version: "2026.06.01",
                    runtimeVersion: "coreml-8",
                    downloadURL: URL(string: "https://example.com/encoder.bin")!,
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

        let report = try ModelIntegrityValidator().validate(
            manifest: manifest,
            installedRoot: root,
            runtimeVersion: "coreml-8"
        )

        XCTAssertEqual(report.issues, [.invalidMetadata(localPath: "encoder.bin", field: "providerID")])
    }

    private func component(
        localPath: String,
        expectedSizeBytes: Int64 = 5,
        sha256: String = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
        requirement: ModelComponentRequirement
    ) -> ModelComponentManifest {
        ModelComponentManifest(
            providerID: ModelProviderID(rawValue: "qwen3"),
            modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
            version: "2026.06.01",
            runtimeVersion: "coreml-8",
            downloadURL: URL(string: "https://example.com/\(localPath)")!,
            expectedSizeBytes: expectedSizeBytes,
            sha256: SHA256Digest(rawValue: sha256),
            localPath: localPath,
            requirement: requirement,
            supportedArchitectures: [.arm64],
            minimumOSVersion: "14.0",
            minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
            license: ModelLicense(name: "Apache-2.0", url: nil)
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
