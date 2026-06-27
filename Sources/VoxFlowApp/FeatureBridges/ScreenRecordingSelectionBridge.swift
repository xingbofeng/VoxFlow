import CoreGraphics
import VoxFlowScreenshotKit

struct ScreenRecordingOverlayControls {
    let showCountdown: @MainActor (Int) -> Void
    let showRecordingFrame: @MainActor () -> Void
    let excludedWindowIDs: @MainActor () -> [CGWindowID]
    let close: @MainActor () -> Void
}

@MainActor
final class ScreenRecordingSelectionBridge {
    var onSelection: ((SelectionState, ScreenshotDisplay, ScreenRecordingAudioMode, ScreenRecordingOverlayControls) -> Void)?

    func handle(_ result: SelectionOverlayResult, overlayControls: ScreenRecordingOverlayControls) {
        guard case let .acceptedScreenRecording(state, display, audioMode) = result else {
            return
        }
        onSelection?(state, display, audioMode, overlayControls)
    }
}
