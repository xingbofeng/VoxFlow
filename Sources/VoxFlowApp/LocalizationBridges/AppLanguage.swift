import Foundation

/// App 界面显示语言偏好。
///
/// 与语音识别语言（`RecognitionLanguage`）完全独立：
/// - `AppLanguage` 控制 App 界面文案显示用哪种语言（zh-Hans / zh-Hant / en / ja / ko），影响 `Bundle.main` 的 locale。
/// - `RecognitionLanguage` 控制语音识别引擎接收的 BCP 47 标签（en-US / zh-CN …）。
///
/// 切换通过 `InterfaceLanguageManager` 写 `AppleLanguages` override 实现，需重启 App 生效。
enum AppLanguage: String, CaseIterable {
    /// 跟随系统 locale（默认）。
    case followSystem
    /// 简体中文。
    case zhHans = "zh-Hans"
    /// 繁体中文。
    case zhHant = "zh-Hant"
    /// 英文。
    case en
    /// 日语。
    case ja
    /// 韩语。
    case ko

    static var `default`: AppLanguage { .followSystem }

    /// 用于写入 `AppleLanguages` override 的 locale 标识。
    /// `followSystem` 返回 nil（表示清除 override，回归系统 locale）。
    var appleLanguagesValue: String? {
        switch self {
        case .followSystem: return nil
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        case .en: return "en"
        case .ja: return "ja"
        case .ko: return "ko"
        }
    }

    /// 设置项显示名。
    /// `followSystem` 是 UI 文案需本地化；各语言自称不本地化。
    var displayName: String {
        switch self {
        case .followSystem:
            return L10n.localize("settings.interface_language.follow_system", comment: "界面语言选项：跟随系统")
        case .zhHans:
            return "简体中文"
        case .en:
            return "English"
        case .zhHant:
            return "繁體中文"
        case .ja:
            return "日本語"
        case .ko:
            return "한국어"
        }
    }
}
