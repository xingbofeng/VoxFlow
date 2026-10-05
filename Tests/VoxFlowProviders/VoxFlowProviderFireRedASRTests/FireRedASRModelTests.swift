import Foundation
@testable import VoxFlowProviderFireRedASR
import XCTest

final class FireRedASRModelTests: XCTestCase {
    func testArchiveIsPinnedToTheAEDInt8Release() {
        XCTAssertEqual(
            FireRedASRModel.archiveName,
            "sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2"
        )
        XCTAssertEqual(
            FireRedASRModel.archiveURL.absoluteString,
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/"
                + "sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2"
        )
        XCTAssertEqual(
            FireRedASRModel.directoryName,
            String(FireRedASRModel.archiveName.dropLast(".tar.bz2".count))
        )
    }

    /// AED 是 encoder + decoder 双文件；这条断言防止有人把它改成 CTC 的单文件布局。
    func testRequiredPathsDescribeTheAEDExportNotTheCTCExport() {
        XCTAssertEqual(
            FireRedASRModel.requiredPaths,
            ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"]
        )
        XCTAssertFalse(
            FireRedASRModel.requiredPaths.contains("model.int8.onnx"),
            "AED export must not be treated as the single-file CTC export."
        )
    }

    func testModelsExistRequiresEveryFileToBeNonEmpty() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(FireRedASRModel.modelsExist(at: root))
        XCTAssertEqual(
            FireRedASRModel.missingRequiredPaths(at: root),
            ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"]
        )

        for path in FireRedASRModel.requiredPaths {
            try Data([0x01]).write(to: root.appendingPathComponent(path))
        }
        XCTAssertTrue(FireRedASRModel.modelsExist(at: root))
        XCTAssertTrue(FireRedASRModel.missingRequiredPaths(at: root).isEmpty)

        // 零字节文件不算存在：截断的下载不能被当成可用模型。
        try Data().write(to: root.appendingPathComponent(FireRedASRModel.decoderPath))
        XCTAssertFalse(FireRedASRModel.modelsExist(at: root))
        XCTAssertEqual(FireRedASRModel.missingRequiredPaths(at: root), ["decoder.int8.onnx"])
    }

    func testInstalledBytesMatchTheMeasuredComponents() {
        XCTAssertEqual(
            FireRedASRModel.installedBytes,
            817_286_833 + 417_291_928 + 79_172
        )
    }

    func testInstalledDirectoryURLFollowsTheModelStoreLayout() {
        let modelsDirectory = URL(fileURLWithPath: "/tmp/Models", isDirectory: true)
        let installed = FireRedASRModel.installedDirectoryURL(modelsDirectory: modelsDirectory)
        let key = FireRedASRManifestCatalog.modelInstallKey

        // ModelAtomicInstaller 装到 <modelID>/<version>；扁平布局会让设置页指向不存在的目录。
        XCTAssertEqual(
            installed.path,
            modelsDirectory
                .appendingPathComponent(key.modelID.rawValue, isDirectory: true)
                .appendingPathComponent(key.version, isDirectory: true)
                .path
        )
        XCTAssertNotEqual(
            installed.path,
            modelsDirectory.appendingPathComponent(FireRedASRModel.directoryName).path,
            "不能退回既有 sherpa 变体的扁平布局"
        )
    }

    private static func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fireredasr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
