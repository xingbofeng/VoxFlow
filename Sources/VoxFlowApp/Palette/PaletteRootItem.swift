import Foundation

struct PaletteRootItemID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func command(_ command: PaletteCommand) -> PaletteRootItemID {
        PaletteRootItemID(rawValue: "command:\(command.rawValue)")
    }

    static func application(_ application: InstalledApplication) -> PaletteRootItemID {
        PaletteRootItemID(rawValue: "application:\(application.id)")
    }

    var description: String { rawValue }
}

enum PaletteRootItemKind: Equatable, Sendable {
    case command
    case application
}

enum PaletteRootIcon: Equatable, Sendable {
    case systemImage(String)
    case applicationIcon(path: String)
}

enum PaletteRootActivation: Equatable, Sendable {
    case command(PaletteCommand)
    case application(InstalledApplication)
}

enum PaletteRootAction: String, Equatable, Sendable {
    case open
    case addFavorite
    case removeFavorite

    var displayTitle: String {
        switch self {
        case .open:
            return "打开"
        case .addFavorite:
            return "加入最喜欢"
        case .removeFavorite:
            return "从最喜欢移除"
        }
    }

    var systemImageName: String {
        switch self {
        case .open:
            return "arrow.turn.down.left"
        case .addFavorite:
            return "star"
        case .removeFavorite:
            return "star.slash"
        }
    }

    var shortcutBadges: [String] {
        switch self {
        case .open:
            return ["↩"]
        case .addFavorite, .removeFavorite:
            return ["⇧", "⌘", "F"]
        }
    }
}

struct PaletteRootItem: Equatable, Identifiable, Sendable {
    let id: PaletteRootItemID
    let kind: PaletteRootItemKind
    let title: String
    let subtitle: String
    let aliases: [String]
    let icon: PaletteRootIcon
    let activation: PaletteRootActivation

    static func command(_ command: PaletteCommand) -> PaletteRootItem {
        PaletteRootItem(
            id: .command(command),
            kind: .command,
            title: command.rootTitle,
            subtitle: command.rootSubtitle,
            aliases: command.rootAliases,
            icon: .systemImage(command.rootSystemImageName),
            activation: .command(command)
        )
    }

    static func application(_ application: InstalledApplication) -> PaletteRootItem {
        PaletteRootItem(
            id: .application(application),
            kind: .application,
            title: application.name,
            subtitle: "应用",
            aliases: [application.bundleID].compactMap(\.self),
            icon: application.iconPath.map { .applicationIcon(path: $0) } ?? .systemImage("app"),
            activation: .application(application)
        )
    }
}

extension PaletteCommand {
    static let rootCommands: [PaletteCommand] = [
        .recentAssets,
        .assetHistory,
        .screenshotOCR,
        .startAgentCompose,
        .startAgentDispatch,
        .startDictation,
    ]

    var rootTitle: String {
        switch self {
        case .recentAssets:
            return "最近资产"
        case .assetHistory:
            return "历史资产"
        case .screenshotOCR:
            return "截图 OCR"
        case .startAgentCompose:
            return "帮我说"
        case .startAgentDispatch:
            return "AI 编程"
        case .startDictation:
            return "开始听写"
        }
    }

    var rootSubtitle: String {
        switch self {
        case .recentAssets:
            return "打开最近的语音、截图和剪切板"
        case .assetHistory:
            return "查看全部历史资产"
        case .screenshotOCR:
            return "框选截图并识别文字"
        case .startAgentCompose:
            return "口述需求，生成可直接输入的文本"
        case .startAgentDispatch:
            return "语音触发 AI 编程控制台"
        case .startDictation:
            return "按住快捷键说话"
        }
    }

    var rootAliases: [String] {
        switch self {
        case .recentAssets:
            return ["asset", "assets", "recent", "最近", "资产"]
        case .assetHistory:
            return ["history", "asset", "assets", "历史", "资产"]
        case .screenshotOCR:
            return ["ocr", "screenshot", "截图", "识别"]
        case .startAgentCompose:
            return ["compose", "agent", "帮我说", "口述"]
        case .startAgentDispatch:
            return ["ai", "code", "coding", "terminal", "编程"]
        case .startDictation:
            return ["dict", "dictation", "mic", "voice", "听写"]
        }
    }

    var rootSystemImageName: String {
        switch self {
        case .recentAssets, .assetHistory:
            return "tray.full"
        case .screenshotOCR:
            return "text.viewfinder"
        case .startAgentCompose:
            return "quote.bubble"
        case .startAgentDispatch:
            return "terminal"
        case .startDictation:
            return "mic"
        }
    }
}
