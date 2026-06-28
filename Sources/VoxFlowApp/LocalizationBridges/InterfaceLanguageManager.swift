import Foundation

/// 管理 App 界面显示语言偏好，独立于语音识别语言（`LanguageManager`）。
///
/// 切换机制：写 `UserDefaults "AppleLanguages"` override + 重启 App 生效。
/// 默认 `.followSystem`（不写 override，跟随系统 locale）。
/// 非中文系统的 fallback 以 `Info.plist` 的 `CFBundleLocalizations` 为准。
/// 与 `Info.plist` 的 `CFBundleDevelopmentRegion` 一同保证。
@MainActor
final class InterfaceLanguageManager: NSObject {
    static let shared = InterfaceLanguageManager(defaults: .standard)

    private let defaultsKey = "VoxFlow_InterfaceLanguage"
    private let appleLanguagesKey = "AppleLanguages"
    private let defaults: UserDefaults
    private var restartRequiredAfterChange = false

    private(set) var currentLanguage: AppLanguage {
        didSet {
            defaults.set(currentLanguage.rawValue, forKey: defaultsKey)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let saved = defaults.string(forKey: defaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            currentLanguage = lang
        } else {
            currentLanguage = .default
            defaults.set(currentLanguage.rawValue, forKey: defaultsKey)
        }
        super.init()
    }

    /// 切换界面语言。写/删 `AppleLanguages` override，调用后需重启 App 生效。
    func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        currentLanguage = language
        restartRequiredAfterChange = true
        if let value = language.appleLanguagesValue {
            defaults.set([value], forKey: appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: appleLanguagesKey)
        }
        defaults.synchronize()
    }

    /// 当前进程生效的界面 locale（`Bundle.main.preferredLocalizations` 首个）。
    var effectiveLocale: String? {
        Bundle.main.preferredLocalizations.first
    }

    /// 切换后是否需要重启才能生效。
    /// 比较已保存的偏好与当前进程 locale：不一致即需要重启。
    var needsRestart: Bool {
        if restartRequiredAfterChange {
            return true
        }
        if let desired = currentLanguage.appleLanguagesValue {
            return effectiveLocale.map { $0 != desired } ?? true
        }
        return false
    }
}
