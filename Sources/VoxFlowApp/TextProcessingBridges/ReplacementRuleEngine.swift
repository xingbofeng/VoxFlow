import Foundation

struct ReplacementRuleApplicationResult: Equatable {
    let text: String
    let warnings: [String]
}

struct ReplacementRuleEngine {
    func apply(_ rules: [ReplacementRule], to text: String) -> ReplacementRuleApplicationResult {
        var currentText = text
        var warnings: [String] = []

        for rule in rules.sorted(by: ruleSort) {
            switch rule.matchMode {
            case .exact:
                if currentText == rule.source {
                    currentText = rule.target
                }
            case .contains:
                currentText = currentText.replacingOccurrences(of: rule.source, with: rule.target)
            case .regex:
                do {
                    let regex = try NSRegularExpression(pattern: rule.source)
                    let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
                    currentText = regex.stringByReplacingMatches(
                        in: currentText,
                        options: [],
                        range: range,
                        withTemplate: rule.target
                    )
                } catch {
                    warnings.append("replacement_rule_invalid_regex:\(rule.id)")
                }
            }
        }

        return ReplacementRuleApplicationResult(text: currentText, warnings: warnings)
    }

    private func ruleSort(_ lhs: ReplacementRule, _ rhs: ReplacementRule) -> Bool {
        if lhs.priority == rhs.priority {
            return lhs.source < rhs.source
        }
        return lhs.priority < rhs.priority
    }
}
