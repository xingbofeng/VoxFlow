import CoreGraphics
import Foundation

enum PermissionSummary {
    static func statusText(_ granted: Bool) -> String {
        granted ? "已授权" : "未授权"
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
                "需要录音与语音识别权限",
                """
                随声写需要麦克风和语音识别权限才能使用系统自带模型。

                请在 系统设置 → 隐私与安全性 中启用"麦克风"和"语音识别"权限。
                """
            )
        case .funASR, .whisper, .qwen3, .senseVoice, .paraformer, .nvidiaNemotron,
             .parakeetStreaming, .omnilingualASR:
            return (
                "需要麦克风权限",
                """
                随声写使用本地离线模型时只需要麦克风权限，不需要 Apple 语音识别权限。

                请在 系统设置 → 隐私与安全性 → 麦克风 中启用随声写。
                """
            )
        case .groqWhisper:
            return (
                "需要麦克风权限",
                """
                随声写使用 Groq 云端语音识别时只需要麦克风权限，不需要 Apple 语音识别权限。录音会发送到 Groq 进行转写。

                请在 系统设置 → 隐私与安全性 → 麦克风 中启用随声写。
                """
            )
        case .tencentCloud:
            return (
                "需要麦克风权限",
                """
                随声写使用腾讯云实时语音识别时只需要麦克风权限，不需要 Apple 语音识别权限。录音会发送到腾讯云进行流式转写。

                请在 系统设置 → 隐私与安全性 → 麦克风 中启用随声写。
                """
            )
        case .aliyunDashScope:
            return (
                "需要麦克风权限",
                """
                随声写使用阿里云百炼 DashScope 实时语音识别时只需要麦克风权限，不需要 Apple 语音识别权限。录音会发送到阿里云进行流式转写。

                请在 系统设置 → 隐私与安全性 → 麦克风 中启用随声写。
                """
            )
        }
    }

    // MARK: - Screen recording permission

    static func screenRecordingStatus() -> String {
        let hasAccess = CGPreflightScreenCaptureAccess()
        return statusText(hasAccess)
    }

    static func screenRecordingDescription() -> String {
        """
        "帮我说"功能可以截取当前窗口作为视觉上下文，帮助 LLM 更好地理解你的意图。

        截图仅在单次任务中使用，不会保存到磁盘或上传到任何服务器。

        请在 系统设置 → 隐私与安全性 → 屏幕录制 中启用随声写。
        """
    }

    static func screenRecordingAlertText() -> (title: String, body: String) {
        (
            "需要屏幕录制权限",
            screenRecordingDescription()
        )
    }
}
