import Foundation

// MARK: - KnownApplicationEntry

struct KnownApplicationEntry: Equatable, Sendable {
    let bundleID: String
    let displayName: String
    let suggestedStyleID: String
}

// MARK: - KnownApplicationRegistry

struct KnownApplicationRegistry: Sendable {
    let version: Int
    let entries: [KnownApplicationEntry]

    func lookup(bundleID: String) -> KnownApplicationEntry? {
        let key = bundleID.lowercased()
        let result = entries.first { $0.bundleID.lowercased() == key }
        if result == nil {
            AppLogger.general.debug("KnownApplicationRegistry miss bundleID=\(bundleID)")
        }
        return result
    }

    static func builtIn() -> KnownApplicationRegistry {
        KnownApplicationRegistry(version: 2, entries: builtInEntries)
    }

    // MARK: - Built-in entries

    private static let builtInEntries: [KnownApplicationEntry] = [
        // Chat
        .init(bundleID: "com.tencent.xinWeChat",       displayName: "WeChat",   suggestedStyleID: "builtin.chat"),
        .init(bundleID: "com.tencent.Lark",             displayName: "Feishu",   suggestedStyleID: "builtin.chat"),
        .init(bundleID: "com.tinyspeck.slackmacgap",    displayName: "Slack",    suggestedStyleID: "builtin.chat"),
        .init(bundleID: "ru.keepcoder.Telegram",        displayName: "Telegram", suggestedStyleID: "builtin.chat"),
        .init(bundleID: "com.tencent.meeting",           displayName: "Tencent Meeting", suggestedStyleID: "builtin.chat"),

        // Email
        .init(bundleID: "com.apple.mail",               displayName: "Mail",     suggestedStyleID: "builtin.email"),
        .init(bundleID: "com.microsoft.Outlook",        displayName: "Outlook",  suggestedStyleID: "builtin.email"),

        // AI assistants and voice tools
        .init(bundleID: "com.openai.chat",               displayName: "ChatGPT",  suggestedStyleID: "builtin.original"),
        .init(bundleID: "com.anthropic.claudefordesktop", displayName: "Claude",  suggestedStyleID: "builtin.original"),
        .init(bundleID: "com.tencent.imamac",            displayName: "ima.copilot", suggestedStyleID: "builtin.original"),
        .init(bundleID: "com.nousresearch.hermes.setup", displayName: "Hermes",   suggestedStyleID: "builtin.original"),
        .init(bundleID: ProductBrand.bundleIdentifier, displayName: ProductBrand.displayName, suggestedStyleID: "builtin.original"),
        .init(bundleID: "cn.shandianshuo.desktop",       displayName: "闪电说",     suggestedStyleID: "builtin.original"),

        // Coding
        .init(bundleID: "com.microsoft.VSCode",         displayName: "VS Code",  suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.jetbrains.intellij",       displayName: "IntelliJ", suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.apple.dt.Xcode",           displayName: "Xcode",    suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.todesktop.cursors",        displayName: "Cursor",   suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.openai.codex",              displayName: "Codex",    suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.anthropic.claude-code-url-handler", displayName: "Claude Code", suggestedStyleID: "builtin.coding"),
        .init(bundleID: "dev.kiro.desktop",              displayName: "Kiro",     suggestedStyleID: "builtin.coding"),
        .init(bundleID: "ai.elementlabs.lmstudio",       displayName: "LM Studio", suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.aliyun.lingma.ide",         displayName: "Qoder CN", suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.qoder.work.cn",             displayName: "QoderWork CN", suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.ccswitch.desktop",          displayName: "CC Switch", suggestedStyleID: "builtin.coding"),
        .init(bundleID: "dev.zed.Zed",                   displayName: "Zed",      suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.postmanlabs.mac",           displayName: "Postman",  suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.tinyapp.TablePlus",         displayName: "TablePlus", suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.apple.Terminal",           displayName: "Terminal", suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.googlecode.iterm2",        displayName: "iTerm",    suggestedStyleID: "builtin.coding"),
        .init(bundleID: "dev.dirs.ghostty",             displayName: "Ghostty",  suggestedStyleID: "builtin.coding"),
        .init(bundleID: "com.mitchellh.ghostty",        displayName: "Ghostty",  suggestedStyleID: "builtin.coding"),
        .init(bundleID: "net.vmlx.app",                  displayName: "vMLX",     suggestedStyleID: "builtin.coding"),

        // Writing
        .init(bundleID: "com.apple.iWork.Pages",        displayName: "Pages",    suggestedStyleID: "builtin.formal"),
        .init(bundleID: "org.textforge.TextMate",       displayName: "TextMate", suggestedStyleID: "builtin.formal"),
        .init(bundleID: "md.obsidian",                  displayName: "Obsidian", suggestedStyleID: "builtin.formal"),
        .init(bundleID: "com.microsoft.Word",           displayName: "Word",     suggestedStyleID: "builtin.formal"),
        .init(bundleID: "io.open-design.desktop",       displayName: "Open Design", suggestedStyleID: "builtin.formal"),

        // Office
        .init(bundleID: "com.apple.iWork.Keynote",      displayName: "Keynote",  suggestedStyleID: "builtin.formal"),
        .init(bundleID: "com.apple.iWork.Numbers",      displayName: "Numbers",  suggestedStyleID: "builtin.formal"),
        .init(bundleID: "com.microsoft.Powerpoint",     displayName: "PowerPoint", suggestedStyleID: "builtin.formal"),
        .init(bundleID: "com.microsoft.Excel",          displayName: "Excel",    suggestedStyleID: "builtin.formal"),

        // Browser
        .init(bundleID: "com.apple.Safari",             displayName: "Safari",   suggestedStyleID: "builtin.casual"),
        .init(bundleID: "com.google.Chrome",            displayName: "Chrome",   suggestedStyleID: "builtin.casual"),
        .init(bundleID: "org.mozilla.firefox",           displayName: "Firefox",  suggestedStyleID: "builtin.casual"),
        .init(bundleID: "com.microsoft.edgemac",        displayName: "Edge",     suggestedStyleID: "builtin.casual"),
        .init(bundleID: "com.raycast.macos",            displayName: "Raycast",  suggestedStyleID: "builtin.casual"),
    ]
}
