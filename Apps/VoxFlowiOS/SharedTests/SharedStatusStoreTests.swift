import XCTest
@testable import Shared

/// Focused tests for the shared status protocol (task 3.6).
///
/// These tests exercise `SharedStatusStore` against the real `AppGroup.defaults`
/// UserDefaults suite. They do NOT require a real App Group entitlement —
/// `UserDefaults(suiteName:)` returns a valid object even when the entitlement
/// is missing, it just won't be cross-process shared. For unit testing the
/// read/write/clear logic, this is sufficient.
final class SharedStatusStoreTests: XCTestCase {

    private var store: SharedStatusStore!

    override func setUp() {
        super.setUp()
        store = SharedStatusStore()
        // Clear all relevant keys before each test.
        let defaults = AppGroup.defaults
        for key in [
            SharedKeys.dictationStatus,
            SharedKeys.lastTranscription,
            SharedKeys.lastTranscriptionTimestamp,
            SharedKeys.liveTranscription,
            SharedKeys.liveTranscriptionTimestamp,
            SharedKeys.lastError,
            SharedKeys.stopRequested,
            SharedKeys.cancelRequested,
            SharedKeys.recordingHeartbeat,
            SharedKeys.coldStartActive,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Status

    func testReadStatusReturnsNilWhenUnset() {
        XCTAssertNil(store.readStatus())
    }

    func testWriteThenReadStatus() {
        store.writeStatus(.recording)
        XCTAssertEqual(store.readStatus(), .recording)
    }

    func testStatusTransitionsThroughFullCycle() {
        store.writeStatus(.requested)
        XCTAssertEqual(store.readStatus(), .requested)

        store.writeStatus(.recording)
        XCTAssertEqual(store.readStatus(), .recording)

        store.writeStatus(.transcribing)
        XCTAssertEqual(store.readStatus(), .transcribing)

        store.writeStatus(.ready)
        XCTAssertEqual(store.readStatus(), .ready)

        store.writeStatus(.idle)
        XCTAssertEqual(store.readStatus(), .idle)
    }

    // MARK: - Transcription

    func testWriteTranscriptionSetsTimestamp() {
        store.writeTranscription("你好世界")
        XCTAssertEqual(store.readTranscription(), "你好世界")
        let ts = store.readTranscriptionTimestamp()
        XCTAssertNotNil(ts)
        XCTAssertGreaterThan(ts!.timeIntervalSince1970, 0)
    }

    func testClearConsumedTranscriptionRemovesTextAndTimestamp() {
        store.writeTranscription("test")
        store.clearConsumedTranscription()
        XCTAssertNil(store.readTranscription())
        XCTAssertNil(store.readTranscriptionTimestamp())
    }

    func testClearConsumedTranscriptionIsIdempotent() {
        store.clearConsumedTranscription()  // no-op when unset
        store.clearConsumedTranscription()  // still no-op
        XCTAssertNil(store.readTranscription())
    }

    func testWriteLiveTranscriptionSetsTimestamp() {
        store.writeLiveTranscription("正在识别")
        XCTAssertEqual(store.readLiveTranscription(), "正在识别")
        let ts = store.readLiveTranscriptionTimestamp()
        XCTAssertNotNil(ts)
        XCTAssertGreaterThan(ts!.timeIntervalSince1970, 0)
    }

    func testClearLiveTranscriptionRemovesTextAndTimestamp() {
        store.writeLiveTranscription("partial")
        store.clearLiveTranscription()
        XCTAssertNil(store.readLiveTranscription())
        XCTAssertNil(store.readLiveTranscriptionTimestamp())
    }

    // MARK: - Stop / Cancel

    func testStopRequestedDefaultsToFalseAndConsumes() {
        XCTAssertFalse(store.consumeStopRequested())
    }

    func testSetStopRequestedThenConsumeReturnsTrueAndClears() {
        store.setStopRequested(true)
        XCTAssertTrue(store.consumeStopRequested())
        // Second consume should return false (already cleared).
        XCTAssertFalse(store.consumeStopRequested())
    }

    func testSetCancelRequestedThenConsumeReturnsTrueAndClears() {
        store.setCancelRequested(true)
        XCTAssertTrue(store.consumeCancelRequested())
        XCTAssertFalse(store.consumeCancelRequested())
    }

    // MARK: - Heartbeat

    func testWriteHeartbeatUpdatesTimestamp() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        store.writeHeartbeat(fixedDate)
        let read = store.readHeartbeat()
        XCTAssertEqual(read?.timeIntervalSince1970, 1_700_000_000)
    }

    func testReadHeartbeatReturnsNilWhenUnset() {
        XCTAssertNil(store.readHeartbeat())
    }

    // MARK: - Cold start

    func testColdStartActiveDefaultsToFalse() {
        XCTAssertFalse(store.consumeColdStartActive())
    }

    func testSetColdStartActiveThenConsumeReturnsTrueAndClears() {
        store.setColdStartActive(true)
        XCTAssertTrue(store.consumeColdStartActive())
        XCTAssertFalse(store.consumeColdStartActive())
    }

    // MARK: - Error

    func testWriteThenReadError() {
        store.writeError("missing credentials")
        XCTAssertEqual(store.readError(), "missing credentials")
    }

    func testClearErrorRemovesIt() {
        store.writeError("oops")
        store.clearError()
        XCTAssertNil(store.readError())
    }
}
