import Foundation

@MainActor
enum KeyboardVoiceEntryCoordinator {
    static func prepareChineseCompositionAndStartRecording(
        prepareChineseComposition: (() async -> Void)?,
        startRecording: () -> Void
    ) async {
        await prepareChineseComposition?()
        startRecording()
    }
}
