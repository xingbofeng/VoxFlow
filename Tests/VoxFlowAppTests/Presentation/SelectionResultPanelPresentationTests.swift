import XCTest
@testable import VoxFlowApp

final class SelectionResultPanelPresentationTests: XCTestCase {
    func testTextResultPanelSharedComponentsDriveSelectionAndScreenshotPanels() throws {
        let root = try Self.repositoryRoot()
        let controllerSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelController.swift"),
            encoding: .utf8
        )
        let sharedSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelView.swift"),
            encoding: .utf8
        )
        let selectionSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/SelectionResultPanelController.swift"),
            encoding: .utf8
        )
        let screenshotSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sharedSource.contains("struct TextResultPanelShell"))
        XCTAssertTrue(sharedSource.contains("struct TextResultPanelHeader"))
        XCTAssertTrue(sharedSource.contains("struct TextResultScrollableTextView"))
        XCTAssertTrue(sharedSource.contains("struct TextResultPlaybackBar"))
        XCTAssertTrue(sharedSource.contains("struct TextResultFooterBar"))
        XCTAssertTrue(controllerSource.contains("final class TextResultPanelController"))
        XCTAssertTrue(controllerSource.contains("final class TextResultPanel"))
        XCTAssertTrue(selectionSource.contains("TextResultPanelShell"))
        XCTAssertTrue(screenshotSource.contains("TextResultPanelShell"))
        XCTAssertTrue(selectionSource.contains("TextResultPanelController"))
        XCTAssertTrue(screenshotSource.contains("TextResultPanelController"))
        XCTAssertFalse(selectionSource.contains("final class SelectionResultPanel: NSPanel"))
        XCTAssertFalse(screenshotSource.contains("final class ScreenshotOCRResultPanel: NSPanel"))
    }

    func testSelectionResultPanelUsesScreenshotResultPanelVisualLanguage() throws {
        let root = try Self.repositoryRoot()
        let sharedSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelView.swift"),
            encoding: .utf8
        )
        let source = try String(
            contentsOf: root
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/SelectionResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sharedSource.contains(".frame(width: 440, height: 560)"))
        XCTAssertTrue(sharedSource.contains(".regularMaterial"))
        XCTAssertTrue(sharedSource.contains(".pickerStyle(.segmented)"))
        XCTAssertTrue(sharedSource.contains("RoundedRectangle(cornerRadius: 12"))
        XCTAssertTrue(source.contains("Label(\"复制文字\", systemImage: \"doc.on.doc\")"))
        XCTAssertTrue(source.contains("Label(\"朗读\", systemImage: \"speaker.wave.2\")"))
        XCTAssertTrue(source.contains("Label(\"替换原文\", systemImage: \"text.cursor\")"))
        XCTAssertTrue(source.contains("Label(\"插入下一行\", systemImage: \"arrow.down.doc\")"))
    }

    func testSelectionResultPanelIsNotScreenshotSpecific() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/SelectionResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("SelectionResultViewModel"))
        XCTAssertFalse(source.contains("ScreenshotOCRResult"))
        XCTAssertFalse(source.contains("originalImage"))
        XCTAssertFalse(source.contains("复制图片"))
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "SelectionResultPanelPresentationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
