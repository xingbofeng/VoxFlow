import Foundation

/// iOS app 本地化助手。所有可见文案应通过 `L10n.t(_:)` 或 SwiftUI `Text("key")` 走 Localizable.strings。
///
/// 支持 5 种语言：en、zh-Hans、zh-Hant、ja、ko。缺失 key 时回退到英文。
enum L10n {
    /// 查找当前 bundle 的本地化字符串。
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// 带格式参数的本地化字符串。
    static func t(_ key: String, _ args: CVarArg...) -> String {
        let template = NSLocalizedString(key, comment: "")
        if args.isEmpty { return template }
        return String(format: template, locale: Locale.current, arguments: args)
    }
}
