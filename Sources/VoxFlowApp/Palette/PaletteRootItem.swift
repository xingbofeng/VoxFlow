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

    static let askAI = PaletteRootItemID(rawValue: "askAI")

    static func quicklink(_ link: PaletteQuicklink) -> PaletteRootItemID {
        PaletteRootItemID(rawValue: "quicklink:\(link.id)")
    }

    static func openURL(_ normalizedURL: String) -> PaletteRootItemID {
        PaletteRootItemID(rawValue: "openURL:\(normalizedURL)")
    }

    var openURLString: String? {
        guard rawValue.hasPrefix("openURL:") else { return nil }
        return String(rawValue.dropFirst("openURL:".count))
    }

    var description: String { rawValue }
}

enum PaletteRootItemKind: Equatable, Sendable {
    case command
    case application
    case ai
    case quicklink
    case link
}

enum PaletteRootIcon: Equatable, Sendable {
    case systemImage(String)
    case applicationIcon(path: String)
    case quicklinkImage(name: String)
    case websiteIcon(pageURL: String)
}

enum PaletteRootActivation: Equatable, Sendable {
    case command(PaletteCommand)
    case application(InstalledApplication)
    case askAI(prompt: String)
    case translate(text: String)
    case quicklink(PaletteQuicklink, query: String)
    case openURL(String)
}

enum PaletteRootAction: String, Equatable, Sendable {
    case open
    case addFavorite
    case removeFavorite

    var displayTitle: String {
        switch self {
        case .open:
            return L10n.localize("palette.root_item.action.open", comment: "")
        case .addFavorite:
            return L10n.localize("palette.root_item.action.add_favorite", comment: "")
        case .removeFavorite:
            return L10n.localize("palette.root_item.action.remove_favorite", comment: "")
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
            subtitle: L10n.localize("palette.root_item.subtitle.application", comment: ""),
            aliases: [application.bundleID].compactMap(\.self),
            icon: application.iconPath.map { .applicationIcon(path: $0) } ?? .systemImage("app"),
            activation: .application(application)
        )
    }

    static func askAI(prompt: String) -> PaletteRootItem {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = trimmed.isEmpty
            ? L10n.localize("palette.root_item.ask_ai.subtitle_empty", comment: "")
            : L10n.format("palette.root_item.ask_ai.subtitle_with_query", comment: "",
                Self.truncated(trimmed)
            )
        return PaletteRootItem(
            id: .askAI,
            kind: .ai,
            title: L10n.localize("palette.root_item.title.ask_ai", comment: ""),
            subtitle: subtitle,
            aliases: ["ai", "问ai", "问", "ask", "提问"],
            icon: .systemImage("sparkles"),
            activation: .askAI(prompt: trimmed)
        )
    }

    static func translate(text: String) -> PaletteRootItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = trimmed.isEmpty
            ? L10n.localize("palette.root_item.translate.subtitle_empty", comment: "")
            : L10n.format("palette.root_item.translate.subtitle_with_query", comment: "",
                Self.truncated(trimmed)
            )
        return PaletteRootItem(
            id: PaletteRootItemID(rawValue: "translateInput"),
            kind: .command,
            title: L10n.localize("palette.root_item.title.translate", comment: ""),
            subtitle: subtitle,
            aliases: ["translate", "translation", "翻译", "译"],
            icon: .systemImage("translate"),
            activation: .translate(text: trimmed)
        )
    }

    static func quicklink(_ link: PaletteQuicklink, query: String) -> PaletteRootItem {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty
            ? link.title
            : L10n.format("palette.root_item.quicklink.search_title_format", comment: "",
                link.title
            )
        let subtitle = trimmed.isEmpty
            ? link.homepageURL
            : L10n.format("palette.root_item.quicklink.search_subtitle_format", comment: "",
                Self.truncated(trimmed)
            )
        return PaletteRootItem(
            id: .quicklink(link),
            kind: .quicklink,
            title: title,
            subtitle: subtitle,
            aliases: link.aliases,
            icon: .quicklinkImage(name: link.iconResourceName),
            activation: .quicklink(link, query: trimmed)
        )
    }

    static func openURL(normalizedURL: String) -> PaletteRootItem {
        PaletteRootItem(
            id: .openURL(normalizedURL),
            kind: .link,
            title: L10n.localize("palette.root_item.title.open_website", comment: ""),
            subtitle: normalizedURL,
            aliases: [],
            icon: .websiteIcon(pageURL: normalizedURL),
            activation: .openURL(normalizedURL)
        )
    }

    private static func truncated(_ text: String, limit: Int = 60) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}

extension PaletteCommand {
    static let rootCommands: [PaletteCommand] = [
        .recentAssets,
        .assetHistory,
        .searchFiles,
        .screenshotOCR,
        .startAgentCompose,
        .startAgentDispatch,
        .startDictation,
    ]

    var rootTitle: String {
        switch self {
        case .recentAssets:
            return L10n.localize("palette.root_item.title.recent_assets", comment: "")
        case .assetHistory:
            return L10n.localize("palette.root_item.title.asset_history", comment: "")
        case .searchFiles:
            return L10n.localize("palette.root_item.title.search_files", comment: "")
        case .screenshotOCR:
            return L10n.localize("palette.root_item.title.screenshot_ocr", comment: "")
        case .startAgentCompose:
            return L10n.localize("palette.root_item.title.agent_compose", comment: "")
        case .startAgentDispatch:
            return L10n.localize("palette.root_item.title.agent_dispatch", comment: "")
        case .startDictation:
            return L10n.localize("palette.root_item.title.start_dictation", comment: "")
        }
    }

    var rootSubtitle: String {
        switch self {
        case .recentAssets:
            return L10n.localize("palette.root_item.subtitle.recent_assets", comment: "")
        case .assetHistory:
            return L10n.localize("palette.root_item.subtitle.asset_history", comment: "")
        case .searchFiles:
            return L10n.localize("palette.root_item.subtitle.search_files", comment: "")
        case .screenshotOCR:
            return L10n.localize("palette.root_item.subtitle.screenshot_ocr", comment: "")
        case .startAgentCompose:
            return L10n.localize("palette.root_item.subtitle.agent_compose", comment: "")
        case .startAgentDispatch:
            return L10n.localize("palette.root_item.subtitle.agent_dispatch", comment: "")
        case .startDictation:
            return L10n.localize("palette.root_item.subtitle.start_dictation", comment: "")
        }
    }

    var rootAliases: [String] {
        switch self {
        case .recentAssets:
            return ["asset", "assets", "recent", "最近", "资产"]
        case .assetHistory:
            return ["history", "asset", "assets", "历史", "资产"]
        case .searchFiles:
            return ["f", "search", "search files", "find", "file", "files", "文件", "搜索文件"]
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
        case .searchFiles:
            return "doc.text.magnifyingglass"
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
