import AppKit
import UniformTypeIdentifiers
import VoxFlowTextInsertion
import XCTest
@testable import VoxFlowApp

@MainActor
final class AssetActionServiceTests: XCTestCase {
    func testTextAssetActionsExcludePhaseTwoActions() {
        let service = makeService()
        let actions = service.availableActions(for: makeAsset(contentType: .text, text: "hello"))

        XCTAssertEqual(
            actions,
            [.paste, .copy, .pasteAndKeepOpen, .quickLook, .saveAsFile, .delete]
        )
        XCTAssertFalse(actions.contains(.pin))
        XCTAssertFalse(actions.contains(.rerunOCR))
        XCTAssertFalse(actions.contains(.attachToAIChat))
    }

    func testScreenshotAssetActionsIncludeOCROnSameAsset() {
        let service = makeService()
        let actions = service.availableActions(
            for: makeAsset(
                source: .screenshot,
                contentType: .image,
                text: "recognized text",
                imagePath: "/tmp/screenshot.png"
            )
        )

        XCTAssertTrue(actions.contains(.copyImage))
        XCTAssertTrue(actions.contains(.pasteOCRText))
        XCTAssertTrue(actions.contains(.copyOCRText))
        XCTAssertFalse(actions.contains(.rerunOCR))
        XCTAssertEqual(actions.last, .delete)
    }

    func testFileAssetActionsIncludeFileAndPathVariants() {
        let service = makeService()
        let actions = service.availableActions(
            for: makeAsset(contentType: .file, text: "/tmp/report.pdf", filePath: "/tmp/report.pdf")
        )

        XCTAssertTrue(actions.contains(.pasteFile))
        XCTAssertTrue(actions.contains(.copyFile))
        XCTAssertTrue(actions.contains(.pasteFilePath))
        XCTAssertTrue(actions.contains(.copyFilePath))
        XCTAssertEqual(actions.last, .delete)
    }

    func testPasteTextUsesTextInserter() async throws {
        let inserter = CapturingTextInserter()
        let service = makeService(textInserter: inserter)
        let asset = makeAsset(source: .dictation, contentType: .text, text: "hello world")

        let result = try await service.perform(.paste, on: asset)

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(inserter.insertedTexts, ["hello world"])
    }

    func testCopyTextWritesInternalPasteboardMarker() async throws {
        let pasteboard = try makePasteboard()
        let guarder = ClipboardInternalWriteGuard()
        let service = makeService(pasteboard: pasteboard, internalWriteGuard: guarder)
        let asset = makeAsset(contentType: .text, text: "copy me")

        let result = try await service.perform(.copy, on: asset)

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(pasteboard.string(forType: .string), "copy me")
        XCTAssertTrue(pasteboard.types?.contains(.voxFlowInternalMarker) == true)
        XCTAssertTrue(guarder.shouldIgnore(changeCount: pasteboard.changeCount, types: pasteboard.types ?? []))
    }

    func testPasteAndCopyOCRTextUseScreenshotTextField() async throws {
        let pasteboard = try makePasteboard()
        let inserter = CapturingTextInserter()
        let service = makeService(textInserter: inserter, pasteboard: pasteboard)
        let asset = makeAsset(source: .screenshot, contentType: .image, text: "OCR text")

        let pasteResult = try await service.perform(.pasteOCRText, on: asset)
        let copyResult = try await service.perform(.copyOCRText, on: asset)

        XCTAssertEqual(pasteResult, .pasted)
        XCTAssertEqual(copyResult, .copied)
        XCTAssertEqual(inserter.insertedTexts, ["OCR text"])
        XCTAssertEqual(pasteboard.string(forType: .string), "OCR text")
    }

    func testPasteAndCopyImageUseImagePayloadNotOCRText() async throws {
        let pasteboard = try makePasteboard()
        let inserter = CapturingTextInserter()
        let pasteShortcutPoster = CapturingPasteShortcutPoster()
        let service = makeService(
            textInserter: inserter,
            pasteboard: pasteboard,
            pasteShortcutPoster: pasteShortcutPoster
        )
        let imagePath = try makeImageFile()
        let asset = makeAsset(
            source: .screenshot,
            contentType: .image,
            text: "OCR text",
            imagePath: imagePath
        )

        let pasteResult = try await service.perform(.paste, on: asset)
        let keepOpenResult = try await service.perform(.pasteAndKeepOpen, on: asset)
        let copyResult = try await service.perform(.copy, on: asset)

        XCTAssertEqual(pasteResult, .pasted)
        XCTAssertEqual(keepOpenResult, .pasted)
        XCTAssertEqual(copyResult, .copied)
        XCTAssertNotNil(NSImage(pasteboard: pasteboard))
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertEqual(inserter.insertedTexts, [])
        XCTAssertEqual(pasteShortcutPoster.postCallCount, 2)
    }

    func testImageSaveAsFileRequestPreservesImageFileType() throws {
        let service = makeService()
        let imagePath = try makeImageFile()
        let asset = makeAsset(
            source: .screenshot,
            contentType: .image,
            text: "OCR text",
            imagePath: imagePath
        )

        let request = try service.fileSaveRequest(for: asset)

        XCTAssertEqual(request.suggestedFileName, URL(fileURLWithPath: imagePath).lastPathComponent)
        XCTAssertEqual(request.sourceURL?.path, imagePath)
        XCTAssertEqual(request.allowedContentTypes, [.png])
    }

    func testPasteAndCopyFileUseFilePayloadNotPathText() async throws {
        let pasteboard = try makePasteboard()
        let pasteShortcutPoster = CapturingPasteShortcutPoster()
        let service = makeService(
            pasteboard: pasteboard,
            pasteShortcutPoster: pasteShortcutPoster
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asset-action-file.txt")
        try "file".write(to: fileURL, atomically: true, encoding: .utf8)
        let asset = makeAsset(contentType: .file, text: nil, filePath: fileURL.path)

        let pasteResult = try await service.perform(.paste, on: asset)
        let pasteFileResult = try await service.perform(.pasteFile, on: asset)
        let copyResult = try await service.perform(.copy, on: asset)

        XCTAssertEqual(pasteResult, .pasted)
        XCTAssertEqual(pasteFileResult, .pasted)
        XCTAssertEqual(copyResult, .copied)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL]
        XCTAssertEqual(urls?.first?.path, fileURL.path)
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertEqual(pasteShortcutPoster.postCallCount, 2)
    }

    func testSystemPasteShortcutPosterSkipsSystemEventsWhenInteractionIsDisabled() throws {
        let poster = SystemPasteShortcutPoster(
            allowsSystemInteraction: { false },
            postEvents: { _, _ in
                XCTFail("Tests must not post real Cmd+V events")
            }
        )

        try poster.postPasteShortcut()
    }

    func testRuntimeEnvironmentDetectsXCTestFromXCTestArguments() {
        XCTAssertTrue(
            RuntimeEnvironment.isRunningUnderXCTest(
                environment: [:],
                arguments: ["/tmp/VoxFlowAppTests.xctest"],
                bundlePaths: [],
                classExists: { _ in false }
            )
        )
    }

    func testFilePathActionsUsePathText() async throws {
        let pasteboard = try makePasteboard()
        let inserter = CapturingTextInserter()
        let service = makeService(textInserter: inserter, pasteboard: pasteboard)
        let asset = makeAsset(contentType: .file, text: nil, filePath: "/tmp/report.pdf")

        let pasteResult = try await service.perform(.pasteFilePath, on: asset)
        let copyResult = try await service.perform(.copyFilePath, on: asset)

        XCTAssertEqual(pasteResult, .pasted)
        XCTAssertEqual(copyResult, .copied)
        XCTAssertEqual(inserter.insertedTexts, ["/tmp/report.pdf"])
        XCTAssertEqual(pasteboard.string(forType: .string), "/tmp/report.pdf")
    }

    func testDeleteSoftDeletesAsset() async throws {
        let repository = CapturingAssetActionRepository()
        let service = makeService(repository: repository, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let asset = makeAsset(id: "delete-me")

        let result = try await service.perform(.delete, on: asset)

        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(repository.deletedIDs, ["delete-me"])
        XCTAssertEqual(repository.deletedAt, [Date(timeIntervalSince1970: 1_800_000_000)])
    }

    private func makeService(
        textInserter: CapturingTextInserter = CapturingTextInserter(),
        pasteboard: NSPasteboard? = nil,
        internalWriteGuard: ClipboardInternalWriteGuard = ClipboardInternalWriteGuard(),
        repository: CapturingAssetActionRepository = CapturingAssetActionRepository(),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) },
        pasteShortcutPoster: CapturingPasteShortcutPoster = CapturingPasteShortcutPoster()
    ) -> AssetActionService {
        AssetActionService(
            textInserter: textInserter,
            pasteboard: pasteboard ?? NSPasteboard(name: NSPasteboard.Name("AssetActionServiceTests-\(UUID().uuidString)")),
            internalWriteGuard: internalWriteGuard,
            repository: repository,
            now: now,
            pasteShortcutPoster: pasteShortcutPoster
        )
    }

    private func makePasteboard() throws -> NSPasteboard {
        try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("AssetActionServiceTests-\(UUID().uuidString)")))
    }

    private func makeImageFile() throws -> String {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("asset-action-image-\(UUID().uuidString).png")
        try png.write(to: url)
        return url.path
    }

    private func makeAsset(
        id: String = "asset",
        source: AssetSource = .clipboard,
        contentType: AssetContentType = .text,
        text: String? = "asset text",
        imagePath: String? = nil,
        filePath: String? = nil,
        url: String? = nil,
        colorValue: String? = nil
    ) -> AssetItem {
        AssetItem(
            id: id,
            source: source,
            contentType: contentType,
            title: "asset",
            previewText: text,
            text: text,
            rawText: nil,
            imagePath: imagePath,
            filePath: filePath,
            url: url,
            colorValue: colorValue,
            sourceAppName: nil,
            sourceAppBundleID: nil,
            contentHash: "hash-\(id)",
            captureReason: .userCopied,
            metadataJSON: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            deletedAt: nil
        )
    }
}

@MainActor
private final class CapturingTextInserter: TextInserting {
    private(set) var insertedTexts: [String] = []
    var result: TextInsertionResult = .success

    func insert(_ text: String) async -> TextInsertionResult {
        insertedTexts.append(text)
        return result
    }
}

private final class CapturingPasteShortcutPoster: PasteShortcutPosting {
    private(set) var postCallCount = 0

    func postPasteShortcut() throws {
        postCallCount += 1
    }
}

private final class CapturingAssetActionRepository: AssetRepository {
    private(set) var deletedIDs: [String] = []
    private(set) var deletedAt: [Date] = []

    func save(_ item: AssetItem) throws {}

    func asset(id: String) throws -> AssetItem? { nil }

    func page(query: AssetQuery) throws -> AssetPage {
        AssetPage(items: [], totalCount: 0)
    }

    func softDelete(id: String, deletedAt: Date) throws {
        deletedIDs.append(id)
        self.deletedAt.append(deletedAt)
    }
}
