import CoreGraphics
import Foundation

enum PermissionSummary {
    static func statusText(_ granted: Bool) -> String {
        granted
            ? L10n.localize("permission.status.granted", comment: "Permission granted status text")
            : L10n.localize("permission.status.denied", comment: "Permission denied status text")
    }

    static func speechRecognitionStatus(
        engineType: ASREngineType,
        speechPermission: AudioRecorder.PermissionStatus
    ) -> String {
        _ = engineType
        return statusText(speechPermission == .granted)
    }

    static func recordingPermissionAlertText(engineType: ASREngineType) -> (title: String, body: String) {
        switch engineType {
        case .apple:
            return (
                L10n.localize("permission.alert.title.audio_and_speech", comment: "Permission alert title for Apple engine"),
                L10n.localize("permission.alert.body.apple", comment: "Permission body for Apple engine")
            )
        case .funASR, .whisper, .qwen3, .senseVoice, .paraformer, .nvidiaNemotron,
             .parakeetStreaming, .omnilingualASR:
            return (
                L10n.localize("permission.alert.title.microphone_only", comment: "Permission alert title for microphone-only engine"),
                L10n.localize("permission.alert.body.microphone_only_local", comment: "Permission body for offline local engine")
            )
        case .groqWhisper:
            return (
                L10n.localize("permission.alert.title.microphone_only", comment: "Permission alert title for microphone-only engine"),
                L10n.localize("permission.alert.body.microphone_only_cloud", comment: "Permission body for Groq engine")
            )
        case .tencentCloud:
            return (
                L10n.localize("permission.alert.title.microphone_only", comment: "Permission alert title for microphone-only engine"),
                L10n.localize("permission.alert.body.microphone_only_cloud", comment: "Permission body for Tencent cloud engine")
            )
        case .aliyunDashScope:
            return (
                L10n.localize("permission.alert.title.microphone_only", comment: "Permission alert title for microphone-only engine"),
                L10n.localize("permission.alert.body.aliyun_engine", comment: "Permission body for Aliyun engine")
            )
        case .volcengineDoubao:
            return (
                L10n.localize("permission.alert.title.microphone_only", comment: "Permission alert title for microphone-only engine"),
                L10n.localize("permission.alert.body.microphone_only_cloud", comment: "Permission body for Volcengine engine")
            )
        }
    }

    // MARK: - Screen recording permission

    static func screenRecordingStatus() -> String {
        let hasAccess = CGPreflightScreenCaptureAccess()
        return statusText(hasAccess)
    }

    static func screenRecordingDescription() -> String {
        L10n.localize("permission.screen.recording.description", comment: "Screen recording permission explanation")
    }

    static func screenRecordingAlertText() -> (title: String, body: String) {
        (
            L10n.localize("permission.alert.title.screen_recording", comment: "Permission alert title for screen recording"),
            screenRecordingDescription()
        )
    }

}
