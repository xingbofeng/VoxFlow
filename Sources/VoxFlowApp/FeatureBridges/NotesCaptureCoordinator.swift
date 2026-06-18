import Foundation

/// Coordinates between the global hotkey handler and the notes recording flow.
/// When the notes view is active (visible and user is interacting), the global
/// hotkey triggers notes recording instead of global dictation.
@MainActor
final class NotesCaptureCoordinator {
    static let shared = NotesCaptureCoordinator()

    /// Whether the notes editor currently owns keyboard focus.
    private(set) var isActive = false

    /// Closure that starts notes recording. Set by NotesView when it appears.
    var startRecording: (() async -> Void)?

    /// Closure that finishes notes recording. Set by NotesView when it appears.
    var finishRecording: (() -> Void)?

    /// Whether the notes view is currently in a recording session.
    var isRecording: Bool = false

    /// Latest UTF-16 selection from the notes editor.
    var editorSelection = NSRange(location: 0, length: 0)

    init() {}

    func setEditorFocused(_ focused: Bool) {
        isActive = focused
    }

    /// Returns `true` if the global hotkey should be routed to notes recording.
    func shouldCaptureHotKey() -> Bool {
        isActive && startRecording != nil
    }

    func reset() {
        isActive = false
        startRecording = nil
        finishRecording = nil
        isRecording = false
        editorSelection = NSRange(location: 0, length: 0)
    }
}
