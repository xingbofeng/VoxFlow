import XCTest
@testable import VoxFlowApp

final class NotesViewPresentationTests: XCTestCase {
    func testNotePreviewUsesDismissibleOverlayInsteadOfSystemSheet() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/NotesView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var notePreviewOverlay"))
        XCTAssertTrue(source.contains("Image(systemName: \"xmark\")"))
        XCTAssertTrue(source.contains("viewModel.dismissPreview()"))
        XCTAssertTrue(source.contains("NoteMarkdownPreviewModal(note: note, onClose: viewModel.dismissPreview)"))
        XCTAssertFalse(source.contains(".sheet("))
    }

    func testNotePreviewDoesNotRepeatTitleInsideMarkdownBody() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/NotesView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("# \\(note.title)\\n\\n\\(note.bodyMarkdown)"))
        XCTAssertTrue(source.contains("AttributedString(markdown: note.bodyMarkdown)"))
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
            domain: "NotesViewPresentationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
