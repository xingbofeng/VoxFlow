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
        case .home: return "首页"
        case .vibeCoding: return "AI 编程"
        case .voiceCorrection: return "易错词"
        case .styles: return "风格"
        case .fileTranscription: return "文件转写"
        case .notes: return "笔记"
        case .screenshotRecord: return "多媒体"
        case .settings: return "设置"
        case .help: return "帮助"
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
