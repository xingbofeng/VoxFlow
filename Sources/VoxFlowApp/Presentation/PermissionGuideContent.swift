import Foundation

enum PermissionGuideContent {
    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy"
    )
    static let privacySecuritySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity"
    )

    static func allPermissionItems(
        microphonePermission: AudioRecorder.PermissionStatus,
        speechPermission: AudioRecorder.PermissionStatus,
        accessibilityTrusted: Bool,
        screenRecordingGranted: Bool,
        engineType: ASREngineType
    ) -> [PermissionStatusItem] {
        [
            PermissionStatusItem(
                title: "辅助功能",
                subtitle: "监听快捷键并向当前应用输入转写文本",
                systemImage: "accessibility",
                status: PermissionSummary.statusText(accessibilityTrusted),
                granted: accessibilityTrusted,
                settingsURL: systemSettingsURL(for: .accessibility)
            ),
            PermissionStatusItem(
                title: "麦克风",
                subtitle: "录制你的声音用于听写",
                systemImage: "mic",
                status: PermissionSummary.statusText(microphonePermission == .granted),
                granted: microphonePermission == .granted,
                settingsURL: systemSettingsURL(for: .microphone)
            ),
            PermissionStatusItem(
                title: "语音识别",
                subtitle: "Apple 语音识别的真实系统授权状态",
                systemImage: "waveform",
                status: PermissionSummary.speechRecognitionStatus(
                    engineType: engineType,
                    speechPermission: speechPermission
                ),
                granted: speechPermission == .granted,
                settingsURL: systemSettingsURL(for: .speech)
            ),
            PermissionStatusItem(
                title: "屏幕录制",
                subtitle: "用于“帮我说”的当前窗口 OCR，不保存截图",
                systemImage: "rectangle.inset.filled.and.person.filled",
                status: PermissionSummary.statusText(screenRecordingGranted),
                granted: screenRecordingGranted,
                settingsURL: systemSettingsURL(for: .screenRecording)
            ),
        ]
    }

    static func recordingPermissionItems(
        microphonePermission: AudioRecorder.PermissionStatus,
        speechPermission: AudioRecorder.PermissionStatus
    ) -> [PermissionStatusItem] {
        [
            PermissionStatusItem(
                title: "麦克风",
                subtitle: "录制你的声音用于听写",
                systemImage: "mic",
                status: PermissionSummary.statusText(microphonePermission == .granted),
                granted: microphonePermission == .granted,
                settingsURL: systemSettingsURL(for: .microphone)
            ),
            PermissionStatusItem(
                title: "语音识别",
                subtitle: "Apple 语音识别的真实系统授权状态",
                systemImage: "waveform",
                status: PermissionSummary.statusText(speechPermission == .granted),
                granted: speechPermission == .granted,
                settingsURL: systemSettingsURL(for: .speech)
            ),
        ]
    }

    static func systemSettingsURL(for pane: SystemSettingsPane) -> URL? {
        switch pane {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speech:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }
}
