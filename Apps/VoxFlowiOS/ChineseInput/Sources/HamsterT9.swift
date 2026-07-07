import Foundation

public enum HamsterT9 {
    public static func pinyinCandidates(for digits: String) -> [String] {
        t9ToPinyinMapping[digits] ?? []
    }

    public static func digitSequence(forPinyin pinyin: String) -> String? {
        pinyinToT9Mapping[pinyin]
    }

    public static func replaceSingleDigitPreview(_ preview: String) -> String {
        preview.replaceT9pinyin
    }

    public static func restorePreview(_ preview: String, candidateComment: String) -> String {
        preview.t9pinyinToPinyin(comment: candidateComment)
    }

    public static func completions(startingWith digits: String) -> [String] {
        t9PinyinTrie.collections(startingWith: digits).sorted()
    }
}
