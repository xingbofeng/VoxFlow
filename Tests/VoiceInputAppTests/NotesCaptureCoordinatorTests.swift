import XCTest
@testable import VoiceInputApp

@MainActor
final class NotesCaptureCoordinatorTests: XCTestCase {
    func testHotKeyRoutesOnlyWhileEditorIsFocused() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}

        coordinator.setEditorFocused(false)
        XCTAssertFalse(coordinator.shouldCaptureHotKey())

        coordinator.setEditorFocused(true)
        XCTAssertTrue(coordinator.shouldCaptureHotKey())
    }

    func testResetClearsFocusAndCallbacks() {
        let coordinator = NotesCaptureCoordinator()
        coordinator.startRecording = {}
        coordinator.finishRecording = {}
        coordinator.setEditorFocused(true)
        coordinator.isRecording = true

        coordinator.reset()

        XCTAssertFalse(coordinator.shouldCaptureHotKey())
        XCTAssertFalse(coordinator.isRecording)
        XCTAssertNil(coordinator.startRecording)
        XCTAssertNil(coordinator.finishRecording)
    }
}
