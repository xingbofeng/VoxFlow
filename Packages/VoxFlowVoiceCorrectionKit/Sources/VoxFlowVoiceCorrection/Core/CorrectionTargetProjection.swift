import Foundation

public struct CorrectionTargetProjection: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var target: CorrectionTargetTerm
    public var aliases: [CorrectionRule]
    public var aliasPreview: String
    public var appliedCount: Int
    public var lastAppliedAt: Date?
    public var lifecycle: RuleLifecycle

    public init(target: CorrectionTargetTerm, aliases: [CorrectionRule]) {
        let sortedAliases = aliases.sorted {
            $0.original.localizedCaseInsensitiveCompare($1.original) == .orderedAscending
        }
        self.id = target.id
        self.target = target
        self.aliases = sortedAliases
        self.aliasPreview = sortedAliases.map(\.original).joined(separator: "、")
        self.appliedCount = sortedAliases.reduce(target.appliedCount) { $0 + $1.appliedCount }
        self.lastAppliedAt = ([target.lastAppliedAt] + sortedAliases.map(\.lastAppliedAt))
            .compactMap { $0 }
            .max()
        self.lifecycle = target.lifecycle
    }

    public static func build(
        targets: [CorrectionTargetTerm],
        rules: [CorrectionRule]
    ) -> [CorrectionTargetProjection] {
        var projections: [CorrectionTargetProjection] = []
        let targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        let explicitlyGrouped = Dictionary(grouping: rules.compactMap { rule -> (UUID, CorrectionRule)? in
            guard let targetID = rule.targetID, targetsByID[targetID] != nil else {
                return nil
            }
            return (targetID, rule)
        }, by: \.0).mapValues { pairs in pairs.map(\.1) }

        for target in targets {
            projections.append(
                CorrectionTargetProjection(
                    target: target,
                    aliases: explicitlyGrouped[target.id] ?? []
                )
            )
        }

        let legacyRules = rules.filter { rule in
            guard let targetID = rule.targetID else {
                return true
            }
            return targetsByID[targetID] == nil
        }
        var legacyGroups: [(key: LegacyTargetKey, rules: [CorrectionRule])] = []
        for rule in legacyRules {
            let key = LegacyTargetKey(replacement: rule.replacement, scope: rule.scope)
            if let index = legacyGroups.firstIndex(where: { $0.key == key }) {
                legacyGroups[index].rules.append(rule)
            } else {
                legacyGroups.append((key, [rule]))
            }
        }

        for group in legacyGroups {
            let firstRule = group.rules[0]
            let target = CorrectionTargetTerm(
                text: firstRule.replacement,
                scope: firstRule.scope,
                lifecycle: firstRule.lifecycle,
                source: firstRule.source,
                observedCount: group.rules.reduce(0) { $0 + $1.observedCount },
                appliedCount: 0,
                revertedCount: group.rules.reduce(0) { $0 + $1.revertedCount },
                createdAt: group.rules.map(\.createdAt).min() ?? firstRule.createdAt,
                updatedAt: group.rules.map(\.updatedAt).max() ?? firstRule.updatedAt,
                lastAppliedAt: group.rules.compactMap(\.lastAppliedAt).max()
            )
            projections.append(CorrectionTargetProjection(target: target, aliases: group.rules))
        }

        return projections.sorted {
            if $0.lastAppliedAt != $1.lastAppliedAt {
                return ($0.lastAppliedAt ?? .distantPast) > ($1.lastAppliedAt ?? .distantPast)
            }
            return $0.target.text.localizedCaseInsensitiveCompare($1.target.text) == .orderedAscending
        }
    }
}

private struct LegacyTargetKey: Equatable {
    let replacement: String
    let scope: RuleScope
}
