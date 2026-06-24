import AppKit
import XCTest
@testable import VoxFlowApp

final class ClipboardContentClassifierTests: XCTestCase {
    func testImageWinsOverFileBecauseScreenshotToolsOftenWriteBoth() {
        let type = ClipboardContentClassifier.detect(
            from: [.fileURL, .png],
            plainText: nil
        )

        XCTAssertEqual(type, .image)
    }

    func testFileWinsOverURLAndText() {
        let type = ClipboardContentClassifier.detect(
            from: [.string, .URL, .fileURL],
            plainText: "file:///Users/counter/report.pdf"
        )

        XCTAssertEqual(type, .file)
    }

    func testURLWinsOverRichTextAndPlainText() {
        let type = ClipboardContentClassifier.detect(
            from: [.string, .rtf, .URL],
            plainText: "https://example.com"
        )

        XCTAssertEqual(type, .link)
    }

    func testRichTextFallsBackToText() {
        let type = ClipboardContentClassifier.detect(
            from: [.html, .rtf],
            plainText: "formatted"
        )

        XCTAssertEqual(type, .text)
    }

    func testPlainTextURLIsDetectedAsLinkWhenItIsOnlyAURL() {
        let type = ClipboardContentClassifier.detect(
            from: [.string],
            plainText: "https://github.com/voxflow/app"
        )

        XCTAssertEqual(type, .link)
    }

    func testPlainTextColorIsDetectedAsColorWhenExact() {
        XCTAssertEqual(
            ClipboardContentClassifier.detect(from: [.string], plainText: "#08745f"),
            .color
        )
        XCTAssertEqual(
            ClipboardContentClassifier.detect(from: [.string], plainText: "rgba(8, 116, 95, 0.8)"),
            .color
        )
        XCTAssertEqual(
            ClipboardContentClassifier.detect(from: [.string], plainText: "hsl(164, 87%, 24%)"),
            .color
        )
    }

    func testColorDetectionRequiresExactText() {
        let type = ClipboardContentClassifier.detect(
            from: [.string],
            plainText: "accent #08745f"
        )

        XCTAssertEqual(type, .text)
    }

    func testUnsupportedTypesReturnNil() {
        let type = ClipboardContentClassifier.detect(
            from: [.voxFlowInternalMarker],
            plainText: nil
        )

        XCTAssertNil(type)
    }
}
