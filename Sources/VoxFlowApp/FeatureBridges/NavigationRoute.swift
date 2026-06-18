import Foundation

enum NavigationRoute: String, CaseIterable, Identifiable {
    case home
    case glossary
    case styles
    case fileTranscription
    case notes
    case settings
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .glossary: return "词汇表"
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
        case .glossary: return "text.book.closed"
        case .styles: return "slider.horizontal.3"
        case .fileTranscription: return "waveform.path.badge.plus"
        case .notes: return "note.text"
        case .settings: return "gearshape"
        case .help: return "questionmark.circle"
        }
    }
}
