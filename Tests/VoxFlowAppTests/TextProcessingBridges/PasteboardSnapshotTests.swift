import AppKit
import XCTest
import VoxFlowTextInsertion

final class PasteboardSnapshotTests: XCTestCase {
    func testSnapshotPreservesEveryItemAndDeclaredType() throws {
        let customType = NSPasteboard.PasteboardType("dev.voiceinput.custom")
        let first = NSPasteboardItem()
        first.setString("plain", forType: .string)
        first.setData(Data([0x01, 0x02]), forType: customType)

        let second = NSPasteboardItem()
        second.setData(Data("rich".utf8), forType: .rtf)

        let snapshot = PasteboardSnapshot(items: [first, second])

        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].representations[.string], Data("plain".utf8))
        XCTAssertEqual(snapshot.items[0].representations[customType], Data([0x01, 0x02]))
        XCTAssertEqual(snapshot.items[1].representations[.rtf], Data("rich".utf8))
    }

    func testSnapshotRecreatesMultiplePasteboardItems() {
        let snapshot = PasteboardSnapshot(
            archivedItems: [
                [.string: Data("first".utf8)],
                [.string: Data("second".utf8)],
            ]
        )

        let restored = snapshot.makePasteboardItems()

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].string(forType: .string), "first")
        XCTAssertEqual(restored[1].string(forType: .string), "second")
    }

    func testPasteboardTransactionRestoresOriginalWhenPasteboardIsUnchanged() throws {
        let pasteboard = try makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)

        let transaction = PasteboardTransaction.begin(
            on: pasteboard,
            replacementText: "voxflow inserted text"
        )

        XCTAssertEqual(pasteboard.string(forType: .string), "voxflow inserted text")
        XCTAssertTrue(transaction.restoreOriginalIfUnchanged(on: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }

    func testPasteboardTransactionDoesNotOverwriteUserCopyAfterPaste() throws {
        let pasteboard = try makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)

        let transaction = PasteboardTransaction.begin(
            on: pasteboard,
            replacementText: "voxflow inserted text"
        )
        pasteboard.clearContents()
        pasteboard.setString("user copied after paste", forType: .string)

        XCTAssertFalse(transaction.restoreOriginalIfUnchanged(on: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "user copied after paste")
    }

    func testPasteCompletionWaiterReturnsWhenPasteboardChangesDuringPolling() async throws {
        let pasteboard = try makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let transaction = PasteboardTransaction.begin(
            on: pasteboard,
            replacementText: "voxflow inserted text"
        )
        let waiter = PasteCompletionWaiter(pollIntervalNanoseconds: 10, maxPollCount: 5)
        var sleeps: [UInt64] = []

        let result = await waiter.waitForPasteWindow(
            on: pasteboard,
            transaction: transaction,
            sleep: { delay in
                sleeps.append(delay)
                pasteboard.clearContents()
                pasteboard.setString("user copied while waiting", forType: .string)
            }
        )

        XCTAssertEqual(result, .pasteboardChanged)
        XCTAssertEqual(sleeps, [10])
    }

    func testPasteCompletionWaiterPollsTransactionInsteadOfSingleFixedDelay() async throws {
        let pasteboard = try makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let transaction = PasteboardTransaction.begin(
            on: pasteboard,
            replacementText: "voxflow inserted text"
        )
        let waiter = PasteCompletionWaiter(pollIntervalNanoseconds: 20, maxPollCount: 3)
        var sleeps: [UInt64] = []

        let result = await waiter.waitForPasteWindow(
            on: pasteboard,
            transaction: transaction,
            sleep: { delay in sleeps.append(delay) }
        )

        XCTAssertEqual(result, .pasteboardUnchangedAfterTimeout)
        XCTAssertEqual(sleeps, [20, 20, 20])
    }

    private func makePasteboard() throws -> NSPasteboard {
        try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("PasteboardSnapshotTests-\(UUID().uuidString)")))
    }
}
