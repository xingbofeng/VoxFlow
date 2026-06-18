import AppKit
import XCTest
import VoxFlowTextInsertion

final class PasteboardTransactionTests: XCTestCase {
    func testTransactionRestoresOriginalOnlyWhenPasteboardIsUnchanged() throws {
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

    func testTransactionDoesNotOverwriteUserCopyAfterPaste() throws {
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

    func testWaiterReturnsWhenPasteboardChangesDuringPolling() async throws {
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

    private func makePasteboard() throws -> NSPasteboard {
        try XCTUnwrap(
            NSPasteboard(name: NSPasteboard.Name("VoxFlowTextInsertionTests-\(UUID().uuidString)"))
        )
    }
}
