import Foundation
import VoxFlowTextProcessing

enum StyleOutputPunctuation: String, Codable, CaseIterable, Sendable, Equatable, Identifiable {
    case complete
    case less
    case preserve

    static let allCases: [StyleOutputPunctuation] = [.preserve, .less, .complete]

    var id: String { rawValue }
}

enum StyleOutputCapitalization: String, Codable, CaseIterable, Sendable, Equatable, Identifiable {
    case normal
    case relaxed
    case preserve

    static let allCases: [StyleOutputCapitalization] = [.preserve, .relaxed, .normal]

    var id: String { rawValue }
}

enum StyleOutputTone: String, Codable, CaseIterable, Sendable, Equatable, Identifiable {
    case restrained
    case natural
    case energetic

    var id: String { rawValue }
}

enum StyleOutputEmoji: String, Codable, CaseIterable, Sendable, Equatable, Identifiable {
    case none
    case natural
    case required

    static let allCases: [StyleOutputEmoji] = [.none, .natural, .required]

    var id: String { rawValue }
}

struct StyleOutputFormat: Codable, Sendable, Equatable {
    private struct PromptExampleOutput: Encodable {
        let polished: String
        let corrections: [String]
        let key_terms: [String]
    }

    var punctuation: StyleOutputPunctuation
    var capitalization: StyleOutputCapitalization
    var tone: StyleOutputTone
    var emoji: StyleOutputEmoji

    private enum CodingKeys: String, CodingKey {
        case punctuation
        case capitalization
        case tone
        case emoji
    }

    init(
        punctuation: StyleOutputPunctuation,
        capitalization: StyleOutputCapitalization,
        tone: StyleOutputTone,
        emoji: StyleOutputEmoji
    ) {
        self.punctuation = punctuation
        self.capitalization = capitalization
        self.tone = tone
        self.emoji = emoji
    }

    var deterministicPolicy: StyleOutputFormatPolicy {
        StyleOutputFormatPolicy(
            punctuation: punctuation.deterministicPolicy,
            capitalization: capitalization.deterministicPolicy
        )
    }

    var promptRules: String {
        """
        # Runtime Polished Text Formatting Rules
        These four output-format controls are user-selected Gold Rules for the `polished` field.
        You MUST obey all four selected values below. They outrank the editable style prompt, examples, app context, previous transcription context, and model habits.
        Only the non-interaction protocol and JSON-output protocol outrank these Gold Rules.

        Option catalog:
        - Punctuation: preserve = keep user punctuation; less = light punctuation; complete = natural full punctuation.
        - Capitalization: preserve = keep casing; relaxed = allow chat/dev lowercase; normal = standard sentence capitalization.
        - Tone: restrained = concise/professional; natural = close to user voice; energetic = warmer/action-oriented.
        - Emoji: none = do not add; natural = allowed but optional; required = add one when not skipped.

        Selected Gold Rules:
        - Punctuation = \(punctuation.rawValue): \(punctuation.promptRule) \(Self.dictatedPunctuationRule)
        - Capitalization = \(capitalization.rawValue): \(capitalization.promptRule)
        - Tone = \(tone.rawValue): \(tone.promptRule)
        - Emoji = \(emoji.rawValue): \(emoji.promptRule)

        Selected combination example:
        The app selected this single example from the current user-configured combination. Follow its pattern.
        \(selectedCombinationExample)

        Final self-check before returning JSON:
        1. Does `polished` obey Punctuation = \(punctuation.rawValue)?
        2. Does `polished` obey Capitalization = \(capitalization.rawValue)?
        3. Does `polished` obey Tone = \(tone.rawValue)?
        4. Does `polished` obey Emoji = \(emoji.rawValue)?
        If any answer is no, revise `polished` before returning JSON.
        """
    }

    private static let dictatedPunctuationRule = """
        Recognize dictated punctuation commands such as colon, period, comma, \
        question mark, exclamation mark, ellipsis, semicolon, quotes, \
        parentheses, and dash; replace the command words with the corresponding \
        symbol only when they are clearly dictated as punctuation.
        """

    private var selectedCombinationExample: String {
        """
        Input: i will check the api response 帮我看一下这里呗。
        JSON:
        \(selectedCombinationExampleJSON)
        Why: \(punctuation.shortExampleReason); \(capitalization.shortExampleReason); \(tone.shortExampleReason); \(emoji.shortExampleReason).
        """
    }

    private var selectedCombinationExampleJSON: String {
        let output = PromptExampleOutput(
            polished: selectedCombinationExampleOutput,
            corrections: [],
            key_terms: []
        )
        let data = try! JSONEncoder().encode(output)
        return String(decoding: data, as: UTF8.self)
    }

    private var selectedCombinationExampleRow: String {
        let selectedCells = "| \(punctuation.rawValue) | \(capitalization.rawValue) | \(tone.rawValue) | \(emoji.rawValue) |"
        return Self.combinationExampleRows
            .split(separator: "\n")
            .map(String.init)
            .first { $0.contains(selectedCells) }
            ?? ""
    }

    private var selectedCombinationExampleOutput: String {
        let columns = selectedCombinationExampleRow
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard columns.count > 6 else { return "" }
        return columns[6]
    }

    private static let combinationExampleRows = """
        | # | Punctuation | Capitalization | Tone | Emoji | Correct polished | Why this is correct |
        |---|---|---|---|---|---|---|
        | 1 | preserve | preserve | restrained | none | i will check the api response, 帮我看一下这里。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=preserve keeps the original lowercase English words. Tone=restrained keeps the wording concise and professional. Emoji=none adds no emoji. |
        | 2 | preserve | preserve | restrained | natural | i will check the api response, 帮我看一下这里。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=preserve keeps the original lowercase English words. Tone=restrained keeps the wording concise and professional. Emoji=natural is allowed, but this example does not need an emoji. |
        | 3 | preserve | preserve | restrained | required | i will check the api response, 帮我看一下这里。 🚀 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=preserve keeps the original lowercase English words. Tone=restrained keeps the wording concise and professional. Emoji=required adds one fitting emoji here. |
        | 4 | preserve | preserve | natural | none | i will check the api response, 帮我看一下这里呗。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=preserve keeps the original lowercase English words. Tone=natural keeps the user's casual particle 呗. Emoji=none adds no emoji. |
        | 5 | preserve | preserve | natural | natural | i will check the api response, 帮我看一下这里呗。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=preserve keeps the original lowercase English words. Tone=natural keeps the user's casual particle 呗. Emoji=natural is allowed, but this example does not need an emoji. |
        | 6 | preserve | preserve | natural | required | i will check the api response, 帮我看一下这里呗。 🚀 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=preserve keeps the original lowercase English words. Tone=natural keeps the user's casual particle 呗. Emoji=required adds one fitting emoji here. |
        | 7 | preserve | preserve | energetic | none | i will check the api response, 帮我看一下这里，我们推进一下。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=preserve keeps the original lowercase English words. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=none adds no emoji. |
        | 8 | preserve | preserve | energetic | natural | i will check the api response, 帮我看一下这里，我们推进一下。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=preserve keeps the original lowercase English words. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=natural is allowed, but this example does not need an emoji. |
        | 9 | preserve | preserve | energetic | required | i will check the api response, 帮我看一下这里，我们推进一下。 🚀 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=preserve keeps the original lowercase English words. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=required adds one fitting emoji here. |
        | 10 | preserve | relaxed | restrained | none | i will check the API response, 帮我看一下这里。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=restrained keeps the wording concise and professional. Emoji=none adds no emoji. |
        | 11 | preserve | relaxed | restrained | natural | i will check the API response, 帮我看一下这里。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=restrained keeps the wording concise and professional. Emoji=natural is allowed, but this example does not need an emoji. |
        | 12 | preserve | relaxed | restrained | required | i will check the API response, 帮我看一下这里。 🚀 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=restrained keeps the wording concise and professional. Emoji=required adds one fitting emoji here. |
        | 13 | preserve | relaxed | natural | none | i will check the API response, 帮我看一下这里呗。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=natural keeps the user's casual particle 呗. Emoji=none adds no emoji. |
        | 14 | preserve | relaxed | natural | natural | i will check the API response, 帮我看一下这里呗。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=natural keeps the user's casual particle 呗. Emoji=natural is allowed, but this example does not need an emoji. |
        | 15 | preserve | relaxed | natural | required | i will check the API response, 帮我看一下这里呗。 🚀 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=natural keeps the user's casual particle 呗. Emoji=required adds one fitting emoji here. |
        | 16 | preserve | relaxed | energetic | none | i will check the API response, 帮我看一下这里，我们推进一下。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=none adds no emoji. |
        | 17 | preserve | relaxed | energetic | natural | i will check the API response, 帮我看一下这里，我们推进一下。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=natural is allowed, but this example does not need an emoji. |
        | 18 | preserve | relaxed | energetic | required | i will check the API response, 帮我看一下这里，我们推进一下。 🚀 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=required adds one fitting emoji here. |
        | 19 | preserve | normal | restrained | none | I will check the API response, 帮我看一下这里。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=restrained keeps the wording concise and professional. Emoji=none adds no emoji. |
        | 20 | preserve | normal | restrained | natural | I will check the API response, 帮我看一下这里。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=restrained keeps the wording concise and professional. Emoji=natural is allowed, but this example does not need an emoji. |
        | 21 | preserve | normal | restrained | required | I will check the API response, 帮我看一下这里。 🚀 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=restrained keeps the wording concise and professional. Emoji=required adds one fitting emoji here. |
        | 22 | preserve | normal | natural | none | I will check the API response, 帮我看一下这里呗。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=natural keeps the user's casual particle 呗. Emoji=none adds no emoji. |
        | 23 | preserve | normal | natural | natural | I will check the API response, 帮我看一下这里呗。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=natural keeps the user's casual particle 呗. Emoji=natural is allowed, but this example does not need an emoji. |
        | 24 | preserve | normal | natural | required | I will check the API response, 帮我看一下这里呗。 🚀 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=natural keeps the user's casual particle 呗. Emoji=required adds one fitting emoji here. |
        | 25 | preserve | normal | energetic | none | I will check the API response, 帮我看一下这里，我们推进一下。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=none adds no emoji. |
        | 26 | preserve | normal | energetic | natural | I will check the API response, 帮我看一下这里，我们推进一下。 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=natural is allowed, but this example does not need an emoji. |
        | 27 | preserve | normal | energetic | required | I will check the API response, 帮我看一下这里，我们推进一下。 🚀 | Punctuation=preserve keeps the explicit Chinese full stop from the input. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=required adds one fitting emoji here. |
        | 28 | less | preserve | restrained | none | i will check the api response, 帮我看一下这里 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=preserve keeps the original lowercase English words. Tone=restrained keeps the wording concise and professional. Emoji=none adds no emoji. |
        | 29 | less | preserve | restrained | natural | i will check the api response, 帮我看一下这里 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=preserve keeps the original lowercase English words. Tone=restrained keeps the wording concise and professional. Emoji=natural is allowed, but this example does not need an emoji. |
        | 30 | less | preserve | restrained | required | i will check the api response, 帮我看一下这里 🚀 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=preserve keeps the original lowercase English words. Tone=restrained keeps the wording concise and professional. Emoji=required adds one fitting emoji here. |
        | 31 | less | preserve | natural | none | i will check the api response, 帮我看一下这里呗 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=preserve keeps the original lowercase English words. Tone=natural keeps the user's casual particle 呗. Emoji=none adds no emoji. |
        | 32 | less | preserve | natural | natural | i will check the api response, 帮我看一下这里呗 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=preserve keeps the original lowercase English words. Tone=natural keeps the user's casual particle 呗. Emoji=natural is allowed, but this example does not need an emoji. |
        | 33 | less | preserve | natural | required | i will check the api response, 帮我看一下这里呗 🚀 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=preserve keeps the original lowercase English words. Tone=natural keeps the user's casual particle 呗. Emoji=required adds one fitting emoji here. |
        | 34 | less | preserve | energetic | none | i will check the api response, 帮我看一下这里，我们推进一下 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=preserve keeps the original lowercase English words. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=none adds no emoji. |
        | 35 | less | preserve | energetic | natural | i will check the api response, 帮我看一下这里，我们推进一下 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=preserve keeps the original lowercase English words. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=natural is allowed, but this example does not need an emoji. |
        | 36 | less | preserve | energetic | required | i will check the api response, 帮我看一下这里，我们推进一下 🚀 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=preserve keeps the original lowercase English words. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=required adds one fitting emoji here. |
        | 37 | less | relaxed | restrained | none | i will check the API response, 帮我看一下这里 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=restrained keeps the wording concise and professional. Emoji=none adds no emoji. |
        | 38 | less | relaxed | restrained | natural | i will check the API response, 帮我看一下这里 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=restrained keeps the wording concise and professional. Emoji=natural is allowed, but this example does not need an emoji. |
        | 39 | less | relaxed | restrained | required | i will check the API response, 帮我看一下这里 🚀 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=restrained keeps the wording concise and professional. Emoji=required adds one fitting emoji here. |
        | 40 | less | relaxed | natural | none | i will check the API response, 帮我看一下这里呗 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=natural keeps the user's casual particle 呗. Emoji=none adds no emoji. |
        | 41 | less | relaxed | natural | natural | i will check the API response, 帮我看一下这里呗 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=natural keeps the user's casual particle 呗. Emoji=natural is allowed, but this example does not need an emoji. |
        | 42 | less | relaxed | natural | required | i will check the API response, 帮我看一下这里呗 🚀 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=natural keeps the user's casual particle 呗. Emoji=required adds one fitting emoji here. |
        | 43 | less | relaxed | energetic | none | i will check the API response, 帮我看一下这里，我们推进一下 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=none adds no emoji. |
        | 44 | less | relaxed | energetic | natural | i will check the API response, 帮我看一下这里，我们推进一下 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=natural is allowed, but this example does not need an emoji. |
        | 45 | less | relaxed | energetic | required | i will check the API response, 帮我看一下这里，我们推进一下 🚀 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=required adds one fitting emoji here. |
        | 46 | less | normal | restrained | none | I will check the API response, 帮我看一下这里 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=restrained keeps the wording concise and professional. Emoji=none adds no emoji. |
        | 47 | less | normal | restrained | natural | I will check the API response, 帮我看一下这里 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=restrained keeps the wording concise and professional. Emoji=natural is allowed, but this example does not need an emoji. |
        | 48 | less | normal | restrained | required | I will check the API response, 帮我看一下这里 🚀 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=restrained keeps the wording concise and professional. Emoji=required adds one fitting emoji here. |
        | 49 | less | normal | natural | none | I will check the API response, 帮我看一下这里呗 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=natural keeps the user's casual particle 呗. Emoji=none adds no emoji. |
        | 50 | less | normal | natural | natural | I will check the API response, 帮我看一下这里呗 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=natural keeps the user's casual particle 呗. Emoji=natural is allowed, but this example does not need an emoji. |
        | 51 | less | normal | natural | required | I will check the API response, 帮我看一下这里呗 🚀 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=natural keeps the user's casual particle 呗. Emoji=required adds one fitting emoji here. |
        | 52 | less | normal | energetic | none | I will check the API response, 帮我看一下这里，我们推进一下 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=none adds no emoji. |
        | 53 | less | normal | energetic | natural | I will check the API response, 帮我看一下这里，我们推进一下 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=natural is allowed, but this example does not need an emoji. |
        | 54 | less | normal | energetic | required | I will check the API response, 帮我看一下这里，我们推进一下 🚀 | Punctuation=less removes the ordinary ending full stop for this short chat-like sentence. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=required adds one fitting emoji here. |
        | 55 | complete | preserve | restrained | none | i will check the api response, 帮我看一下这里。 | Punctuation=complete adds a natural ending full stop. Capitalization=preserve keeps the original lowercase English words. Tone=restrained keeps the wording concise and professional. Emoji=none adds no emoji. |
        | 56 | complete | preserve | restrained | natural | i will check the api response, 帮我看一下这里。 | Punctuation=complete adds a natural ending full stop. Capitalization=preserve keeps the original lowercase English words. Tone=restrained keeps the wording concise and professional. Emoji=natural is allowed, but this example does not need an emoji. |
        | 57 | complete | preserve | restrained | required | i will check the api response, 帮我看一下这里。 🚀 | Punctuation=complete adds a natural ending full stop. Capitalization=preserve keeps the original lowercase English words. Tone=restrained keeps the wording concise and professional. Emoji=required adds one fitting emoji here. |
        | 58 | complete | preserve | natural | none | i will check the api response, 帮我看一下这里呗。 | Punctuation=complete adds a natural ending full stop. Capitalization=preserve keeps the original lowercase English words. Tone=natural keeps the user's casual particle 呗. Emoji=none adds no emoji. |
        | 59 | complete | preserve | natural | natural | i will check the api response, 帮我看一下这里呗。 | Punctuation=complete adds a natural ending full stop. Capitalization=preserve keeps the original lowercase English words. Tone=natural keeps the user's casual particle 呗. Emoji=natural is allowed, but this example does not need an emoji. |
        | 60 | complete | preserve | natural | required | i will check the api response, 帮我看一下这里呗。 🚀 | Punctuation=complete adds a natural ending full stop. Capitalization=preserve keeps the original lowercase English words. Tone=natural keeps the user's casual particle 呗. Emoji=required adds one fitting emoji here. |
        | 61 | complete | preserve | energetic | none | i will check the api response, 帮我看一下这里，我们推进一下。 | Punctuation=complete adds a natural ending full stop. Capitalization=preserve keeps the original lowercase English words. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=none adds no emoji. |
        | 62 | complete | preserve | energetic | natural | i will check the api response, 帮我看一下这里，我们推进一下。 | Punctuation=complete adds a natural ending full stop. Capitalization=preserve keeps the original lowercase English words. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=natural is allowed, but this example does not need an emoji. |
        | 63 | complete | preserve | energetic | required | i will check the api response, 帮我看一下这里，我们推进一下。 🚀 | Punctuation=complete adds a natural ending full stop. Capitalization=preserve keeps the original lowercase English words. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=required adds one fitting emoji here. |
        | 64 | complete | relaxed | restrained | none | i will check the API response, 帮我看一下这里。 | Punctuation=complete adds a natural ending full stop. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=restrained keeps the wording concise and professional. Emoji=none adds no emoji. |
        | 65 | complete | relaxed | restrained | natural | i will check the API response, 帮我看一下这里。 | Punctuation=complete adds a natural ending full stop. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=restrained keeps the wording concise and professional. Emoji=natural is allowed, but this example does not need an emoji. |
        | 66 | complete | relaxed | restrained | required | i will check the API response, 帮我看一下这里。 🚀 | Punctuation=complete adds a natural ending full stop. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=restrained keeps the wording concise and professional. Emoji=required adds one fitting emoji here. |
        | 67 | complete | relaxed | natural | none | i will check the API response, 帮我看一下这里呗。 | Punctuation=complete adds a natural ending full stop. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=natural keeps the user's casual particle 呗. Emoji=none adds no emoji. |
        | 68 | complete | relaxed | natural | natural | i will check the API response, 帮我看一下这里呗。 | Punctuation=complete adds a natural ending full stop. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=natural keeps the user's casual particle 呗. Emoji=natural is allowed, but this example does not need an emoji. |
        | 69 | complete | relaxed | natural | required | i will check the API response, 帮我看一下这里呗。 🚀 | Punctuation=complete adds a natural ending full stop. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=natural keeps the user's casual particle 呗. Emoji=required adds one fitting emoji here. |
        | 70 | complete | relaxed | energetic | none | i will check the API response, 帮我看一下这里，我们推进一下。 | Punctuation=complete adds a natural ending full stop. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=none adds no emoji. |
        | 71 | complete | relaxed | energetic | natural | i will check the API response, 帮我看一下这里，我们推进一下。 | Punctuation=complete adds a natural ending full stop. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=natural is allowed, but this example does not need an emoji. |
        | 72 | complete | relaxed | energetic | required | i will check the API response, 帮我看一下这里，我们推进一下。 🚀 | Punctuation=complete adds a natural ending full stop. Capitalization=relaxed allows chat-like lowercase i while normalizing the common technical term API. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=required adds one fitting emoji here. |
        | 73 | complete | normal | restrained | none | I will check the API response, 帮我看一下这里。 | Punctuation=complete adds a natural ending full stop. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=restrained keeps the wording concise and professional. Emoji=none adds no emoji. |
        | 74 | complete | normal | restrained | natural | I will check the API response, 帮我看一下这里。 | Punctuation=complete adds a natural ending full stop. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=restrained keeps the wording concise and professional. Emoji=natural is allowed, but this example does not need an emoji. |
        | 75 | complete | normal | restrained | required | I will check the API response, 帮我看一下这里。 🚀 | Punctuation=complete adds a natural ending full stop. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=restrained keeps the wording concise and professional. Emoji=required adds one fitting emoji here. |
        | 76 | complete | normal | natural | none | I will check the API response, 帮我看一下这里呗。 | Punctuation=complete adds a natural ending full stop. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=natural keeps the user's casual particle 呗. Emoji=none adds no emoji. |
        | 77 | complete | normal | natural | natural | I will check the API response, 帮我看一下这里呗。 | Punctuation=complete adds a natural ending full stop. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=natural keeps the user's casual particle 呗. Emoji=natural is allowed, but this example does not need an emoji. |
        | 78 | complete | normal | natural | required | I will check the API response, 帮我看一下这里呗。 🚀 | Punctuation=complete adds a natural ending full stop. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=natural keeps the user's casual particle 呗. Emoji=required adds one fitting emoji here. |
        | 79 | complete | normal | energetic | none | I will check the API response, 帮我看一下这里，我们推进一下。 | Punctuation=complete adds a natural ending full stop. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=none adds no emoji. |
        | 80 | complete | normal | energetic | natural | I will check the API response, 帮我看一下这里，我们推进一下。 | Punctuation=complete adds a natural ending full stop. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=natural is allowed, but this example does not need an emoji. |
        | 81 | complete | normal | energetic | required | I will check the API response, 帮我看一下这里，我们推进一下。 🚀 | Punctuation=complete adds a natural ending full stop. Capitalization=normal uses sentence-style English capitalization and keeps API uppercase. Tone=energetic makes the line warmer and more action-oriented without adding facts. Emoji=required adds one fitting emoji here. |
        """

    static let systemDefault = StyleOutputFormat(
        punctuation: .complete,
        capitalization: .normal,
        tone: .natural,
        emoji: .none
    )

    static func builtInDefault(for profileID: String) -> StyleOutputFormat? {
        switch profileID {
        case "builtin.energetic":
            return StyleOutputFormat(
                punctuation: .less,
                capitalization: .normal,
                tone: .energetic,
                emoji: .required
            )
        case "builtin.original":
            return StyleOutputFormat(
                punctuation: .preserve,
                capitalization: .preserve,
                tone: .natural,
                emoji: .none
            )
        case "builtin.casual":
            return StyleOutputFormat(
                punctuation: .less,
                capitalization: .relaxed,
                tone: .natural,
                emoji: .none
            )
        case "builtin.formal":
            return StyleOutputFormat(
                punctuation: .complete,
                capitalization: .normal,
                tone: .restrained,
                emoji: .none
            )
        case "builtin.coding":
            return StyleOutputFormat(
                punctuation: .preserve,
                capitalization: .preserve,
                tone: .natural,
                emoji: .none
            )
        case "builtin.chat":
            return StyleOutputFormat(
                punctuation: .less,
                capitalization: .relaxed,
                tone: .natural,
                emoji: .natural
            )
        case "builtin.email":
            return StyleOutputFormat(
                punctuation: .complete,
                capitalization: .normal,
                tone: .natural,
                emoji: .none
            )
        default:
            return nil
        }
    }
}

extension StyleOutputPunctuation {
    var deterministicPolicy: StylePunctuationPolicy? {
        switch self {
        case .complete:
            return .complete
        case .less:
            return .noEnding
        case .preserve:
            return .preserve
        }
    }

    var promptRule: String {
        switch self {
        case .complete:
            return "use complete, natural punctuation where appropriate; add missing sentence punctuation when it improves readability."
        case .less:
            return "use light punctuation; avoid over-punctuating short casual text; do not auto-add ordinary ending full stops to short chat-like messages; keep explicit question marks, exclamation marks, ellipses, URLs, paths, versions, and code symbols."
        case .preserve:
            return "preserve the user's punctuation as much as possible; only fix clear ASR punctuation commands or obvious recognition errors."
        }
    }

    var shortExampleReason: String {
        switch self {
        case .complete:
            return "complete adds a natural ending mark"
        case .less:
            return "less avoids an ordinary final full stop"
        case .preserve:
            return "preserve keeps dictated punctuation"
        }
    }

}

extension StyleOutputCapitalization {
    var deterministicPolicy: StyleCapitalizationPolicy? {
        switch self {
        case .normal:
            return .normal
        case .relaxed:
            return .relaxed
        case .preserve:
            return .preserve
        }
    }

    var promptRule: String {
        switch self {
        case .normal:
            return "use normal capitalization for natural-language English sentences."
        case .relaxed:
            return "do not force capitalization in terminal, code editor, or chat-like short fragments; preserve code identifiers and user casing."
        case .preserve:
            return "preserve original casing for URLs, commands, paths, identifiers, versions, and user-typed fragments."
        }
    }

    var shortExampleReason: String {
        switch self {
        case .normal:
            return "normal uses sentence casing and API"
        case .relaxed:
            return "relaxed allows chat-like lowercase while keeping API"
        case .preserve:
            return "preserve keeps original lowercase"
        }
    }

}

extension StyleOutputTone {
    var promptRule: String {
        switch self {
        case .restrained:
            return "keep tone calm, concise, and professional."
        case .natural:
            return "keep tone natural and close to the user's original voice."
        case .energetic:
            return "allow a warmer, more energetic tone without adding facts, promises, or exaggerated claims."
        }
    }

    var shortExampleReason: String {
        switch self {
        case .restrained:
            return "restrained stays concise"
        case .natural:
            return "natural keeps the user's voice"
        case .energetic:
            return "energetic is warmer without new facts"
        }
    }

}

extension StyleOutputEmoji {
    var promptRule: String {
        switch self {
        case .none:
            return "do not add emoji unless the user explicitly dictated one."
        case .natural:
            return "emoji is optional; add at most one natural emoji only when it clearly fits the message; it must not add facts, promises, or evaluations, and must not change meaning or amplify emotional intensity."
        case .required:
            return "add 1 fitting emoji to ordinary social, chat, status update, or motivational text. Use up to 2 only when the message is clearly playful. Do not repeat or stack emoji. Skip only for code, commands, URLs/paths-only text, legal/medical/financial-sensitive text, or when the user explicitly says no emoji. The emoji must not add facts, promises, or evaluations, and must not change meaning or amplify emotional intensity."
        }
    }

    var shortExampleReason: String {
        switch self {
        case .none:
            return "none adds no emoji"
        case .natural:
            return "natural is optional; no emoji needed here"
        case .required:
            return "required adds one fitting emoji"
        }
    }

}
