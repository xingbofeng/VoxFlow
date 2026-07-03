import XCTest
@testable import VoxFlowApp

@MainActor
final class NotesCaptureCoordinatorTests: XCTestCase {
    func testHotKeyRoutesOnlyWhileEditorIsFocused() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}

        coordinator.setEditorFocused(false)
        XCTAssertFalse(coordinator.shouldCaptureHotKey(appIsForeground: true))

        coordinator.setEditorFocused(true)
        XCTAssertTrue(coordinator.shouldCaptureHotKey(appIsForeground: true))
    }

    func testHotKeyRoutesWhileNotesViewIsVisibleWithoutEditorFocus() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}

        coordinator.setEditorFocused(false)
        coordinator.setViewVisible(true)

        XCTAssertTrue(coordinator.shouldCaptureHotKey(appIsForeground: true))
        XCTAssertTrue(coordinator.isActive)
    }

    func testVisibleNotesViewDoesNotCaptureHotKeyWhenAppIsNotForeground() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}
        coordinator.setViewVisible(true)

        XCTAssertFalse(coordinator.shouldCaptureHotKey(appIsForeground: false))
        XCTAssertTrue(coordinator.shouldCaptureHotKey(appIsForeground: true))
    }

    func testResetClearsFocusAndCallbacks() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}
        coordinator.finishRecording = {}
        coordinator.setViewVisible(true)
        coordinator.setEditorFocused(true)
        coordinator.isRecording = true
        coordinator.editorSelection = NSRange(location: 8, length: 2)

        coordinator.reset()

        XCTAssertFalse(coordinator.shouldCaptureHotKey(appIsForeground: true))
        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(coordinator.isRecording)
        XCTAssertNil(coordinator.startRecording)
        XCTAssertNil(coordinator.finishRecording)
        XCTAssertEqual(coordinator.editorSelection, NSRange(location: 0, length: 0))
    }

    // MARK: - Continuing dictation routing (OpenSpec revamp-file-transcription-and-notes §6.3)

    func testContinuingDictationRoutesHotKeyToNotesEvenWithoutEditorFocus() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}

        coordinator.setEditorFocused(false)
        XCTAssertFalse(coordinator.shouldCaptureHotKey(appIsForeground: true))

        coordinator.setContinuingDictation(true)
        XCTAssertTrue(coordinator.shouldCaptureHotKey(appIsForeground: true))
    }

    func testContinuingDictationDoesNotCaptureHotKeyWhenAppIsNotForeground() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}
        coordinator.setContinuingDictation(true)

        XCTAssertFalse(coordinator.shouldCaptureHotKey(appIsForeground: false))
        XCTAssertTrue(coordinator.shouldCaptureHotKey(appIsForeground: true))
    }

    func testReadingModeWithoutFocusOrContinuingDoesNotRouteToNotes() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}

        coordinator.setEditorFocused(false)
        coordinator.setContinuingDictation(false)
        XCTAssertFalse(coordinator.shouldCaptureHotKey(appIsForeground: true))
    }

    func testExitingContinuingDictationRestoresGlobalRouting() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}

        coordinator.setContinuingDictation(true)
        XCTAssertTrue(coordinator.shouldCaptureHotKey(appIsForeground: true))

        coordinator.setContinuingDictation(false)
        XCTAssertFalse(coordinator.shouldCaptureHotKey(appIsForeground: true))
    }

    func testResetClearsContinuingDictation() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}
        coordinator.setContinuingDictation(true)

        coordinator.reset()

        XCTAssertFalse(coordinator.shouldCaptureHotKey(appIsForeground: true))
    }
}
