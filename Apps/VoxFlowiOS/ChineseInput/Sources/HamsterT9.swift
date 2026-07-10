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

    /// Ported from Hamster's `RimeContext.getPinyinCandidates()` presentation
    /// logic. The Rime preedit may contain converted pinyin while `rawInput`
    /// still contains the original T9 digits.
    public static func pinyinCandidates(preedit: String, rawInput: String) -> [String] {
        var source = preedit.replacingOccurrences(of: " ", with: "")
        if source.isEmpty {
            source = rawInput
        }

        while let first = source.first, !first.isNumber {
            source.removeFirst()
        }

        var result: [String] = []
        if !source.isEmpty {
            for count in 1...source.count {
                let prefix = String(source.prefix(count))
                result.append(contentsOf: t9ToPinyinMapping[prefix] ?? [])
            }
        } else if let lastSyllable = preedit.split(separator: " ").last {
            var digits = pinyinToT9Mapping[String(lastSyllable)] ?? ""
            while !digits.isEmpty {
                result.append(contentsOf: t9ToPinyinMapping[digits] ?? [])
                digits.removeLast()
            }
        }

        if result.isEmpty, !rawInput.isEmpty {
            result = completions(startingWith: rawInput)
        }
        return Array(Set(result)).sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0 < $1
        }
    }

    public static func replayInput(
        rawInput: String,
        replacingDigits digits: String,
        at start: Int,
        with pinyin: String
    ) -> String? {
        guard start >= 0,
              let lowerBound = rawInput.index(rawInput.startIndex, offsetBy: start, limitedBy: rawInput.endIndex),
              let upperBound = rawInput.index(lowerBound, offsetBy: digits.count, limitedBy: rawInput.endIndex),
              rawInput[lowerBound..<upperBound] == digits[...] else {
            return nil
        }
        var rebuilt = rawInput
        rebuilt.replaceSubrange(lowerBound..<upperBound, with: pinyin)
        return rebuilt
    }
}
