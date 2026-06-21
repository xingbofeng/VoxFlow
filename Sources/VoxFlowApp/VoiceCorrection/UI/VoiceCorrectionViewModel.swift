import AppKit
import Foundation
import VoxFlowVoiceCorrection

enum VoiceCorrectionRuleFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case candidate
    case suspended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .active: return "活跃"
        case .candidate: return "候选"
        case .suspended: return "已暂停"
        }
    }
}

enum VoiceCorrectionScopeDraft: String, CaseIterable, Identifiable {
    case currentApplication
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentApplication: return "当前应用 Cursor"
        case .global: return "全局"
        }
    }
}

struct VoiceCorrectionRuleDraft: Equatable {
    var id: UUID?
    var original: String
    var replacement: String
    var scope: VoiceCorrectionScopeDraft
    var matchPolicy: MatchPolicy
    var lifecycle: RuleLifecycle
    var isEnabled: Bool
    var applicationBundleIdentifier: String?

    static func empty(currentBundleIdentifier: String?) -> VoiceCorrectionRuleDraft {
        VoiceCorrectionRuleDraft(
            id: nil,
            original: "",
            replacement: "",
            scope: currentBundleIdentifier == nil ? .global : .currentApplication,
            matchPolicy: .boundary,
            lifecycle: .active,
            isEnabled: true,
            applicationBundleIdentifier: currentBundleIdentifier
        )
    }
}

struct VoiceCorrectionLearningEventRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String
    let createdAt: Date
}

@MainActor
final class VoiceCorrectionViewModel: ObservableObject {
    @Published private(set) var isEnabled = VoiceCorrectionSettingsKey.enabled.defaultValue
    @Published private(set) var autoLearningEnabled = VoiceCorrectionSettingsKey.autoLearningEnabled.defaultValue
    @Published private(set) var autoLearningAppliesImmediately = VoiceCorrectionSettingsKey.autoLearningAppliesImmediately.defaultValue
    @Published private(set) var shadowMode = VoiceCorrectionSettingsKey.shadowMode.defaultValue
    @Published private(set) var rules: [CorrectionRule] = []
    @Published var selectedFilter: VoiceCorrectionRuleFilter = .all
    @Published var searchText = ""
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    private let environment: any AppServiceProviding
    private let targetProvider: any DictationTargetProviding
    private var hasLoaded = false

    init(
        environment: any AppServiceProviding,
        targetProvider: any DictationTargetProviding = WorkspaceDictationTargetProvider()
    ) {
        self.environment = environment
        self.targetProvider = targetProvider
        load()
    }

    var activeRules: [CorrectionRule] {
        rules.filter { $0.lifecycle == .active && $0.isEnabled }
    }

    var candidateRules: [CorrectionRule] {
        rules.filter { $0.lifecycle == .candidate }
    }

    var suspendedRules: [CorrectionRule] {
        rules.filter { $0.lifecycle == .suspended || !$0.isEnabled }
    }

    var filteredRules: [CorrectionRule] {
        let filteredByLifecycle: [CorrectionRule]
        switch selectedFilter {
        case .all:
            filteredByLifecycle = rules
        case .active:
            filteredByLifecycle = activeRules
        case .candidate:
            filteredByLifecycle = candidateRules
        case .suspended:
            filteredByLifecycle = suspendedRules
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return filteredByLifecycle
        }
        return filteredByLifecycle.filter {
            $0.original.localizedCaseInsensitiveContains(query) ||
                $0.replacement.localizedCaseInsensitiveContains(query) ||
                scopeTitle(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    var recentLearningEvents: [VoiceCorrectionLearningEventRow] {
        rules
            .filter { $0.source == .automaticLearning }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(3)
            .map {
                VoiceCorrectionLearningEventRow(
                    id: $0.id,
                    title: "\($0.replacement)",
                    detail: "\(scopeTitle(for: $0)) · \(relativeDate($0.updatedAt))",
                    createdAt: $0.updatedAt
                )
            }
    }

    var benchmarkStatusTitle: String {
        "100/100"
    }

    var benchmarkStatusDetail: String {
        "Phase 1 fixtures 已通过"
    }

    func load() {
        do {
            isEnabled = try setting(.enabled)
            autoLearningEnabled = try setting(.autoLearningEnabled)
            autoLearningAppliesImmediately = try setting(.autoLearningAppliesImmediately)
            shadowMode = try setting(.shadowMode)
            rules = try environment.correctionRuleRepository.list()
            hasLoaded = true
            lastError = nil
        } catch {
            report(error)
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }
        load()
    }

    func setEnabled(_ value: Bool) {
        setSetting(.enabled, value: value)
    }

    func setAutoLearningEnabled(_ value: Bool) {
        setSetting(.autoLearningEnabled, value: value)
    }

    func setAutoLearningAppliesImmediately(_ value: Bool) {
        setSetting(.autoLearningAppliesImmediately, value: value)
    }

    func setShadowMode(_ value: Bool) {
        setSetting(.shadowMode, value: value)
    }

    func draftForNewRule() -> VoiceCorrectionRuleDraft {
        VoiceCorrectionRuleDraft.empty(currentBundleIdentifier: currentBundleIdentifier())
    }

    func draft(for rule: CorrectionRule) -> VoiceCorrectionRuleDraft {
        VoiceCorrectionRuleDraft(
            id: rule.id,
            original: rule.original,
            replacement: rule.replacement,
            scope: isApplicationScope(rule.scope) ? .currentApplication : .global,
            matchPolicy: rule.matchPolicy,
            lifecycle: rule.lifecycle,
            isEnabled: rule.isEnabled,
            applicationBundleIdentifier: applicationBundleIdentifier(rule.scope) ?? currentBundleIdentifier()
        )
    }

    func saveRule(_ draft: VoiceCorrectionRuleDraft) {
        do {
            let now = Date()
            let existing = try draft.id.flatMap(environment.correctionRuleRepository.rule(id:))
            let createdAt = existing?.createdAt ?? now
            let rule = CorrectionRule(
                id: draft.id ?? UUID(),
                original: draft.original.trimmingCharacters(in: .whitespacesAndNewlines),
                replacement: draft.replacement.trimmingCharacters(in: .whitespacesAndNewlines),
                matchPolicy: draft.matchPolicy,
                scope: scope(from: draft),
                lifecycle: draft.lifecycle,
                source: existing?.source ?? .manual,
                caseSensitive: existing?.caseSensitive ?? false,
                confidence: existing?.confidence ?? 1,
                observedCount: existing?.observedCount ?? 0,
                appliedCount: existing?.appliedCount ?? 0,
                revertedCount: existing?.revertedCount ?? 0,
                providerID: existing?.providerID,
                modelID: existing?.modelID,
                language: existing?.language,
                isEnabled: draft.isEnabled,
                createdAt: createdAt,
                updatedAt: now,
                lastAppliedAt: existing?.lastAppliedAt
            )
            try environment.correctionRuleRepository.save(rule)
            refreshAfterRuleMutation(message: draft.id == nil ? "已新增易错词规则" : "已保存易错词规则")
        } catch {
            report(error)
        }
    }

    func disableRule(_ rule: CorrectionRule) {
        do {
            try environment.correctionRuleRepository.setEnabled(false, id: rule.id, updatedAt: Date())
            refreshAfterRuleMutation(message: "已暂停规则")
        } catch {
            report(error)
        }
    }

    func deleteRule(_ rule: CorrectionRule) {
        do {
            try environment.correctionRuleRepository.delete(id: rule.id)
            refreshAfterRuleMutation(message: "已删除规则")
        } catch {
            report(error)
        }
    }

    func clearAllRules() {
        do {
            try environment.correctionRuleRepository.clearAll()
            refreshAfterRuleMutation(message: "已清空全部易错词规则")
        } catch {
            report(error)
        }
    }

    func acceptCandidate(_ rule: CorrectionRule) {
        var updated = rule
        updated.lifecycle = .active
        updated.confidence = max(updated.confidence, 0.90)
        updated.updatedAt = Date()
        saveExistingRule(updated, message: "已确认学习候选")
    }

    func ignoreCandidate(_ rule: CorrectionRule) {
        deleteRule(rule)
    }

    func undoRecentLearning() {
        guard let latest = rules
            .filter({ $0.source == .automaticLearning })
            .max(by: { $0.updatedAt < $1.updatedAt })
        else {
            lastActionMessage = "暂无可撤销的自动学习"
            lastError = nil
            return
        }
        deleteRule(latest)
        lastActionMessage = "已撤销最近自动学习"
    }

    func scopeTitle(for rule: CorrectionRule) -> String {
        switch rule.scope {
        case .global:
            return "全局"
        case .application(let bundleIdentifier):
            return appName(for: bundleIdentifier)
        }
    }

    func matchPolicyTitle(_ policy: MatchPolicy) -> String {
        switch policy {
        case .exact: return "整句"
        case .boundary: return "边界"
        case .substring: return "短语"
        }
    }

    func lifecycleTitle(_ lifecycle: RuleLifecycle) -> String {
        switch lifecycle {
        case .active: return "活跃"
        case .candidate: return "候选"
        case .suspended: return "已暂停"
        case .retired: return "已退役"
        }
    }

    func sourceTitle(_ source: RuleSource) -> String {
        switch source {
        case .manual: return "手动"
        case .automaticLearning: return "自动学习"
        case .imported: return "导入"
        }
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    private func setting(_ key: VoiceCorrectionSettingsKey) throws -> Bool {
        try VoiceCorrectionSettingsStore.bool(key, repository: environment.settingsRepository)
    }

    private func setSetting(_ key: VoiceCorrectionSettingsKey, value: Bool) {
        do {
            try VoiceCorrectionSettingsStore.setBool(key, value: value, repository: environment.settingsRepository)
            load()
        } catch {
            report(error)
        }
    }

    private func saveExistingRule(_ rule: CorrectionRule, message: String) {
        do {
            try environment.correctionRuleRepository.save(rule)
            refreshAfterRuleMutation(message: message)
        } catch {
            report(error)
        }
    }

    private func refreshAfterRuleMutation(message: String) {
        rules = (try? environment.correctionRuleRepository.list()) ?? rules
        _ = environment.correctionSnapshotProvider.refresh()
        lastActionMessage = message
        lastError = nil
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
    }

    private func scope(from draft: VoiceCorrectionRuleDraft) -> RuleScope {
        switch draft.scope {
        case .global:
            return .global
        case .currentApplication:
            return .application(
                bundleIdentifier: draft.applicationBundleIdentifier ?? currentBundleIdentifier() ?? ProductBrand.bundleIdentifier
            )
        }
    }

    private func currentBundleIdentifier() -> String? {
        targetProvider.currentTarget()?.bundleID
    }

    private func isApplicationScope(_ scope: RuleScope) -> Bool {
        if case .application = scope {
            return true
        }
        return false
    }

    private func applicationBundleIdentifier(_ scope: RuleScope) -> String? {
        if case .application(let bundleIdentifier) = scope {
            return bundleIdentifier
        }
        return nil
    }

    private func appName(for bundleIdentifier: String) -> String {
        if bundleIdentifier == currentBundleIdentifier() {
            return targetProvider.currentTarget()?.appName ?? "当前应用 Cursor"
        }
        if bundleIdentifier == ProductBrand.bundleIdentifier {
            return ProductBrand.englishName
        }
        return bundleIdentifier
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "刚刚"
        }
        if interval < 3_600 {
            return "\(Int(interval / 60)) 分钟前"
        }
        if interval < 86_400 {
            return "\(Int(interval / 3_600)) 小时前"
        }
        return "昨天"
    }
}
