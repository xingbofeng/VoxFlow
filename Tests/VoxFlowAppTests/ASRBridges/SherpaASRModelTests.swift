import XCTest
@testable import VoxFlowApp

final class SherpaASRModelTests: XCTestCase {
    func testSupportedVariantsUseOfficialSherpaOnnxArchives() {
        let variants: [SherpaASRModelVariant] = [
            .funASRInt8,
            .funASRFP32,
        ]

        XCTAssertEqual(Set(variants.map(\.directoryName)).count, variants.count)
        for variant in variants {
            XCTAssertEqual(variant.archiveURL.host, "github.com")
            XCTAssertTrue(variant.archiveURL.path.contains("/k2-fsa/sherpa-onnx/releases/download/asr-models/"))
            XCTAssertFalse(variant.requiredPaths.isEmpty)
        }
    }

    func testVariantRejectsEmptyPlaceholderFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SherpaASRModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        for path in SherpaASRModelVariant.funASRInt8.requiredPaths {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        }

        XCTAssertFalse(SherpaASRModelVariant.funASRInt8.modelsExist(at: root))
    }

    func testVariantAcceptsNonEmptyRequiredFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SherpaASRModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        for path in SherpaASRModelVariant.funASRFP32.requiredPaths {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([0x01]).write(to: url)
        }

        XCTAssertTrue(SherpaASRModelVariant.funASRFP32.modelsExist(at: root))
    }
}
