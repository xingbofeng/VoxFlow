import AppKit
import XCTest
@testable import VoxFlowApp
import VoxFlowTextInsertion

final class ClipboardAssetMonitorTests: XCTestCase {
    func testInternalWriteGuardIgnoresMarkedChangeCount() {
        let guarder = ClipboardInternalWriteGuard()

        guarder.markInternalWrite(changeCount: 42)

        XCTAssertTrue(
            guarder.shouldIgnore(changeCount: 42, types: [.string])
        )
        XCTAssertFalse(
            guarder.shouldIgnore(changeCount: 43, types: [.string])
        )
    }

    func testInternalWriteGuardIgnoresVoxFlowPasteboardMarker() {
        let guarder = ClipboardInternalWriteGuard()

        XCTAssertTrue(
            guarder.shouldIgnore(changeCount: 7, types: [.voxFlowInternalMarker, .string])
        )
    }

    @MainActor
    func testMonitorPersistsPlainTextClipboardAsset() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: ClipboardInternalWriteGuard(),
            sourceApplicationProvider: {
                ClipboardSourceApplication(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92")
            }
        )

        pasteboard.clearContents()
        pasteboard.setString("把剪切板也纳入历史资产", forType: .string)

        let item = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        XCTAssertEqual(repository.savedItems.count, 1)
        XCTAssertEqual(item?.source, .clipboard)
        XCTAssertEqual(item?.contentType, .text)
        XCTAssertEqual(item?.text, "把剪切板也纳入历史资产")
        XCTAssertEqual(item?.title, "把剪切板也纳入历史资产")
        XCTAssertEqual(item?.sourceAppName, "Cursor")
        XCTAssertEqual(item?.sourceAppBundleID, "com.todesktop.230313mzl4w4u92")
    }

    @MainActor
    func testMonitorPersistsContentFromFirstSupportedPasteboardItem() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: ClipboardInternalWriteGuard()
        )
        let metadataItem = NSPasteboardItem()
        metadataItem.setString(
            "copy-button-metadata",
            forType: NSPasteboard.PasteboardType("com.example.copy-button.metadata")
        )
        let textItem = NSPasteboardItem()
        textItem.setString("copied from another app button", forType: .string)

        pasteboard.clearContents()
        pasteboard.writeObjects([metadataItem, textItem])

        let item = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        XCTAssertEqual(item?.text, "copied from another app button")
        XCTAssertEqual(repository.savedItems.map(\.id), [item?.id])
    }

    @MainActor
    func testMonitorIgnoresInternalVoxFlowWrites() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let guarder = ClipboardInternalWriteGuard()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: guarder
        )

        guarder.writeInternalString("fallback copy", to: pasteboard)

        let item = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        XCTAssertNil(item)
        XCTAssertTrue(repository.savedItems.isEmpty)
    }

    @MainActor
    func testMonitorIgnoresFastPasteReplacementAndRestoreWrites() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let guarder = ClipboardInternalWriteGuard()
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: guarder
        )

        let transaction = PasteboardTransaction.begin(
            on: pasteboard,
            replacementText: "corrected dictation text",
            markInternalChangeCount: { guarder.markInternalWrite(changeCount: $0) }
        )
        let replacementItem = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        XCTAssertNil(replacementItem)
        XCTAssertTrue(repository.savedItems.isEmpty)

        XCTAssertTrue(transaction.restoreOriginalIfUnchanged(on: pasteboard))
        let restoredItem = try monitor.processIfChanged(now: date("2026-06-23T10:01:00Z"))

        XCTAssertNil(restoredItem)
        XCTAssertTrue(repository.savedItems.isEmpty)
    }

    @MainActor
    func testFastPasteInternalWritesDoNotChangeHomeAssetStatistics() throws {
        let pasteboard = try makePasteboard()
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        let guarder = ClipboardInternalWriteGuard()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: environment.assetRepository,
            internalWriteGuard: guarder
        )
        let viewModel = HomeDashboardViewModel(environment: environment)

        pasteboard.clearContents()
        pasteboard.setString("user clipboard before dictation", forType: .string)
        try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        viewModel.load()
        XCTAssertEqual(viewModel.stats.totalAssets, 1)
        XCTAssertEqual(viewModel.stats.sourceBreakdown, HomeSourceBreakdown(clipboard: 1))

        let transaction = PasteboardTransaction.begin(
            on: pasteboard,
            replacementText: "corrected dictation text",
            markInternalChangeCount: { guarder.markInternalWrite(changeCount: $0) }
        )
        try monitor.processIfChanged(now: date("2026-06-23T10:01:00Z"))
        XCTAssertTrue(transaction.restoreOriginalIfUnchanged(on: pasteboard))
        try monitor.processIfChanged(now: date("2026-06-23T10:02:00Z"))

        viewModel.load()
        XCTAssertEqual(viewModel.stats.totalAssets, 1)
        XCTAssertEqual(viewModel.stats.sourceBreakdown, HomeSourceBreakdown(clipboard: 1))

        pasteboard.clearContents()
        pasteboard.setString("user clipboard after dictation", forType: .string)
        try monitor.processIfChanged(now: date("2026-06-23T10:03:00Z"))

        viewModel.load()
        XCTAssertEqual(viewModel.stats.totalAssets, 2)
        XCTAssertEqual(viewModel.stats.sourceBreakdown, HomeSourceBreakdown(clipboard: 2))
    }

    @MainActor
    func testMonitorPersistsUniversalClipboardWrites() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: ClipboardInternalWriteGuard()
        )

        let item = NSPasteboardItem()
        item.setString("from another device", forType: .string)
        item.setString("1", forType: .universalClipboard)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let asset = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        XCTAssertEqual(asset?.source, .clipboard)
        XCTAssertEqual(asset?.contentType, .text)
        XCTAssertEqual(asset?.text, "from another device")
        XCTAssertEqual(repository.savedItems.map(\.id), [asset?.id])
    }

    @MainActor
    func testMonitorPersistsPlainTextURLAndColorAsSpecificAssetTypes() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: ClipboardInternalWriteGuard()
        )

        pasteboard.clearContents()
        pasteboard.setString("https://example.com/voxflow", forType: .string)
        let link = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        pasteboard.clearContents()
        pasteboard.setString("#08745f", forType: .string)
        let color = try monitor.processIfChanged(now: date("2026-06-23T10:01:00Z"))

        XCTAssertEqual(link?.contentType, .link)
        XCTAssertEqual(link?.url, "https://example.com/voxflow")
        XCTAssertEqual(color?.contentType, .color)
        XCTAssertEqual(color?.colorValue, "#08745f")
        XCTAssertEqual(repository.savedItems.map(\.contentType), [.link, .color])
    }

    @MainActor
    func testMonitorRecordsTokenLikeTextAsOrdinaryClipboardAsset() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: ClipboardInternalWriteGuard()
        )

        pasteboard.clearContents()
        pasteboard.setString("sk-live-token-should-still-be-recorded", forType: .string)

        let item = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        XCTAssertEqual(item?.contentType, .text)
        XCTAssertEqual(item?.text, "sk-live-token-should-still-be-recorded")
    }

    @MainActor
    func testMonitorPersistsFileURLClipboardAsset() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: ClipboardInternalWriteGuard()
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxflow-clipboard-file.txt")
        try "asset file".write(to: fileURL, atomically: true, encoding: .utf8)

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])

        let item = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        XCTAssertEqual(item?.contentType, .file)
        XCTAssertEqual(item?.filePath, fileURL.path)
        XCTAssertEqual(item?.title, "voxflow-clipboard-file.txt")
    }

    @MainActor
    func testMonitorPersistsImageClipboardAssetWithStoredImagePath() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: ClipboardInternalWriteGuard(),
            imageDataWriter: { data, contentHash in
                XCTAssertFalse(data.isEmpty)
                return "/tmp/\(contentHash).png"
            }
        )
        let image = try makeImage()

        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        let item = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        XCTAssertEqual(item?.contentType, .image)
        XCTAssertEqual(item?.imagePath?.hasSuffix(".png"), true)
    }

    @MainActor
    func testMonitorDeduplicatesRepeatedCopiesByContentHash() throws {
        let pasteboard = try makePasteboard()
        let repository = CapturingAssetRepository()
        let monitor = ClipboardAssetMonitor(
            pasteboard: pasteboard,
            repository: repository,
            internalWriteGuard: ClipboardInternalWriteGuard()
        )

        pasteboard.clearContents()
        pasteboard.setString("repeat me", forType: .string)
        let first = try monitor.processIfChanged(now: date("2026-06-23T10:00:00Z"))

        pasteboard.clearContents()
        pasteboard.setString("repeat me", forType: .string)
        let second = try monitor.processIfChanged(now: date("2026-06-23T10:01:00Z"))

        XCTAssertEqual(repository.savedItems.count, 1)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(second?.createdAt, date("2026-06-23T10:00:00Z"))
        XCTAssertEqual(second?.updatedAt, date("2026-06-23T10:01:00Z"))
    }

    private func makePasteboard() throws -> NSPasteboard {
        let name = NSPasteboard.Name("ClipboardAssetMonitorTests-\(UUID().uuidString)")
        return try XCTUnwrap(NSPasteboard(name: name))
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func makeImage() throws -> NSImage {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        return image
    }
}

private final class CapturingAssetRepository: AssetRepository {
    private(set) var savedItems: [AssetItem] = []

    func save(_ item: AssetItem) throws {
        savedItems.removeAll { $0.id == item.id }
        savedItems.append(item)
    }

    func asset(id: String) throws -> AssetItem? {
        savedItems.first { $0.id == id && $0.deletedAt == nil }
    }

    func page(query: AssetQuery) throws -> AssetPage {
        AssetPage(items: savedItems, totalCount: savedItems.count)
    }

    func softDelete(id: String, deletedAt: Date) throws {}
}
