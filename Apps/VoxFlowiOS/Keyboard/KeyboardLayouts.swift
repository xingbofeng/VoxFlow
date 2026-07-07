// DictusKeyboard/KeyboardLayouts.swift
// AZERTY and QWERTY layout definitions in giellakbd-ios KeyboardDefinition format.
// Supports French, English, and Spanish with language-aware labels.

import UIKit
import Shared
import ChineseInput

extension Notification.Name {
    static let mashangxieReloadKeyboardLayout = Notification.Name("mashangxieReloadKeyboardLayout")
}

enum ChineseKeyboardModeStore {
    private static let key = "Mashangxie.keyboard.chineseInputMode"

    static var active: ChineseInputMode {
        get {
            let raw = AppGroup.preferences.string(forKey: key) ?? ChineseInputMode.chineseQwerty.rawValue
            return ChineseInputMode(rawValue: raw) ?? .chineseQwerty
        }
        set {
            AppGroup.preferences.set(newValue.rawValue, forKey: key)
            AppGroup.preferences.synchronize()
        }
    }
}

/// Constructs KeyboardDefinition objects for all supported layouts.
///
/// These layouts are built programmatically (not from JSON) using the same KeyDefinition
/// types as the vendored giellakbd-ios codebase. Each layout includes 5 pages:
/// normal, shifted, capslock (same visual as shifted), symbols1 (numbers), symbols2 (symbols).
///
/// Bottom row on letter pages: [123] [emoji] [space] [return] -- emoji key added in Phase 20.
/// Globe key is provided by iOS below third-party keyboards -- not part of our layout.
enum KeyboardLayouts {

    // MARK: - Public API

    /// AZERTY layout (default for French).
    static func azerty(lang: SupportedLanguage = .active) -> KeyboardDefinition {
        return KeyboardDefinition(
            name: lang.displayName,
            locale: lang.rawValue,
            spaceName: lang.spaceName,
            returnName: lang.returnName,
            longPress: longPressData,
            layout: KeyboardDefinition.Layout(
                normal: azertyNormal(lang: lang),
                shifted: azertyShifted(lang: lang),
                symbols1: numbersPage(lang: lang),
                symbols2: symbolsPage(lang: lang)
            )
        )
    }

    /// QWERTY layout (default for English and Spanish).
    static func qwerty(lang: SupportedLanguage = .active) -> KeyboardDefinition {
        return KeyboardDefinition(
            name: lang.displayName,
            locale: lang.rawValue,
            spaceName: lang.spaceName,
            returnName: lang.returnName,
            longPress: longPressData,
            layout: KeyboardDefinition.Layout(
                normal: qwertyNormal(lang: lang),
                shifted: qwertyShifted(lang: lang),
                symbols1: numbersPage(lang: lang),
                symbols2: symbolsPage(lang: lang)
            )
        )
    }

    /// Returns the layout matching the user's App Group preferences.
    static func current() -> KeyboardDefinition {
        switch ChineseKeyboardModeStore.active {
        case .chineseQwerty:
            return chineseQwerty()
        case .chineseNineGrid:
            return chineseNineGrid()
        case .english:
            return englishQwerty()
        case .symbols, .voice:
            break
        }

        return qwerty(lang: .english)
    }

    static func chineseQwerty() -> KeyboardDefinition {
        let normal = qwertyNormal(lang: .english)
        let shifted = qwertyShifted(lang: .english)
        return KeyboardDefinition(
            name: "中文拼音",
            locale: "zh-Hans",
            spaceName: "空格",
            returnName: "换行",
            longPress: longPressData,
            layout: KeyboardDefinition.Layout(
                normal: replacingBottomRow(in: normal, with: chineseLettersBottomRow()),
                shifted: replacingBottomRow(in: shifted, with: chineseLettersBottomRow()),
                symbols1: numbersPage(lang: .english),
                symbols2: symbolsPage(lang: .english)
            )
        )
    }

    static func englishQwerty() -> KeyboardDefinition {
        let normal = qwertyNormal(lang: .english)
        let shifted = qwertyShifted(lang: .english)
        return KeyboardDefinition(
            name: SupportedLanguage.english.displayName,
            locale: SupportedLanguage.english.rawValue,
            spaceName: SupportedLanguage.english.spaceName,
            returnName: SupportedLanguage.english.returnName,
            longPress: longPressData,
            layout: KeyboardDefinition.Layout(
                normal: replacingBottomRow(in: normal, with: lettersBottomRow(lang: .english)),
                shifted: replacingBottomRow(in: shifted, with: lettersBottomRow(lang: .english)),
                symbols1: numbersPage(lang: .english),
                symbols2: symbolsPage(lang: .english)
            )
        )
    }

    static func chineseNineGrid() -> KeyboardDefinition {
        let rows = ChineseNineGridLayout.rows.map { row in
            row.map { key in
                keyDefinition(for: key)
            }
        }
        return KeyboardDefinition(
            name: "中文九键",
            locale: "zh-Hans",
            spaceName: "空格",
            returnName: "换行",
            longPress: [:],
            layout: KeyboardDefinition.Layout(
                normal: rows,
                shifted: rows,
                symbols1: numbersPage(lang: .english),
                symbols2: symbolsPage(lang: .english)
            )
        )
    }

    // MARK: - AZERTY Letter Pages

    private static func azertyNormal(lang: SupportedLanguage) -> [[KeyDefinition]] {
        [
            // Row 1: 10 keys
            inputRow("a", "z", "e", "r", "t", "y", "u", "i", "o", "p"),
            // Row 2: 10 keys
            inputRow("q", "s", "d", "f", "g", "h", "j", "k", "l", "m"),
            // Row 3: shift + 6 letters + accent key + delete = 9 items (10 units)
            [
                KeyDefinition(type: .shift, size: CGSize(width: 1.5, height: 1)),
                key("w"), key("x"), key("c"), key("v"), key("b"), key("n"),
                KeyDefinition(type: .input(key: "'", alternate: "accent")),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1)),
            ],
            // Row 4: 123 + emoji + space + return
            lettersBottomRow(lang: lang),
        ]
    }

    private static func azertyShifted(lang: SupportedLanguage) -> [[KeyDefinition]] {
        [
            // Row 1: uppercase
            inputRow("A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"),
            // Row 2: uppercase
            inputRow("Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"),
            // Row 3: shift (filled state handled by KeyView) + uppercase letters + accent key + delete
            [
                KeyDefinition(type: .shift, size: CGSize(width: 1.5, height: 1)),
                key("W"), key("X"), key("C"), key("V"), key("B"), key("N"),
                KeyDefinition(type: .input(key: "'", alternate: "accent")),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1)),
            ],
            // Row 4: same as normal
            lettersBottomRow(lang: lang),
        ]
    }

    // MARK: - QWERTY Letter Pages

    private static func qwertyNormal(lang: SupportedLanguage) -> [[KeyDefinition]] {
        [
            // Row 1: 10 keys = 10 units
            inputRow("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
            // Row 2: 9 keys with side spacers = 10 units (matches Apple QWERTY centering)
            [
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
                key("a"), key("s"), key("d"), key("f"), key("g"), key("h"), key("j"), key("k"), key("l"),
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
            ],
            // Row 3: shift + 7 letters + delete = 10 units
            [
                KeyDefinition(type: .shift, size: CGSize(width: 1.5, height: 1)),
                key("z"), key("x"), key("c"), key("v"), key("b"), key("n"), key("m"),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1)),
            ],
            // Row 4: 123 + space + return
            lettersBottomRow(lang: lang),
        ]
    }

    private static func qwertyShifted(lang: SupportedLanguage) -> [[KeyDefinition]] {
        [
            inputRow("Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"),
            [
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
                key("A"), key("S"), key("D"), key("F"), key("G"), key("H"), key("J"), key("K"), key("L"),
                KeyDefinition(type: .spacer, size: CGSize(width: 0.5, height: 1)),
            ],
            [
                KeyDefinition(type: .shift, size: CGSize(width: 1.5, height: 1)),
                key("Z"), key("X"), key("C"), key("V"), key("B"), key("N"), key("M"),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1)),
            ],
            lettersBottomRow(lang: lang),
        ]
    }

    // MARK: - Numbers Page (symbols1)

    private static func numbersPage(lang: SupportedLanguage) -> [[KeyDefinition]] {
        [
            // Row 1: digits
            inputRow("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
            // Row 2: common punctuation and symbols
            inputRow("-", "/", ":", ";", "(", ")", "\u{20AC}", "&", "@", "\""),
            // Row 3: #+= toggle + punctuation + delete
            [
                KeyDefinition(type: .shiftSymbols, size: CGSize(width: 1.5, height: 1)),
                key("."), key(","), key("?"), key("!"), key("'"),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1)),
            ],
            // Row 4: ABC + space + return
            symbolsBottomRow(lang: lang),
        ]
    }

    // MARK: - Symbols Page (symbols2)

    private static func symbolsPage(lang: SupportedLanguage) -> [[KeyDefinition]] {
        [
            // Row 1: brackets and math
            inputRow("[", "]", "{", "}", "#", "%", "^", "*", "+", "="),
            // Row 2: special characters
            inputRow("_", "\\", "|", "~", "<", ">", "$", "\u{00A3}", "\u{00A5}", "\u{00B7}"),
            // Row 3: 123 toggle + punctuation + delete
            [
                KeyDefinition(type: .shiftSymbols, size: CGSize(width: 1.5, height: 1)),
                key("."), key(","), key("?"), key("!"), key("'"),
                KeyDefinition(type: .backspace, size: CGSize(width: 1.5, height: 1)),
            ],
            // Row 4: ABC + space + return
            symbolsBottomRow(lang: lang),
        ]
    }

    // MARK: - Bottom Rows

    /// Letters page bottom row: [123 2.0w] [emoji 1.5w] [space 4.5w] [return 2.0w]
    /// Labels adapt to the active language (e.g., "espace" / "space" / "espacio").
    private static func lettersBottomRow(lang: SupportedLanguage) -> [KeyDefinition] {
        [
            KeyDefinition(type: .symbols, size: CGSize(width: 2.0, height: 1)),
            KeyDefinition(type: .input(key: "\u{1F600}", alternate: nil), size: CGSize(width: 1.5, height: 1)),
            KeyDefinition(type: .spacebar(name: lang.spaceName), size: CGSize(width: 4.5, height: 1)),
            KeyDefinition(type: .returnkey(name: lang.returnName), size: CGSize(width: 2.0, height: 1)),
        ]
    }

    /// Symbols page bottom row: [ABC 2.5w] [space 5.0w] [return 2.5w]
    private static func symbolsBottomRow(lang: SupportedLanguage) -> [KeyDefinition] {
        [
            KeyDefinition(type: .symbols, size: CGSize(width: 2.5, height: 1)),
            KeyDefinition(type: .spacebar(name: lang.spaceName), size: CGSize(width: 5.0, height: 1)),
            KeyDefinition(type: .returnkey(name: lang.returnName), size: CGSize(width: 2.5, height: 1)),
        ]
    }

    private static func chineseLettersBottomRow() -> [KeyDefinition] {
        [
            KeyDefinition(type: .input(key: "123", alternate: "openChineseNumbers"), size: CGSize(width: 2.0, height: 1)),
            KeyDefinition(type: .input(key: "\u{1F600}", alternate: nil), size: CGSize(width: 1.5, height: 1)),
            KeyDefinition(type: .spacebar(name: "空格"), size: CGSize(width: 4.5, height: 1)),
            KeyDefinition(type: .returnkey(name: "换行"), size: CGSize(width: 2.0, height: 1)),
        ]
    }

    // MARK: - Long Press Accents

    /// Long-press accent data shared across all languages.
    /// Includes French accents (grave, circumflex, diaeresis) and Spanish accents (acute).
    private static let longPressData: [String: [String]] = {
        var longPress: [String: [String]] = [:]
        for (baseKey, accents) in AccentedCharacters.mappings {
            longPress[baseKey] = accents
        }
        return longPress
    }()

    // MARK: - Helper Functions

    /// Create a standard 1x1 input key.
    private static func key(_ char: String) -> KeyDefinition {
        KeyDefinition(type: .input(key: char, alternate: nil))
    }

    /// Create a row of standard input keys from variadic strings.
    private static func inputRow(_ keys: String...) -> [KeyDefinition] {
        keys.map { KeyDefinition(type: .input(key: $0, alternate: nil)) }
    }

    private static func replacingBottomRow(in rows: [[KeyDefinition]], with bottomRow: [KeyDefinition]) -> [[KeyDefinition]] {
        var copy = rows
        if copy.indices.contains(3) {
            copy[3] = bottomRow
        }
        return copy
    }

    private static func keyDefinition(for key: ChineseNineGridKey) -> KeyDefinition {
        switch key {
        case let .input(label, digit):
            return KeyDefinition(type: .input(key: label, alternate: digit.map { "chineseNineGridDigit:\($0)" }))
        case .backspace:
            return KeyDefinition(type: .backspace)
        case .clearComposition:
            return KeyDefinition(type: .input(key: "清空", alternate: "clearChineseComposition"))
        case .returnKey:
            return KeyDefinition(type: .returnkey(name: "换行"))
        case .symbols:
            return KeyDefinition(type: .input(key: "符号", alternate: "openChineseSymbols"))
        case .numbers:
            return KeyDefinition(type: .input(key: "123", alternate: "openChineseNumbers"))
        case .space:
            return KeyDefinition(type: .spacebar(name: "空格"))
        case .emoji:
            return KeyDefinition(type: .input(key: "\u{1F600}", alternate: nil))
        case .switchLanguage:
            return KeyDefinition(type: .input(key: "中/英", alternate: "switchEnglish"))
        case .send:
            return KeyDefinition(type: .returnkey(name: "发送"))
        }
    }
}
