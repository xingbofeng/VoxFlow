import AppKit
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class ScreenshotPasteboardSnapshotTests: XCTestCase {
    func testSnapshotRestoresTextAndMultipleItems() throws {
        let pasteboard = try makePasteboard()
        let customType = NSPasteboard.PasteboardType("com.voxflow.test.custom")
        let first = NSPasteboardItem()
        first.setString("原剪切板", forType: .string)
        let second = NSPasteboardItem()
        second.setData(Data([1, 2, 3]), forType: customType)
        pasteboard.writeObjects([first, second])
        let snapshot = ScreenshotPasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("截图临时内容", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.string(forType: .string), "原剪切板")
        XCTAssertEqual(pasteboard.pasteboardItems?.last?.data(forType: customType), Data([1, 2, 3]))
    }

    func testEmptySnapshotRestoresEmptyPasteboard() throws {
        let pasteboard = try makePasteboard()
        pasteboard.clearContents()
        let snapshot = ScreenshotPasteboardSnapshot.capture(from: pasteboard)

        pasteboard.setString("temporary", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
    }

    func testClipboardGuardRestoresOnlyWhenCancelled() throws {
        let pasteboard = try makePasteboard()
        pasteboard.setString("before screenshot", forType: .string)
        let guarder = ScreenshotClipboardGuard.begin(on: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("final screenshot image placeholder", forType: .string)
        guarder.restoreOnCancel()
        XCTAssertEqual(pasteboard.string(forType: .string), "before screenshot")

        pasteboard.clearContents()
        pasteboard.setString("before second screenshot", forType: .string)
        let secondGuard = ScreenshotClipboardGuard.begin(on: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("final screenshot image placeholder", forType: .string)
        secondGuard.keepOnSuccess()
        XCTAssertEqual(pasteboard.string(forType: .string), "final screenshot image placeholder")
    }

    private func makePasteboard() throws -> NSPasteboard {
        try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("ScreenshotPasteboardSnapshotTests-\(UUID().uuidString)")))
    }
}
