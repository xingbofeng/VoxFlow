import XCTest
@testable import Mashangxie

/// Phase 4.11 — ClipboardDictationHandoffState state machine tests.
///
/// Covers: partial updates, final within finalizing window, finalizing
/// timeout with partial fallback, empty final does not overwrite, cancel,
/// background transitions, retry reset.
@MainActor
final class ClipboardDictationHandoffStateTests: XCTestCase {

    private func makeState() -> ClipboardDictationHandoffState {
        ClipboardDictationHandoffState(providerDisplayName: "TestProvider")
    }

    // MARK: - Initial state

    func testInitialStateIsPreparing() {
        let state = makeState()
        XCTAssertEqual(state.snapshot.phase, .preparing)
        XCTAssertEqual(state.snapshot.providerDisplayName, "TestProvider")
        XCTAssertTrue(state.snapshot.partialText.isEmpty)
        XCTAssertNil(state.snapshot.finalText)
        XCTAssertNil(state.snapshot.copiedText)
        XCTAssertNil(state.snapshot.copiedTextPreview)
        XCTAssertFalse(state.snapshot.copiedWasFallbackPartial)
        XCTAssertNil(state.snapshot.errorMessage)
    }

    // MARK: - Transitions into recording

    func testTransitionToRequestingPermissionFromPreparing() {
        let state = makeState()
        state.transitionToRequestingPermission()
        XCTAssertEqual(state.snapshot.phase, .requestingPermission)
    }

    func testTransitionToRecordingFromPreparing() {
        let state = makeState()
        state.transitionToRecording()
        XCTAssertEqual(state.snapshot.phase, .recording)
    }

    func testTransitionToRecordingFromRequestingPermission() {
        let state = makeState()
        state.transitionToRequestingPermission()
        state.transitionToRecording()
        XCTAssertEqual(state.snapshot.phase, .recording)
    }

    func testTransitionToRecordingRejectedFromRecording() {
        let state = makeState()
        state.transitionToRecording()
        state.transitionToRecording()  // no-op
        XCTAssertEqual(state.snapshot.phase, .recording)
    }

    // MARK: - Partial updates

    func testUpdatePartialDuringRecordingStoresTrimmedText() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("  你好世界  ")
        XCTAssertEqual(state.snapshot.partialText, "你好世界")
    }

    func testUpdatePartialDuringFinalizingUpdatesText() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("first")
        state.beginFinalizing()
        state.updatePartial("second")
        XCTAssertEqual(state.snapshot.partialText, "second")
        XCTAssertEqual(state.snapshot.phase, .finalizing)
    }

    // MARK: - Final text

    func testHandleFinalDuringRecordingTransitionsToCopied() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("partial")
        state.handleFinal("final result")
        XCTAssertEqual(state.snapshot.phase, .copied)
        XCTAssertEqual(state.snapshot.finalText, "final result")
        XCTAssertEqual(state.snapshot.copiedText, "final result")
        XCTAssertEqual(state.snapshot.copiedTextPreview, "final result")
        XCTAssertFalse(state.snapshot.copiedWasFallbackPartial)
    }

    func testHandleFinalDuringFinalizingTransitionsToCopied() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("partial")
        state.beginFinalizing()
        state.handleFinal("final result")
        XCTAssertEqual(state.snapshot.phase, .copied)
        XCTAssertEqual(state.snapshot.finalText, "final result")
        XCTAssertEqual(state.snapshot.copiedText, "final result")
    }

    // MARK: - Empty final

    func testEmptyFinalWithNoPartialTransitionsToEmptyAndDoesNotMarkCopied() {
        let state = makeState()
        state.transitionToRecording()
        state.handleFinal("   ")
        XCTAssertEqual(state.snapshot.phase, .empty)
        XCTAssertNil(state.snapshot.copiedText)
        XCTAssertNil(state.snapshot.copiedTextPreview)
        XCTAssertNil(state.snapshot.finalText)
    }

    func testEmptyFinalWithPartialFallsBackToPartial() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("partial text")
        state.handleFinal("   ")
        XCTAssertEqual(state.snapshot.phase, .copied)
        XCTAssertTrue(state.snapshot.copiedWasFallbackPartial)
        XCTAssertEqual(state.snapshot.copiedText, "partial text")
        XCTAssertEqual(state.snapshot.copiedTextPreview, "partial text")
        XCTAssertNil(state.snapshot.finalText)
    }

    // MARK: - Finalizing timeout (8s)

    func testFinalizingTimeoutWithPartialFallsBackToPartial() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("still partial")
        state.beginFinalizing()
        XCTAssertEqual(state.snapshot.phase, .finalizing)
        // Manually trigger the timeout — we don't want to wait 8s in tests.
        state.handleFinalizingTimeoutForTesting()
        XCTAssertEqual(state.snapshot.phase, .copied)
        XCTAssertTrue(state.snapshot.copiedWasFallbackPartial)
        XCTAssertEqual(state.snapshot.copiedText, "still partial")
        XCTAssertEqual(state.snapshot.copiedTextPreview, "still partial")
    }

    func testFinalizingTimeoutWithoutPartialTransitionsToEmpty() {
        let state = makeState()
        state.transitionToRecording()
        state.beginFinalizing()
        state.handleFinalizingTimeoutForTesting()
        XCTAssertEqual(state.snapshot.phase, .empty)
        XCTAssertNil(state.snapshot.copiedText)
        XCTAssertNil(state.snapshot.copiedTextPreview)
    }

    // MARK: - Cancel

    func testCancelDuringRecordingTransitionsToCancelled() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("partial")
        state.cancel()
        XCTAssertEqual(state.snapshot.phase, .cancelled)
    }

    func testCancelDuringFinalizingTransitionsToCancelled() {
        let state = makeState()
        state.transitionToRecording()
        state.beginFinalizing()
        state.cancel()
        XCTAssertEqual(state.snapshot.phase, .cancelled)
    }

    func testCancelDuringPreparingTransitionsToCancelled() {
        let state = makeState()
        state.cancel()
        XCTAssertEqual(state.snapshot.phase, .cancelled)
    }

    // MARK: - Fail

    func testFailTransitionsToFailedWithMessage() {
        let state = makeState()
        state.transitionToRecording()
        state.fail("microphone permission denied")
        XCTAssertEqual(state.snapshot.phase, .failed)
        XCTAssertEqual(state.snapshot.errorMessage, "microphone permission denied")
    }

    func testFailDuringFinalizingCancelsTimerAndTransitionsToFailed() {
        let state = makeState()
        state.transitionToRecording()
        state.beginFinalizing()
        state.fail("ASR error")
        XCTAssertEqual(state.snapshot.phase, .failed)
        XCTAssertEqual(state.snapshot.errorMessage, "ASR error")
    }

    // MARK: - Retry

    func testResetForRetryReturnsToPreparingWithCleanSnapshot() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("partial")
        state.fail("error")
        state.resetForRetry()
        XCTAssertEqual(state.snapshot.phase, .preparing)
        XCTAssertTrue(state.snapshot.partialText.isEmpty)
        XCTAssertNil(state.snapshot.finalText)
        XCTAssertNil(state.snapshot.copiedText)
        XCTAssertNil(state.snapshot.copiedTextPreview)
        XCTAssertFalse(state.snapshot.copiedWasFallbackPartial)
        XCTAssertNil(state.snapshot.errorMessage)
    }

    // MARK: - Background transitions

    func testBackgroundDuringRecordingCancelsWithoutCopy() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("partial")
        state.handleBackgroundTransition()
        XCTAssertEqual(state.snapshot.phase, .cancelled)
        // No copied text — pasteboard was NOT written.
        XCTAssertNil(state.snapshot.copiedText)
        XCTAssertNil(state.snapshot.copiedTextPreview)
    }

    func testBackgroundDuringFinalizingInvalidatesTimerButStaysInFinalizing() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("partial")
        state.beginFinalizing()
        state.handleBackgroundTransition()
        // The 8s timer is invalidated; the caller's 3s grace timer takes over.
        // We stay in .finalizing so the grace timer can still fire.
        XCTAssertEqual(state.snapshot.phase, .finalizing)
    }

    func testBackgroundGraceTimeoutFallsBackToPartial() {
        let state = makeState()
        state.transitionToRecording()
        state.updatePartial("partial")
        state.beginFinalizing()
        state.handleBackgroundTransition()
        state.handleFinalizingBackgroundGraceTimeout()
        XCTAssertEqual(state.snapshot.phase, .copied)
        XCTAssertTrue(state.snapshot.copiedWasFallbackPartial)
        XCTAssertEqual(state.snapshot.copiedText, "partial")
    }

    // MARK: - Copied preview truncation

    func testCopiedPreviewTruncatesLongText() {
        let state = makeState()
        state.transitionToRecording()
        let longText = String(repeating: "a", count: 100)
        state.handleFinal(longText)
        XCTAssertEqual(state.snapshot.phase, .copied)
        XCTAssertEqual(state.snapshot.copiedText, longText)
        // Preview should be shorter than the full text.
        XCTAssertLessThan(state.snapshot.copiedTextPreview?.count ?? 0, longText.count)
        XCTAssertTrue(state.snapshot.copiedTextPreview?.contains("…") == true)
    }
}
