import AppKit
import SwiftUI
import XCTest
@testable import VoxFlowApp

@MainActor
final class NotesCursorTrackingTextEditorTests: XCTestCase {
    func testProgrammaticTextUpdateDoesNotEchoThroughDelegateBindings() {
        var text = "原文"
        var selection = NSRange(location: 2, length: 0)
        var isFocused = true
        let editor = CursorTrackingTextEditor(
            text: Binding(
                get: { text },
                set: { text = $0 }
            ),
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            )
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView()
        coordinator.textView = textView

        coordinator.performProgrammaticUpdate {
            textView.string = "程序更新"
            textView.setSelectedRange(NSRange(location: 4, length: 0))
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            coordinator.textViewDidChangeSelection(
                Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
            )
        }

        XCTAssertEqual(text, "原文")
        XCTAssertEqual(selection, NSRange(location: 2, length: 0))
        XCTAssertTrue(isFocused)
    }
}
