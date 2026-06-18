import Foundation

/// Supported speech recognition languages.
enum RecognitionLanguage: String, CaseIterable {
    case english = "en-US"
    case simplifiedChinese = "zh-CN"
    case traditionalChinese = "zh-TW"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    var displayName: String {
        switch self {
        case .english:             return "English"
        case .simplifiedChinese:   return "简体中文"
        case .traditionalChinese:  return "繁體中文"
        case .japanese:            return "日本語"
        case .korean:              return "한국어"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    static var `default`: RecognitionLanguage { .simplifiedChinese }
    static var allCases: [RecognitionLanguage] {
        [.simplifiedChinese, .traditionalChinese, .english, .japanese, .korean]
    }

    var isSelectable: Bool {
        Self.allCases.contains(self)
    }

    static func supportsIdentifier(_ identifier: String) -> Bool {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        return allCases
            .map { $0.rawValue.lowercased() }
            .contains(normalized)
    }
}

/// Manages language preferences stored in UserDefaults.
@MainActor
final class LanguageManager: NSObject {
    static let shared = LanguageManager(defaults: .standard)

    private let defaultsKey = "VoxFlow_SelectedLanguage"
    private let defaults: UserDefaults
    private var observers: [UUID: (RecognitionLanguage) -> Void] = [:]

    private(set) var currentLanguage: RecognitionLanguage {
        didSet {
            defaults.set(currentLanguage.rawValue, forKey: defaultsKey)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let saved = defaults.string(forKey: defaultsKey),
           let lang = RecognitionLanguage(rawValue: saved),
           lang.isSelectable {
            currentLanguage = lang
        } else {
            currentLanguage = .default
            defaults.set(currentLanguage.rawValue, forKey: defaultsKey)
        }
        super.init()
    }

    func setLanguage(_ language: RecognitionLanguage) {
        guard language.isSelectable, language != currentLanguage else { return }
        currentLanguage = language
        for observer in observers.values {
            observer(language)
        }
    }

    var allLanguages: [RecognitionLanguage] { RecognitionLanguage.allCases }

    @discardableResult
    func observeLanguageChanges(_ observer: @escaping (RecognitionLanguage) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeLanguageObserver(_ id: UUID) {
        observers[id] = nil
    }
}
