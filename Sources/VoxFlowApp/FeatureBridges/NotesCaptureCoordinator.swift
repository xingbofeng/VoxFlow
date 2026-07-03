import Foundation

/// Coordinates between the global hotkey handler and the notes recording flow.
/// When the notes view is active (visible and user is interacting), the global
/// hotkey triggers notes recording instead of global dictation.
@MainActor
final class NotesCaptureCoordinator {
    static let shared = NotesCaptureCoordinator()

    /// Whether the notes view should own dictation hotkeys.
    var isActive: Bool {
        isViewVisible || isEditorFocused || isContinuingDictation
    }

    private(set) var isViewVisible = false {
        didSet {
            guard oldValue != isViewVisible else { return }
            AppLogger.dictation.debug("notes_capture_visibility changed isViewVisible=\(isViewVisible)")
        }
    }

    /// Whether the notes editor currently owns keyboard focus.
    private(set) var isEditorFocused = false {
        didSet {
            guard oldValue != isEditorFocused else { return }
            AppLogger.dictation.debug("notes_capture_focus changed isEditorFocused=\(isEditorFocused)")
        }
    }

    /// 用户在笔记详情中点了“继续听写”，听写热键应补充当前笔记，而不是走全局听写。
    /// 退出继续听写态或关闭详情时清空。
    private(set) var isContinuingDictation = false {
        didSet {
            guard oldValue != isContinuingDictation else { return }
            AppLogger.dictation.debug(
                "notes_capture_continuing changed isContinuingDictation=\(isContinuingDictation)"
            )
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

    var cancelRecording: (() -> Void)? {
        didSet {
            AppLogger.dictation.debug(
                "notes_capture_cancelRecording_handler_\(cancelRecording == nil ? "cleared" : "set")"
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

    var recordingStateDidChange: ((NotesRecordingState) -> Void)?
    var transcriptionDidChange: ((String, Bool) -> Void)?

    init() {}

    func setViewVisible(_ visible: Bool) {
        isViewVisible = visible
    }

    func setEditorFocused(_ focused: Bool) {
        AppLogger.dictation.debug("notes_capture_setEditorFocused focused=\(focused)")
        isEditorFocused = focused
    }

    /// 进入或退出继续听写态。由 NotesView 根据 ViewModel.detailMode 同步。
    func setContinuingDictation(_ continuing: Bool) {
        isContinuingDictation = continuing
    }

    /// Returns `true` if the global hotkey should be routed to notes recording.
    /// 条件：笔记页可见、编辑器 focus 或处于继续听写态，且 startRecording handler 已注册。
    func shouldCaptureHotKey(appIsForeground: Bool) -> Bool {
        appIsForeground && isActive && startRecording != nil
    }

    func reset() {
        AppLogger.dictation.debug("notes_capture_reset")
        isViewVisible = false
        isEditorFocused = false
        isContinuingDictation = false
        startRecording = nil
        finishRecording = nil
        cancelRecording = nil
        isRecording = false
        recordingStateDidChange?(.idle)
        editorSelection = NSRange(location: 0, length: 0)
    }
}
