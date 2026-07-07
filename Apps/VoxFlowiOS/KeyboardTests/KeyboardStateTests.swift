import XCTest
@testable import Shared

@MainActor
final class KeyboardStateTests: XCTestCase {
    private var state: KeyboardState!

    override func setUp() async throws {
        try await super.setUp()
        state = KeyboardState.shared
        resetSharedState()
        BridgeModeStore.write(.appGroup)
        state.openURL = nil
        state.onTranscriptionInserted = nil
        state.forceResetToIdle()
        state.resetMicDebounceForTesting()
    }

    override func tearDown() async throws {
        state.openURL = nil
        state.onTranscriptionInserted = nil
        state.forceResetToIdle()
        state.resetMicDebounceForTesting()
        resetSharedState()
        try await super.tearDown()
    }

    func testStartRecordingMarksRequestedAndFallsBackToURLWhenAppDoesNotRespond() async throws {
        let fallbackOpened = expectation(description: "Fallback URL opened")
        var openedURL: URL?

        state.openURL = { url in
            openedURL = url
            fallbackOpened.fulfill()
        }

        state.startRecording()

        await fulfillment(of: [fallbackOpened], timeout: 1.2)
        XCTAssertEqual(AppGroup.defaults.string(forKey: SharedKeys.dictationStatus), DictationStatus.requested.rawValue)
        XCTAssertEqual(state.dictationStatus, .requested)
        XCTAssertEqual(openedURL?.absoluteString, "mashangxie://dictate?source=keyboard")
    }

    func testTranscriptionReadyClearsSharedTranscriptionAndResetsState() async throws {
        let inserted = expectation(description: "Transcription insertion path completed")
        AppGroup.defaults.set("你好世界", forKey: SharedKeys.lastTranscription)
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
        AppGroup.defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
        AppGroup.defaults.synchronize()

        state.onTranscriptionInserted = {
            inserted.fulfill()
        }

        DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)

        await fulfillment(of: [inserted], timeout: 1.0)
        XCTAssertNil(AppGroup.defaults.string(forKey: SharedKeys.lastTranscription))
        XCTAssertEqual(AppGroup.defaults.double(forKey: SharedKeys.lastTranscriptionTimestamp), 0)
        XCTAssertEqual(state.dictationStatus, .idle)
    }

    func testLiveTranscriptionNotificationUpdatesVisiblePartialText() async throws {
        let store = SharedStatusStore()
        store.writeLiveTranscription("正在识别")
        AppGroup.defaults.set(DictationStatus.recording.rawValue, forKey: SharedKeys.dictationStatus)
        AppGroup.defaults.synchronize()

        DarwinNotificationCenter.post(DarwinNotificationName.transcriptionPartial)

        for _ in 0..<20 {
            if state.liveTranscription == "正在识别" {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTFail("KeyboardState did not publish live transcription partial text")
    }

    func testStopAndCancelRequestsWriteConsumableFlags() {
        let store = SharedStatusStore()

        state.requestStop()
        XCTAssertTrue(store.consumeStopRequested())
        XCTAssertFalse(store.consumeStopRequested())

        state.requestCancel()
        XCTAssertTrue(store.consumeCancelRequested())
        XCTAssertFalse(store.consumeCancelRequested())
        XCTAssertEqual(state.dictationStatus, .idle)
    }

    private func resetSharedState() {
        for key in [
            SharedKeys.dictationStatus,
            SharedKeys.lastTranscription,
            SharedKeys.lastTranscriptionTimestamp,
            SharedKeys.liveTranscription,
            SharedKeys.liveTranscriptionTimestamp,
            SharedKeys.lastError,
            SharedKeys.stopRequested,
            SharedKeys.cancelRequested,
            SharedKeys.waveformEnergy,
            SharedKeys.recordingElapsedSeconds,
            SharedKeys.recordingHeartbeat,
            SharedKeys.coldStartActive,
        ] {
            AppGroup.defaults.removeObject(forKey: key)
        }
        AppGroup.defaults.synchronize()
    }
}
