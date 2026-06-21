import XCTest
@testable import VoxFlowApp

final class GlossaryViewPresentationTests: XCTestCase {
    func testGlossaryViewDoesNotExposeLegacyVoiceCorrectionOrReplacementSections() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/Views/GlossaryView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("GlossarySection"))
        XCTAssertFalse(source.contains("文本替换"))
        XCTAssertFalse(source.contains("添加易错词"))
        XCTAssertFalse(source.contains("搜索易错词"))
        XCTAssertFalse(source.contains("暂无易错词"))
    }
}
