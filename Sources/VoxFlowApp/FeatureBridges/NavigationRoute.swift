import Foundation
import SwiftUI

enum NavigationRoute: String, CaseIterable, Identifiable {
    case home
    case screenshotRecord
    case vibeCoding
    case voiceCorrection
    case styles
    case fileTranscription
    case notes
    case settings
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return L10n.localize("navigation.route.home", comment: "")
        case .vibeCoding: return L10n.localize("navigation.route.vibe_coding", comment: "")
        case .voiceCorrection: return L10n.localize("navigation.route.voice_correction", comment: "")
        case .styles: return L10n.localize("navigation.route.styles", comment: "")
        case .fileTranscription: return L10n.localize("navigation.route.file_transcription", comment: "")
        case .notes: return L10n.localize("navigation.route.notes", comment: "")
        case .screenshotRecord: return L10n.localize("navigation.route.screenshot_record", comment: "")
        case .settings: return L10n.localize("navigation.route.settings", comment: "")
        case .help: return L10n.localize("navigation.route.help", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .vibeCoding: return "terminal"
        case .voiceCorrection: return "text.badge.checkmark"
        case .styles: return "slider.horizontal.3"
        case .fileTranscription: return "waveform.path.badge.plus"
        case .notes: return "note.text"
        case .screenshotRecord: return "photo.on.rectangle.angled"
        case .settings: return "gearshape"
        case .help: return "questionmark.circle"
        }
    }
}

struct WorkbenchNavigationCommand: Identifiable, Equatable {
    let id = UUID()
    let route: NavigationRoute
    let settingsSection: SettingsSection?

    static func settings(tab: SettingsTab) -> WorkbenchNavigationCommand {
        WorkbenchNavigationCommand(
            route: .settings,
            settingsSection: SettingsSection(settingsTab: tab)
        )
    }
}

@MainActor
final class WorkbenchNavigationRouter: ObservableObject {
    @Published private(set) var command: WorkbenchNavigationCommand?
    private static let logger = AppLogger.general

    func showSettings(tab: SettingsTab) {
        let section = SettingsSection(settingsTab: tab)
        Self.logger.debug(
            "WorkbenchNavigationRouter showSettings section=\(section.rawValue) tab=\(tab)"
        )
        command = .settings(tab: tab)
    }
}

extension SettingsSection {
    init(settingsTab: SettingsTab) {
        switch settingsTab {
        case .asr:
            self = .dictationModels
        case .llm:
            self = .correctionModels
        case .shortcut:
            self = .system
        }
    }
}
