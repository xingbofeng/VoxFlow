import Foundation

/// Native Swift port of the official `vinta/pangu.js` shared spacing rules.
///
/// The rule order and regular-expression groups intentionally mirror Pangu's
/// `src/shared/index.ts`, while keeping the implementation local and offline.
enum PanguSpacingNormalizer {
    private static let cjk = "\u{2e80}-\u{2eff}\u{2f00}-\u{2fdf}\u{3040}-\u{309f}\u{30a0}-\u{30fa}\u{30fc}-\u{30ff}\u{3100}-\u{312f}\u{3200}-\u{32ff}\u{3400}-\u{4dbf}\u{4e00}-\u{9fff}\u{f900}-\u{faff}"
    private static let an = "A-Za-z0-9"
    private static let a = "A-Za-z"
    private static let upperAN = "A-Z0-9"
    private static let operatorsBase = #"\+\*=&"#
    private static let operatorsWithHyphen = #"\+\*=&\-"#
    private static let operatorsNoHyphen = #"\+\*=&"#
    private static let gradeOperators = #"\+\-\*"#
    private static let quotes = "`\"\u{05f4}"
    private static let leftBracketsBasic = #"\(\[\{"#
    private static let rightBracketsBasic = #"\)\]\}"#
    private static let leftBracketsExtended = #"\(\[\{<>“"#
    private static let rightBracketsExtended = #"\)\]\}<>”"#
    private static let ansCJKAfter = "A-Za-z\u{0370}-\u{03ff}0-9@\\$%\\^&\\*\\-\\+\\\\=\u{00a1}-\u{00ff}\u{2150}-\u{218f}\u{2700}-\u{27bf}"
    private static let ansBeforeCJK = "A-Za-z\u{0370}-\u{03ff}0-9\\$%\\^&\\*\\-\\+\\\\=\u{00a1}-\u{00ff}\u{2150}-\u{218f}\u{2700}-\u{27bf}"
    private static let filePathDirs = #"home|root|usr|etc|var|opt|tmp|dev|mnt|proc|sys|bin|boot|lib|media|run|sbin|srv|node_modules|path|project|src|dist|test|tests|docs|templates|assets|public|static|config|scripts|tools|build|out|target|your|\.claude|\.git|\.vscode"#
    private static let filePathChars = #"[A-Za-z0-9_\-\.@\+\*]+"#
    private static let unixAbsoluteFilePath = #"/(?:\.?(?:"# + filePathDirs + #")|\.(?:[A-Za-z0-9_\-]+))(?:/"# + filePathChars + #")*"#
    private static let unixRelativeFilePath = #"(?:(?:\./)?(?:"# + filePathDirs + #")(?:/"# + filePathChars + #")+)"#
    private static let windowsFilePath = #"[A-Z]:\\(?:[A-Za-z0-9_\-\. ]+\\?)+"#

    static func process(_ text: String) -> String {
        guard text.count > 1, matches(text, pattern: "[\(cjk)]") else { return text }

        var result = text

        let backtickManager = PlaceholderReplacer(placeholder: "BACKTICK_CONTENT_", startDelimiter: "\u{E004}", endDelimiter: "\u{E005}")
        result = replace(result, pattern: #"`([^`]+)`"#) { groups in
            "`\(backtickManager.store(groups[1] ?? ""))`"
        }

        let htmlTagManager = PlaceholderReplacer(placeholder: "HTML_TAG_PLACEHOLDER_", startDelimiter: "\u{E000}", endDelimiter: "\u{E001}")
        var hasHTMLTags = false
        if result.contains("<") {
            hasHTMLTags = true
            result = replace(result, pattern: #"</?[a-zA-Z][a-zA-Z0-9]*(?:\s+[^>]*)?>"#) { groups in
                let tag = groups[0] ?? ""
                let processedTag = replace(tag, pattern: #"(\w+)="([^"]*)""#) { attrGroups in
                    let name = attrGroups[1] ?? ""
                    let value = attrGroups[2] ?? ""
                    return #"\#(name)="\#(process(value))""#
                }
                return htmlTagManager.store(processedTag)
            }
        }

        result = replace(result, pattern: #"([\.]{2,}|…)([\#(cjk)])"#, template: "$1 $2")
        result = replace(result, pattern: #"([\#(cjk)])([!;,\?:]+)(?=[\#(cjk)\#(an)])"#, template: "$1$2 ")
        result = replace(result, pattern: #"([\#(an)])([!;,\?]+)([\#(cjk)])"#, template: "$1$2 $3")
        result = replace(result, pattern: #"([\#(cjk)])(~+)(?!=)(?=[\#(cjk)\#(an)])"#, template: "$1$2 ")
        result = replace(result, pattern: #"([\#(cjk)])(~=)"#, template: "$1 $2 ")
        result = replace(result, pattern: #"([\#(cjk)])(\.)(?![\#(an)\./])(?=[\#(cjk)\#(an)])"#, template: "$1$2 ")
        result = replace(result, pattern: #"([\#(an)])(\.)([\#(cjk)])"#, template: "$1$2 $3")
        result = replace(result, pattern: #"([\#(an)])(:)([\#(cjk)])"#, template: "$1$2 $3")
        result = replace(result, pattern: #"([\#(cjk)])\:([\#(upperAN)\(\)])"#, template: "$1：$2")

        result = replace(result, pattern: #"([\#(cjk)])([\#(quotes)])"#, template: "$1 $2")
        result = replace(result, pattern: #"([\#(quotes)])([\#(cjk)])"#, template: "$1 $2")
        result = replace(result, pattern: #"([\#(quotes)]+)[ ]*(.+?)[ ]*([\#(quotes)]+)"#, template: "$1$2$3")
        result = replace(result, pattern: #"([”])([\#(an)])"#, template: "$1 $2")
        result = replace(result, pattern: #"([\#(cjk)])(")([\#(an)])"#, template: "$1$2 $3")
        result = replace(result, pattern: #"([\#(an)\#(cjk)])( )('s)"#, template: "$1$3")

        let singleQuoteCJKManager = PlaceholderReplacer(placeholder: "SINGLE_QUOTE_CJK_PLACEHOLDER_", startDelimiter: "\u{E030}", endDelimiter: "\u{E031}")
        result = replace(result, pattern: #"(')([\#(cjk)]+)(')"#) { groups in
            singleQuoteCJKManager.store(groups[0] ?? "")
        }
        result = replace(result, pattern: #"([\#(cjk)])('[^s])"#, template: "$1 $2")
        result = replace(result, pattern: #"(')([\#(cjk)])"#, template: "$1 $2")
        result = singleQuoteCJKManager.restore(result)

        let textLength = result.count
        let slashCount = result.filter { $0 == "/" }.count
        if slashCount <= 1 {
            if textLength >= 5 {
                result = replace(result, pattern: #"([\#(cjk)])(#)([\#(cjk)]+)(#)([\#(cjk)])"#, template: "$1 $2$3$4 $5")
            }
            result = replace(result, pattern: #"([\#(cjk)])(#([^ ]))"#, template: "$1 $2")
            result = replace(result, pattern: #"(([^ ])#)([\#(cjk)])"#, template: "$1 $3")
        } else {
            if textLength >= 5 {
                result = replace(result, pattern: #"([\#(cjk)])(#)([\#(cjk)]+)(#)([\#(cjk)])"#, template: "$1 $2$3$4 $5")
            }
            result = replace(result, pattern: #"([^/])([\#(cjk)])(#[A-Za-z0-9]+)$"#, template: "$1$2 $3")
        }

        let compoundWordManager = PlaceholderReplacer(placeholder: "COMPOUND_WORD_PLACEHOLDER_", startDelimiter: "\u{E010}", endDelimiter: "\u{E011}")
        let compoundWordPattern = #"(?<![A-Za-z0-9])(?:[A-Za-z0-9]*[a-z][A-Za-z0-9]*-[A-Za-z0-9]+|[A-Za-z0-9]+-[A-Za-z0-9]*[a-z][A-Za-z0-9]*|[A-Za-z]+-[0-9]+|[A-Za-z]+[0-9]+-[A-Za-z0-9]+)(?:-[A-Za-z0-9]+)*(?![A-Za-z0-9])"#
        result = replace(result, pattern: compoundWordPattern) { groups in
            compoundWordManager.store(groups[0] ?? "")
        }

        result = replace(result, pattern: #"(?<![A-Za-z])([\#(a)])([\#(gradeOperators)])([\#(cjk)])"#, template: "$1$2 $3")
        result = replace(result, pattern: #"([\#(cjk)])([\#(operatorsWithHyphen)])([\#(an)])"#, template: "$1 $2 $3")
        result = replace(result, pattern: #"([\#(an)])([\#(operatorsWithHyphen)])([\#(cjk)])"#, template: "$1 $2 $3")
        result = replace(result, pattern: #"([\#(an)])([\#(operatorsNoHyphen)])([\#(an)])"#, template: "$1 $2 $3")
        result = replace(result, pattern: #"([A-Za-z])(-(?![a-z]))([A-Za-z0-9])|([A-Za-z]+[0-9]+)(-(?![a-z]))([0-9])|([0-9])(-(?![a-z0-9]))([A-Za-z])"#) { groups in
            if let g1 = groups[1], let g2 = groups[2], let g3 = groups[3] { return "\(g1) \(g2) \(g3)" }
            if let g4 = groups[4], let g5 = groups[5], let g6 = groups[6] { return "\(g4) \(g5) \(g6)" }
            if let g7 = groups[7], let g8 = groups[8], let g9 = groups[9] { return "\(g7) \(g8) \(g9)" }
            return groups[0] ?? ""
        }

        result = replace(result, pattern: #"([\#(cjk)])(<)([\#(an)])"#, template: "$1 $2 $3")
        result = replace(result, pattern: #"([\#(an)])(<)([\#(cjk)])"#, template: "$1 $2 $3")
        result = replace(result, pattern: #"([\#(an)])(<)([\#(an)])"#, template: "$1 $2 $3")
        result = replace(result, pattern: #"([\#(cjk)])(>)([\#(an)])"#, template: "$1 $2 $3")
        result = replace(result, pattern: #"([\#(an)])(>)([\#(cjk)])"#, template: "$1 $2 $3")
        result = replace(result, pattern: #"([\#(an)])(>)([\#(an)])"#, template: "$1 $2 $3")

        result = replace(result, pattern: #"([\#(cjk)])(\#(unixAbsoluteFilePath))"#, template: "$1 $2")
        result = replace(result, pattern: #"([\#(cjk)])(\#(unixRelativeFilePath))"#, template: "$1 $2")
        result = replace(result, pattern: #"([\#(cjk)])(\#(windowsFilePath))"#, template: "$1 $2")
        result = replace(result, pattern: #"(\#(unixAbsoluteFilePath)/)([\#(cjk)])"#, template: "$1 $2")
        result = replace(result, pattern: #"(\#(unixRelativeFilePath)/)([\#(cjk)])"#, template: "$1 $2")

        if slashCount == 1 {
            let filePathManager = PlaceholderReplacer(placeholder: "FILE_PATH_PLACEHOLDER_", startDelimiter: "\u{E020}", endDelimiter: "\u{E021}")
            result = replace(result, pattern: #"(\#(unixAbsoluteFilePath)|\#(unixRelativeFilePath))"#) { groups in
                filePathManager.store(groups[0] ?? "")
            }
            result = replace(result, pattern: #"([\#(cjk)])([/])([\#(cjk)])"#, template: "$1 $2 $3")
            result = replace(result, pattern: #"([\#(cjk)])([/])([\#(an)])"#, template: "$1 $2 $3")
            result = replace(result, pattern: #"([\#(an)])([/])([\#(cjk)])"#, template: "$1 $2 $3")
            result = replace(result, pattern: #"([\#(an)])([/])([\#(an)])"#, template: "$1 $2 $3")
            result = filePathManager.restore(result)
        }

        result = compoundWordManager.restore(result)

        result = replace(result, pattern: #"([\#(cjk)])([\#(leftBracketsExtended)])"#, template: "$1 $2")
        result = replace(result, pattern: #"([\#(rightBracketsExtended)])([\#(cjk)])"#, template: "$1 $2")
        result = replace(result, pattern: #"([\#(an)\#(cjk)])[ ]*([“])([\#(an)\#(cjk)\-_ ]+)([”])"#, template: "$1 $2$3$4")
        result = replace(result, pattern: #"([“])([\#(an)\#(cjk)\-_ ]+)([”])[ ]*([\#(an)\#(cjk)])"#, template: "$1$2$3 $4")
        result = replace(result, pattern: #"([\#(an)])([\#(leftBracketsBasic)])"#) { groups in
            let before = groups[1] ?? ""
            let bracket = groups[2] ?? ""
            if before.contains(".") { return groups[0] ?? "" }
            return "\(before) \(bracket)"
        }
        result = replace(result, pattern: #"([\#(rightBracketsBasic)])([\#(an)])"#, template: "$1 $2")
        result = replace(result, pattern: #"([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+) \("#, template: "$1(")

        result = replace(result, pattern: #"([\#(cjk)])([\#(ansCJKAfter)])"#, template: "$1 $2")
        result = replace(result, pattern: #"([\#(ansBeforeCJK)])([\#(cjk)])"#, template: "$1 $2")
        result = replace(result, pattern: #"(%)([\#(a)])"#, template: "$1 $2")
        result = replace(result, pattern: #"([ ]*)([·•‧])([ ]*)"#, template: "・")
        result = fixBracketSpacing(result)

        if hasHTMLTags {
            result = htmlTagManager.restore(result)
        }
        result = backtickManager.restore(result)
        return result
    }

    private static func fixBracketSpacing(_ text: String) -> String {
        var result = text
        let patterns: [(String, String, String)] = [
            (#"<([^<>]*)>"#, "<", ">"),
            (#"\(([^()]*)\)"#, "(", ")"),
            (#"\[([^\[\]]*)\]"#, "[", "]"),
            (#"\{([^{}]*)\}"#, "{", "}"),
        ]
        for (pattern, open, close) in patterns {
            result = replace(result, pattern: pattern) { groups in
                guard let inner = groups[1], !inner.isEmpty else { return open + close }
                let trimmed = inner.replacingOccurrences(of: #"^ +| +$"#, with: "", options: .regularExpression)
                return open + trimmed + close
            }
        }
        return result
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = cachedRegex(pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
    }

    private static func replace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = cachedRegex(pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func replace(_ text: String, pattern: String, transform: ([String?]) -> String) -> String {
        guard let regex = cachedRegex(pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var output = ""
        var cursor = 0
        for match in matches {
            output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (0..<match.numberOfRanges).map { index -> String? in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
            output += transform(groups)
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            output += nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
        }
        return output
    }

    private static let regexCache: RegexCache = RegexCache()

    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        regexCache.regex(for: pattern)
    }
}

private final class RegexCache: @unchecked Sendable {
    private var values: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        if let cached = values[pattern] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let compiled = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        lock.lock()
        values[pattern] = compiled
        lock.unlock()
        return compiled
    }
}

private final class PlaceholderReplacer {
    private var items: [String] = []
    private let placeholder: String
    private let startDelimiter: String
    private let endDelimiter: String
    private let pattern: NSRegularExpression?

    init(placeholder: String, startDelimiter: String, endDelimiter: String) {
        self.placeholder = placeholder
        self.startDelimiter = startDelimiter
        self.endDelimiter = endDelimiter
        let escapedStart = NSRegularExpression.escapedPattern(for: startDelimiter)
        let escapedEnd = NSRegularExpression.escapedPattern(for: endDelimiter)
        self.pattern = try? NSRegularExpression(pattern: "\(escapedStart)\(placeholder)(\\d+)\(escapedEnd)")
    }

    func store(_ item: String) -> String {
        let index = items.count
        items.append(item)
        return "\(startDelimiter)\(placeholder)\(index)\(endDelimiter)"
    }

    func restore(_ text: String) -> String {
        guard let pattern else { return text }
        let nsText = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var output = ""
        var cursor = 0
        for match in matches {
            output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let indexString = nsText.substring(with: match.range(at: 1))
            let item = Int(indexString).flatMap { items.indices.contains($0) ? items[$0] : nil } ?? ""
            output += item
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            output += nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
        }
        return output
    }
}
