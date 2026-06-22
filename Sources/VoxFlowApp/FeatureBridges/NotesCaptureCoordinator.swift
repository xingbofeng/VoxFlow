import Foundation

/// Coordinates between the global hotkey handler and the notes recording flow.
/// When the notes view is active (visible and user is interacting), the global
/// hotkey triggers notes recording instead of global dictation.
@MainActor
final class NotesCaptureCoordinator {
    static let shared = NotesCaptureCoordinator()

    /// Whether the notes editor currently owns keyboard focus.
    private(set) var isActive = false {
        didSet {
            guard oldValue != isActive else { return }
            AppLogger.dictation.debug("notes_capture_focus changed isActive=\(isActive)")
        }
    }

    /// Closure that starts notes recording. Set by NotesView when it appears.
    var startRecording: (() async -> Void)? {
        didSet {
            AppLogger.dictation.debug(
                "notes_capture_startRecording_handler_\(startRecording == nil ? "cleared" : "set")"
            )
        }
    }

    /// Closure that finishes notes recording. Set by NotesView when it appears.
    var finishRecording: (() -> Void)? {
        didSet {
            AppLogger.dictation.debug(
                "notes_capture_finishRecording_handler_\(finishRecording == nil ? "cleared" : "set")"
            )
        }
    }

    /// Whether the notes view is currently in a recording session.
    var isRecording: Bool = false {
        didSet {
            guard oldValue != isRecording else { return }
            AppLogger.dictation.debug("notes_capture_recording changed isRecording=\(isRecording)")
        }
    }

    /// Latest UTF-16 selection from the notes editor.
    var editorSelection = NSRange(location: 0, length: 0)

    init() {}

    func setEditorFocused(_ focused: Bool) {
        AppLogger.dictation.debug("notes_capture_setEditorFocused focused=\(focused)")
        isActive = focused
    }

    /// Returns `true` if the global hotkey should be routed to notes recording.
    func shouldCaptureHotKey() -> Bool {
        isActive && startRecording != nil
    }

    func reset() {
        AppLogger.dictation.debug("notes_capture_reset")
        isActive = false
        startRecording = nil
        finishRecording = nil
        isRecording = false
        editorSelection = NSRange(location: 0, length: 0)
    }
}
