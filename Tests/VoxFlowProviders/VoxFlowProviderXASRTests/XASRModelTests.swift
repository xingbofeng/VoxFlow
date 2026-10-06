import Foundation
@testable import VoxFlowProviderXASR
import XCTest

final class XASRModelTests: XCTestCase {
    func testDefaultDirectoryUsesFullPinnedModelStoreInstallationKey() {
        let root = URL(fileURLWithPath: "/tmp/models", isDirectory: true)
        XCTAssertEqual(XASRModel.defaultDirectoryURL(modelsDirectory: root).path,
            "/tmp/models/xasr-zh-en-480ms/689ff18c584d29910da37b6fe904db0c1489c9d1")
    }

    func testRuntimeDefaultsMatchFrozenM0Configuration() {
        XCTAssertEqual(XASRModel.encoderPath, "encoder-480ms.onnx")
        XCTAssertEqual(XASRModel.decoderPath, "decoder-480ms.onnx")
        XCTAssertEqual(XASRModel.joinerPath, "joiner-480ms.onnx")
        XCTAssertEqual(XASRModel.tokensPath, "tokens.txt")
        XCTAssertEqual(XASRModel.numThreads, 1)
        XCTAssertEqual(XASRModel.sampleRate, 16_000)
        XCTAssertEqual(XASRModel.tailPaddingSeconds, 1)
    }

    func testLayoutRequiresFourReadableNonemptyRegularFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(XASRModel.missingRequiredPaths(at: root), XASRModel.requiredPaths)
        for path in XASRModel.requiredPaths {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(path))
        }
        XCTAssertTrue(XASRModel.modelsExist(at: root))
        try Data().write(to: root.appendingPathComponent(XASRModel.tokensPath))
        XCTAssertEqual(XASRModel.missingRequiredPaths(at: root), [XASRModel.tokensPath])
        try FileManager.default.removeItem(at: root.appendingPathComponent(XASRModel.tokensPath))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(XASRModel.tokensPath), withIntermediateDirectories: false)
        XCTAssertFalse(XASRModel.modelsExist(at: root), "目录不能冒充 tokens 文件；布局检查也不等于完整性或 ready")
    }
}
