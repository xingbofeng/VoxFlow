import XCTest
@testable import VoxFlowApp

@MainActor
final class PaletteFileMetadataProviderTests: XCTestCase {
    func testMetadataForExistingFileIncludesSizeAndDates() async throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("note.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: directory) }

        let provider = SystemPaletteFileMetadataProvider()
        let metadata = await provider.metadata(for: PaletteFileItem(
            url: fileURL,
            name: "note.txt",
            displayPath: directory.path,
            isDirectory: false,
            contentTypeIdentifier: "public.plain-text",
            modifiedAt: nil
        ))

        XCTAssertEqual(metadata.name, "note.txt")
        XCTAssertEqual(metadata.path, fileURL.path)
        XCTAssertNotNil(metadata.kind)
        XCTAssertNotNil(metadata.sizeDescription)
        XCTAssertNotNil(metadata.modifiedAt)
        XCTAssertEqual(metadata.previewKind, .generic)
    }

    func testMetadataForDirectoryUsesFolderPreviewKind() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let provider = SystemPaletteFileMetadataProvider()
        let metadata = await provider.metadata(for: PaletteFileItem(
            url: directory,
            name: directory.lastPathComponent,
            displayPath: directory.deletingLastPathComponent().path,
            isDirectory: true,
            contentTypeIdentifier: "public.folder",
            modifiedAt: nil
        ))

        XCTAssertEqual(metadata.previewKind, .folder)
    }

    func testMissingFileFallsBackToFileKindAndItemModifiedDate() async {
        let modifiedAt = Date(timeIntervalSince1970: 123)
        let missingURL = URL(fileURLWithPath: "/tmp/voxflow-missing-file-search-test.txt")

        let provider = SystemPaletteFileMetadataProvider()
        let metadata = await provider.metadata(for: PaletteFileItem(
            url: missingURL,
            name: "missing.txt",
            displayPath: "/tmp",
            isDirectory: false,
            contentTypeIdentifier: nil,
            modifiedAt: modifiedAt
        ))

        XCTAssertEqual(metadata.kind, "文件")
        XCTAssertEqual(metadata.modifiedAt, modifiedAt)
        XCTAssertNil(metadata.sizeDescription)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
