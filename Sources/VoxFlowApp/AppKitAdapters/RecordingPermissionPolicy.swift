import Foundation

enum RecordingPermissionPolicy {
    static func hasRequiredPermissions(
        engineType: ASREngineType,
        microphonePermission: AudioRecorder.PermissionStatus,
        speechPermission: AudioRecorder.PermissionStatus
    ) -> Bool {
        let microGranted = microphonePermission == .granted

        guard microGranted else {
            AppLogger.general.warning(
                "RecordingPermissionPolicy denied: microphonePermission=\(permissionStatusName(microphonePermission))"
            )
            return false
        }

        let result: Bool = {
            switch engineType {
        case .apple:
            return speechPermission == .granted
        case .funASR, .whisper, .qwen3, .senseVoice, .paraformer, .nvidiaNemotron,
             .parakeetStreaming, .omnilingualASR:
            return true
        case .groqWhisper, .tencentCloud, .aliyunDashScope, .volcengineDoubao:
            return true
            }
        }()

        if !result && engineType == .apple {
            AppLogger.general.warning(
                "RecordingPermissionPolicy denied: speechPermission=\(permissionStatusName(speechPermission)) " +
                "engine=\(engineType.rawValue)"
            )
        }

        AppLogger.general.debug(
            "RecordingPermissionPolicy evaluated: engine=\(engineType.rawValue) " +
            "microphone=\(permissionStatusName(microphonePermission)) speech=\(permissionStatusName(speechPermission)) " +
            "result=\(result)"
        )

        return result
    }

    private static func permissionStatusName(_ status: AudioRecorder.PermissionStatus) -> String {
        switch status {
        case .granted:
            return "granted"
        case .denied:
            return "denied"
        case .notDetermined:
            return "notDetermined"
        }
    }
}
