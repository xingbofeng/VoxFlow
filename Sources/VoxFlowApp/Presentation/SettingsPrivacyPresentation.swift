import Foundation

enum SettingsPrivacyPresentation {
    struct ToggleRow: Equatable, Identifiable {
        let option: SettingsSystemOption
        let title: String
        let subtitle: String
        let systemImage: String

        var id: String { option.rawValue }
    }

    struct ManualCrashReportSupport: Equatable {
        let title: String
        let subtitle: String
        let viewSummaryButtonTitle: String
        let sendLatestButtonTitle: String
        let privacyLinkTitle: String
    }

    static var toggleRows: [ToggleRow] {
        [
            ToggleRow(
                option: .crashLogs,
                title: L10n.localize("settings.privacy.crash_logs_title", comment: ""),
                subtitle: L10n.localize("settings.privacy.crash_logs_subtitle", comment: ""),
                systemImage: "ladybug"
            ),
            ToggleRow(
                option: .llmTraceDiagnostics,
                title: L10n.localize("settings.privacy.llm_trace_title", comment: ""),
                subtitle: L10n.localize("settings.privacy.llm_trace_subtitle", comment: ""),
                systemImage: "doc.text.magnifyingglass"
            ),
        ]
    }

    static var manualCrashReportSupport: ManualCrashReportSupport {
        ManualCrashReportSupport(
            title: L10n.localize("settings.privacy.manual_crash_report_title", comment: ""),
            subtitle: L10n.localize("settings.privacy.manual_crash_report_subtitle", comment: ""),
            viewSummaryButtonTitle: L10n.localize("settings.privacy.manual_crash_report_view_summary", comment: ""),
            sendLatestButtonTitle: L10n.localize("settings.privacy.manual_crash_report_send_latest", comment: ""),
            privacyLinkTitle: L10n.localize("settings.privacy.crash_report_privacy_link", comment: "")
        )
    }
}
