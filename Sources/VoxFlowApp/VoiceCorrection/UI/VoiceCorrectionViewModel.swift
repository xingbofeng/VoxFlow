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
        case .all: return L10n.localize("correction.filter.all", comment: "")
        case .active: return L10n.localize("correction.filter.active", comment: "")
        case .candidate: return L10n.localize("correction.filter.candidate", comment: "")
        case .suspended: return L10n.localize("correction.filter.suspended", comment: "")
        }
    }
}

enum VoiceCorrectionVocabularyTab: String, CaseIterable, Identifiable {
    case hotwords
    case textReplacement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hotwords: return L10n.localize("vocabulary.tab.hotwords", comment: "")
        case .textReplacement: return L10n.localize("vocabulary.tab.text_replacement", comment: "")
        }
    }

    var subtitle: String {
        switch self {
        case .hotwords: return L10n.localize("vocabulary.hotwords.description", comment: "")
        case .textReplacement: return L10n.localize("vocabulary.text_replacement.description", comment: "")
        }
    }
}

enum VoiceCorrectionScopeDraft: String, CaseIterable, Identifiable {
    case currentApplication
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentApplication: return L10n.localize("correction.scope.current_application", comment: "")
        case .global: return L10n.localize("correction.scope.global", comment: "")
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

struct VoiceCorrectionTargetRow: Identifiable, Equatable {
    let id: UUID
    let projection: CorrectionTargetProjection

    var targetText: String { projection.target.text }
    var aliasPreview: String {
        projection.aliasPreview.isEmpty ? L10n.localize("correction.alias_preview_empty", comment: "") : projection.aliasPreview
    }
    var scopeTitle: String
    var correctionCountText: String {
        L10n.format("correction.target.correction_count_format", comment: "", projection.appliedCount)
    }
    var hitCountText: String {
        L10n.format("vocabulary.hotwords.hit_count_format", comment: "", projection.target.hitCount)
    }
    var recentUseText: String
    var statusTitle: String
    var aliases: [CorrectionRule] { projection.aliases }
}

private final class NotificationObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
        self.value = value
    }
}

@MainActor
final class VoiceCorrectionViewModel: ObservableObject {
    @Published private(set) var isEnabled = VoiceCorrectionSettingsKey.enabled.defaultValue
    @Published private(set) var autoLearningEnabled = VoiceCorrectionSettingsKey.autoLearningEnabled.defaultValue
    @Published private(set) var autoLearningAppliesImmediately = VoiceCorrectionSettingsKey.autoLearningAppliesImmediately.defaultValue
    @Published private(set) var shadowMode = VoiceCorrectionSettingsKey.shadowMode.defaultValue
    @Published private(set) var rules: [CorrectionRule] = []
    @Published private(set) var targetRows: [VoiceCorrectionTargetRow] = []
    @Published private(set) var learningCandidates: [CorrectionTargetTerm] = []
    @Published private(set) var selectedTargetID: UUID?
    @Published var selectedVocabularyTab: VoiceCorrectionVocabularyTab = .hotwords
    @Published var selectedFilter: VoiceCorrectionRuleFilter = .all
    @Published var searchText = ""
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    private let environment: any AppServiceProviding
    private let targetProvider: any DictationTargetProviding
    private let notificationCenter: NotificationCenter
    private var notificationObservers: [NotificationObserverToken] = []
    private var hasLoaded = false

    init(
        environment: any AppServiceProviding,
        targetProvider: any DictationTargetProviding = WorkspaceDictationTargetProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.environment = environment
        self.targetProvider = targetProvider
        self.notificationCenter = notificationCenter
        observeVocabularyChangeEvents()
        load()
    }

    deinit {
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer.value)
        }
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

    var filteredTargetRows: [VoiceCorrectionTargetRow] {
        let filteredByLifecycle: [VoiceCorrectionTargetRow]
        switch selectedFilter {
        case .all:
            filteredByLifecycle = visibleTargetRows
        case .active:
            filteredByLifecycle = targetRows.filter { $0.projection.lifecycle == .active }
        case .candidate:
            filteredByLifecycle = []
        case .suspended:
            filteredByLifecycle = targetRows.filter {
                $0.projection.lifecycle == .suspended || $0.projection.lifecycle == .retired
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return filteredByLifecycle
        }
        return filteredByLifecycle.filter { row in
            row.targetText.localizedCaseInsensitiveContains(query) ||
                row.aliases.contains { $0.original.localizedCaseInsensitiveContains(query) } ||
                row.scopeTitle.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredHotwordRows: [VoiceCorrectionTargetRow] {
        let hotwords = sortHotwordRows(
            visibleTargetRows.filter { $0.projection.lifecycle == .active }
        )
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return hotwords
        }
        return hotwords.filter { row in
            row.targetText.localizedCaseInsensitiveContains(query) ||
                row.aliases.contains { $0.original.localizedCaseInsensitiveContains(query) }
        }
    }

    var selectedTarget: VoiceCorrectionTargetRow? {
        guard let selectedTargetID else {
            return filteredTargetRows.first
        }
        return targetRows.first { $0.id == selectedTargetID }
    }

    var selectedTargetAliases: [CorrectionRule] {
        selectedTarget?.aliases ?? []
    }

    var visibleTargetRows: [VoiceCorrectionTargetRow] {
        targetRows.filter { row in
            row.projection.lifecycle != .candidate && row.projection.target.isBlocklisted == false
        }
    }

    var visibleTargetCount: Int {
        visibleTargetRows.count
    }

    var visibleAliasCount: Int {
        visibleTargetRows.reduce(0) { $0 + $1.aliases.filter { $0.lifecycle != .candidate }.count }
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

    func load() {
        do {
            isEnabled = try setting(.enabled)
            autoLearningEnabled = try setting(.autoLearningEnabled)
            autoLearningAppliesImmediately = try setting(.autoLearningAppliesImmediately)
            shadowMode = try setting(.shadowMode)
            rules = try environment.correctionRuleRepository.list()
            rebuildTargetRows()
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

    func selectTarget(_ row: VoiceCorrectionTargetRow) {
        selectedTargetID = row.id
    }

    func createTarget(text: String, aliasesText: String) {
        let targetText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetText.isEmpty else {
            lastError = L10n.localize("correction.feedback.target_required", comment: "")
            lastActionMessage = nil
            return
        }

        do {
            let now = Date()
            let target = CorrectionTargetTerm(
                text: targetText,
                scope: .global,
                lifecycle: .active,
                source: .manual,
                createdAt: now,
                updatedAt: now
            )
            try environment.correctionTargetRepository.save(target)

            let aliases = parsedAliases(from: aliasesText)
            guard hasDuplicateAliases(aliases) == false else {
                lastError = L10n.localize("correction.feedback.alias_duplicate", comment: "")
                lastActionMessage = nil
                return
            }
            for alias in aliases {
                let rule = CorrectionRule(
                    targetID: target.id,
                    original: alias,
                    replacement: target.text,
                    matchPolicy: .boundary,
                    scope: target.scope,
                    lifecycle: .active,
                    source: .manual,
                    createdAt: now,
                    updatedAt: now
                )
                try environment.correctionRuleRepository.save(rule)
            }

            rules = try environment.correctionRuleRepository.list()
            rebuildTargetRows()
            selectedTargetID = target.id
            _ = environment.correctionSnapshotProvider.refresh()
            syncHotwordFileFromRepository()
            lastActionMessage = L10n.localize("correction.feedback.target_added", comment: "")
            lastError = nil
        } catch {
            report(error)
        }
    }

    func addHotword(text: String) {
        let hotwordText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hotwordText.isEmpty else {
            lastError = L10n.localize("correction.feedback.target_required", comment: "")
            lastActionMessage = nil
            return
        }

        let normalized = CorrectionTargetTerm.normalize(hotwordText)
        if visibleTargetRows.contains(where: { $0.projection.target.normalizedText == normalized }) {
            lastActionMessage = L10n.localize("vocabulary.hotwords.toast.duplicate", comment: "")
            lastError = nil
            return
        }

        do {
            let target = CorrectionTargetTerm(
                text: hotwordText,
                scope: .global,
                lifecycle: .active,
                source: .manual
            )
            let saved = try environment.correctionTargetRepository.saveHotwordIfNotBlocklisted(target)
            guard saved else {
                lastActionMessage = L10n.localize("vocabulary.hotwords.toast.duplicate", comment: "")
                lastError = nil
                return
            }
            refreshAfterTargetMutation(message: L10n.localize("correction.feedback.target_added", comment: ""))
        } catch {
            report(error)
        }
    }

    func deleteHotword(_ row: VoiceCorrectionTargetRow) {
        do {
            try environment.correctionTargetRepository.blocklist(id: row.id)
            refreshAfterTargetMutation(message: L10n.localize("vocabulary.hotwords.toast.deleted", comment: ""))
        } catch {
            report(error)
        }
    }

    func acceptLearningCandidate(_ candidate: CorrectionTargetTerm) {
        do {
            var promoted = candidate
            promoted.lifecycle = .active
            promoted.updatedAt = Date()
            let saved = try environment.correctionTargetRepository.saveHotwordIfNotBlocklisted(promoted)
            guard saved else {
                refreshAfterTargetMutation(message: L10n.localize("vocabulary.hotwords.toast.duplicate", comment: ""))
                return
            }
            selectedTargetID = candidate.id
            refreshAfterTargetMutation(message: L10n.localize("vocabulary.learning.toast.accepted", comment: ""))
        } catch {
            report(error)
        }
    }

    func ignoreLearningCandidate(_ candidate: CorrectionTargetTerm) {
        do {
            try environment.correctionTargetRepository.blocklist(id: candidate.id)
            refreshAfterTargetMutation(message: L10n.localize("vocabulary.learning.toast.ignored", comment: ""))
        } catch {
            report(error)
        }
    }

    func addAliases(to row: VoiceCorrectionTargetRow, aliasesText: String) {
        let aliases = parsedAliases(from: aliasesText)
        guard !aliases.isEmpty else {
            lastError = L10n.localize("correction.feedback.alias_required", comment: "")
            lastActionMessage = nil
            return
        }

        do {
            let now = Date()
            let target = try persistedTarget(from: row, updatedAt: now)
            let existingAliases = Set(row.aliases.map { $0.original.lowercased() })
            guard hasDuplicateAliases(aliases) == false,
                  aliases.allSatisfy({ !existingAliases.contains($0.lowercased()) })
            else {
                lastError = L10n.localize("correction.feedback.alias_duplicate", comment: "")
                lastActionMessage = nil
                return
            }
            for alias in aliases {
                let rule = CorrectionRule(
                    targetID: target.id,
                    original: alias,
                    replacement: target.text,
                    matchPolicy: .boundary,
                    scope: target.scope,
                    lifecycle: .active,
                    source: .manual,
                    createdAt: now,
                    updatedAt: now
                )
                try environment.correctionRuleRepository.save(rule)
            }
            rules = try environment.correctionRuleRepository.list()
            rebuildTargetRows()
            selectedTargetID = target.id
            _ = environment.correctionSnapshotProvider.refresh()
            lastActionMessage = L10n.localize("correction.feedback.alias_added", comment: "")
            lastError = nil
        } catch {
            report(error)
        }
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
            refreshAfterRuleMutation(message: draft.id == nil
                ? L10n.localize("correction.feedback.rule_created", comment: "")
                : L10n.localize("correction.feedback.rule_saved", comment: ""))
        } catch {
            report(error)
        }
    }

    func disableRule(_ rule: CorrectionRule) {
        do {
            try environment.correctionRuleRepository.setEnabled(false, id: rule.id, updatedAt: Date())
            refreshAfterRuleMutation(message: L10n.localize("correction.feedback.rule_paused", comment: ""))
        } catch {
            report(error)
        }
    }

    func deleteRule(_ rule: CorrectionRule) {
        do {
            try environment.correctionRuleRepository.delete(id: rule.id)
            refreshAfterRuleMutation(message: L10n.localize("correction.feedback.rule_deleted", comment: ""))
        } catch {
            report(error)
        }
    }

    func clearAllRules() {
        do {
            try environment.correctionRuleRepository.clearAll()
            refreshAfterRuleMutation(message: L10n.localize("correction.feedback.rules_cleared", comment: ""))
        } catch {
            report(error)
        }
    }

    func openHotwordFile() {
        guard let service = environment.hotwordFileSyncService else {
            lastError = L10n.localize("app.paths.application_support_unavailable", comment: "")
            lastActionMessage = nil
            return
        }
        do {
            try service.ensureFileExists()
            service.openInSystemEditor()
            lastActionMessage = L10n.localize("vocabulary.hotwords.file_button_help", comment: "")
            lastError = nil
        } catch {
            report(error)
        }
    }

    func acceptCandidate(_ rule: CorrectionRule) {
        var updated = rule
        updated.lifecycle = .active
        updated.confidence = max(updated.confidence, 0.90)
        updated.updatedAt = Date()
        saveExistingRule(updated, message: L10n.localize("correction.feedback.learning_confirmed", comment: ""))
    }

    func ignoreCandidate(_ rule: CorrectionRule) {
        deleteRule(rule)
    }

    func undoRecentLearning() {
        guard let latest = rules
            .filter({ $0.source == .automaticLearning })
            .max(by: { $0.updatedAt < $1.updatedAt })
        else {
            lastActionMessage = L10n.localize("correction.feedback.undo_none", comment: "")
            lastError = nil
            return
        }
        do {
            try environment.correctionRuleRepository.delete(id: latest.id)
            if let targetID = latest.targetID,
               let target = try environment.correctionTargetRepository.target(id: targetID),
               target.source == .automaticLearning {
                let remainingRules = try environment.correctionRuleRepository.list()
                if remainingRules.contains(where: { $0.targetID == targetID }) == false {
                    try environment.correctionTargetRepository.delete(id: targetID)
                    syncHotwordFileFromRepository()
                }
            }
            refreshAfterRuleMutation(message: L10n.localize("correction.feedback.undo_latest", comment: ""))
        } catch {
            report(error)
        }
    }

    func undoLearningBatch(_ event: CorrectionObservationLearningEvent) {
        do {
            let deletedCount = try correctionLearningBatchUndoService.undo(event)
            refreshAfterRuleMutation(
                message: deletedCount > 0
                    ? L10n.localize("correction.feedback.undo_batch", comment: "")
                    : L10n.localize("correction.feedback.undo_not_available", comment: "")
            )
        } catch {
            report(error)
        }
    }

    func applyAutomaticLearningEvent(_ event: CorrectionObservationLearningEvent) {
        load()
        lastActionMessage = event.message
    }

    func scopeTitle(for rule: CorrectionRule) -> String {
        switch rule.scope {
        case .global:
            return L10n.localize("correction.scope.global", comment: "")
        case .application(let bundleIdentifier):
            return appName(for: bundleIdentifier)
        }
    }

    func matchPolicyTitle(_ policy: MatchPolicy) -> String {
        switch policy {
        case .exact: return L10n.localize("correction.match_policy.exact", comment: "")
        case .boundary: return L10n.localize("correction.match_policy.boundary", comment: "")
        case .substring: return L10n.localize("correction.match_policy.substring", comment: "")
        }
    }

    func lifecycleTitle(_ lifecycle: RuleLifecycle) -> String {
        switch lifecycle {
        case .active: return L10n.localize("correction.lifecycle.active", comment: "")
        case .candidate: return L10n.localize("correction.lifecycle.candidate", comment: "")
        case .suspended: return L10n.localize("correction.lifecycle.suspended", comment: "")
        case .retired: return L10n.localize("correction.lifecycle.retired", comment: "")
        }
    }

    func sourceTitle(_ source: RuleSource) -> String {
        switch source {
        case .manual: return L10n.localize("correction.source.manual", comment: "")
        case .automaticLearning: return L10n.localize("correction.source.automatic_learning", comment: "")
        case .imported: return L10n.localize("correction.source.imported", comment: "")
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
        rebuildTargetRows()
        _ = environment.correctionSnapshotProvider.refresh()
        lastActionMessage = message
        lastError = nil
    }

    private func refreshAfterTargetMutation(message: String) {
        rules = (try? environment.correctionRuleRepository.list()) ?? rules
        rebuildTargetRows()
        _ = environment.correctionSnapshotProvider.refresh()
        syncHotwordFileFromRepository()
        lastActionMessage = message
        lastError = nil
    }

    private func syncHotwordFileFromRepository() {
        environment.hotwordFileSyncService?.writeBackFromRepository()
    }

    private func sortHotwordRows(_ rows: [VoiceCorrectionTargetRow]) -> [VoiceCorrectionTargetRow] {
        rows.sorted { lhs, rhs in
            let textComparison = lhs.targetText.localizedCaseInsensitiveCompare(rhs.targetText)
            if textComparison != .orderedSame {
                return textComparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func rebuildTargetRows() {
        let allTargets = (try? environment.correctionTargetRepository.list()) ?? []
        let hotwords = (try? environment.correctionTargetRepository.listHotwords()) ?? []
        let hotwordIDs = Set(hotwords.map(\.id))
        let targets = hotwords + allTargets.filter { !hotwordIDs.contains($0.id) }
        let projections = CorrectionTargetProjection.build(targets: targets, rules: rules)
        targetRows = projections.map { projection in
            VoiceCorrectionTargetRow(
                id: projection.id,
                projection: projection,
                scopeTitle: scopeTitle(for: projection.target.scope),
                recentUseText: projection.lastAppliedAt.map(relativeDate) ?? L10n.localize("correction.time.never", comment: ""),
                statusTitle: lifecycleTitle(projection.lifecycle)
            )
        }
        learningCandidates = (try? environment.correctionTargetRepository.listLearningCandidates(limit: 50)) ?? []
        if let selectedTargetID,
           !targetRows.contains(where: { $0.id == selectedTargetID }) {
            self.selectedTargetID = targetRows.first?.id
        } else if selectedTargetID == nil {
            selectedTargetID = targetRows.first?.id
        }
    }

    private func persistedTarget(
        from row: VoiceCorrectionTargetRow,
        updatedAt: Date
    ) throws -> CorrectionTargetTerm {
        if let target = try environment.correctionTargetRepository.target(id: row.id) {
            return target
        }
        var target = row.projection.target
        target.updatedAt = updatedAt
        try environment.correctionTargetRepository.save(target)
        return target
    }

    private func parsedAliases(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func hasDuplicateAliases(_ aliases: [String]) -> Bool {
        var seen = Set<String>()
        for alias in aliases {
            let normalized = alias.lowercased()
            guard seen.insert(normalized).inserted else {
                return true
            }
        }
        return false
    }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
    }

    private var correctionLearningBatchUndoService: CorrectionLearningBatchUndoService {
        CorrectionLearningBatchUndoService(
            ruleRepository: environment.correctionRuleRepository,
            targetRepository: environment.correctionTargetRepository,
            snapshotProvider: environment.correctionSnapshotProvider
        )
    }

    private func observeVocabularyChangeEvents() {
        notificationObservers.append(NotificationObserverToken(notificationCenter.addObserver(
            forName: .correctionObservationLearningEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CorrectionObservationLearningEvent else {
                return
            }
            Task { @MainActor [weak self] in
                self?.applyAutomaticLearningEvent(event)
            }
        }))
        notificationObservers.append(NotificationObserverToken(notificationCenter.addObserver(
            forName: .correctionVocabularyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.load()
            }
        }))
    }

    private func scopeTitle(for scope: RuleScope) -> String {
        switch scope {
        case .global:
            return L10n.localize("correction.scope.global", comment: "")
        case .application(let bundleIdentifier):
            return appName(for: bundleIdentifier)
        }
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
            return targetProvider.currentTarget()?.appName ?? L10n.localize("correction.scope.current_application", comment: "")
        }
        if bundleIdentifier == ProductBrand.bundleIdentifier {
            return ProductBrand.displayName
        }
        return bundleIdentifier
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return L10n.localize("correction.time.just_now", comment: "")
        }
        if interval < 3_600 {
            return L10n.format("correction.time.minutes_ago_format", comment: "", Int(interval / 60))
        }
        if interval < 86_400 {
            return L10n.format("correction.time.hours_ago_format", comment: "", Int(interval / 3_600))
        }
        return L10n.localize("correction.time.yesterday", comment: "")
    }
}
