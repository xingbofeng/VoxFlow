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
                title: L10n.localize("permission.item.accessibility_title", comment: "Accessibility item title"),
                subtitle: L10n.localize("permission.item.accessibility_subtitle", comment: "Accessibility item subtitle"),
                systemImage: "accessibility",
                status: PermissionSummary.statusText(accessibilityTrusted),
                granted: accessibilityTrusted,
                settingsURL: systemSettingsURL(for: .accessibility)
            ),
            PermissionStatusItem(
                title: L10n.localize("permission.item.microphone_title", comment: "Microphone item title"),
                subtitle: L10n.localize("permission.item.microphone_subtitle", comment: "Microphone item subtitle"),
                systemImage: "mic",
                status: PermissionSummary.statusText(microphonePermission == .granted),
                granted: microphonePermission == .granted,
                settingsURL: systemSettingsURL(for: .microphone)
            ),
            PermissionStatusItem(
                title: L10n.localize("permission.item.speech_title", comment: "Speech item title"),
                subtitle: L10n.localize("permission.item.speech_subtitle", comment: "Speech item subtitle"),
                systemImage: "waveform",
                status: PermissionSummary.speechRecognitionStatus(
                    engineType: engineType,
                    speechPermission: speechPermission
                ),
                granted: speechPermission == .granted,
                settingsURL: systemSettingsURL(for: .speech)
            ),
            PermissionStatusItem(
                title: L10n.localize("permission.item.screen_recording_title", comment: "Screen recording item title"),
                subtitle: L10n.localize("permission.item.screen_recording_subtitle", comment: "Screen recording item subtitle"),
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
                title: L10n.localize("permission.item.microphone_title", comment: "Microphone item title"),
                subtitle: L10n.localize("permission.item.microphone_subtitle", comment: "Microphone item subtitle"),
                systemImage: "mic",
                status: PermissionSummary.statusText(microphonePermission == .granted),
                granted: microphonePermission == .granted,
                settingsURL: systemSettingsURL(for: .microphone)
            ),
            PermissionStatusItem(
                title: L10n.localize("permission.item.speech_title", comment: "Speech item title"),
                subtitle: L10n.localize("permission.item.speech_subtitle", comment: "Speech item subtitle"),
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
