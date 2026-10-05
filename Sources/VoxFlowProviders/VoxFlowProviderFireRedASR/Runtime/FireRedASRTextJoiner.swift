import Foundation

/// 分段解码后把各段文本拼回一句。
///
/// 段是在静音处切开的，所以中文段之间直接相接就是自然结果；但如果两侧都是 ASCII 词字符
/// （英文单词、数字），中间必须补一个空格，否则会出现 `HELLOworld`。
enum FireRedASRTextJoiner {
    static func join(_ parts: [String]) -> String {
        var result = ""
        for part in parts where !isBlank(part) {
            if let last = result.last, let first = part.first, needsSpace(between: last, and: first) {
                result.append(" ")
            }
            result.append(contentsOf: part)
        }
        return result
    }

    /// 只有两侧都是 ASCII 字母或数字时才补空格；涉及 CJK 或标点时不补。
    static func needsSpace(between left: Character, and right: Character) -> Bool {
        isASCIIWordCharacter(left) && isASCIIWordCharacter(right)
    }

    /// 空串与纯空白段都不参与拼接，避免留下孤立的空格。
    private static func isBlank(_ part: String) -> Bool {
        part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isASCIIWordCharacter(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        return (ascii >= 48 && ascii <= 57)      // 0-9
            || (ascii >= 65 && ascii <= 90)      // A-Z
            || (ascii >= 97 && ascii <= 122)     // a-z
    }
}
