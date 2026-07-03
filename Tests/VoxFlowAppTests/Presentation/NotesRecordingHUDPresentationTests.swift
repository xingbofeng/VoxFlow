import XCTest
@testable import VoxFlowApp

final class NotesRecordingHUDPresentationTests: XCTestCase {
    func testNotesPartialTextUsesNotesStreamingHUD() {
        let snapshot = NotesRecordingHUDPresentation.streamingSnapshot(
            text: "很长的笔记内容不应该在底部 HUD 里省略显示",
            isFinal: false
        )

        XCTAssertEqual(snapshot, .notesStreamingText("很长的笔记内容不应该在底部 HUD 里省略显示"))
    }

    func testNotesFinalTextDoesNotRenderIntoGlobalStreamingHUD() {
        let snapshot = NotesRecordingHUDPresentation.streamingSnapshot(
            text: "最终笔记内容由编辑器承载",
            isFinal: true
        )

        XCTAssertNil(snapshot)
    }
}
