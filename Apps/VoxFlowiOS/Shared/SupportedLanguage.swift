// DictusCore/Sources/DictusCore/SupportedLanguage.swift
// Type-safe language representation shared between DictusApp and DictusKeyboard.
import Foundation

/// Languages supported by Dictus for transcription, autocorrect, and predictions.
///
/// WHY an enum instead of raw strings:
/// Language codes were previously scattered as "fr"/"en" string literals across
/// SettingsView, KeyboardViewController, TextPredictionEngine, and TranscriptionService.
/// A single enum prevents typos, centralizes display names and layout defaults,
/// and makes adding new languages a one-place change.
public enum SupportedLanguage: String, CaseIterable, Codable {
    case english = "en"

    /// Localized display name for settings UI.
    public var displayName: String {
        switch self {
        case .english: return "English"
        }
    }

    /// Two-letter uppercase code for the keyboard toolbar language switcher.
    public var shortCode: String { rawValue.uppercased() }

    /// Default keyboard layout for this language.
    /// French defaults to AZERTY; English, Spanish, and German default to QWERTY.
    /// (German QWERTZ is deferred to follow-up issue #151.)
    public var defaultLayout: LayoutType {
        switch self {
        case .english: return .qwerty
        }
    }

    /// Spacebar label matching each language's convention.
    public var spaceName: String {
        switch self {
        case .english: return "space"
        }
    }

    /// Return key label matching each language's convention.
    public var returnName: String {
        switch self {
        case .english: return "return"
        }
    }

    /// Reads the active language from App Group, defaulting to English.
    public static var active: SupportedLanguage {
        guard let raw = AppGroup.preferences.string(forKey: SharedKeys.language),
              let lang = SupportedLanguage(rawValue: raw) else {
            return .english
        }
        return lang
    }

    /// Cycles to the next language in order.
    /// Used by the keyboard toolbar language switcher on tap.
    public func next() -> SupportedLanguage {
        .english
    }
}
