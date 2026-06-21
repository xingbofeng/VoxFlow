import Foundation
import SwiftUI

enum NavigationRoute: String, CaseIterable, Identifiable {
    case home
    case vibeCoding
    case glossary
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
        case .vibeCoding: return "Vibe Coding"
        case .glossary: return "词汇表"
        case .voiceCorrection: return "易错词"
        case .styles: return "风格"
        case .fileTranscription: return "文件转写"
        case .notes: return "笔记"
        case .settings: return "设置"
        case .help: return "帮助"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .vibeCoding: return "terminal"
        case .glossary: return "text.book.closed"
        case .voiceCorrection: return "text.badge.checkmark"
        case .styles: return "slider.horizontal.3"
        case .fileTranscription: return "waveform.path.badge.plus"
        case .notes: return "note.text"
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

    func showSettings(tab: SettingsTab) {
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
