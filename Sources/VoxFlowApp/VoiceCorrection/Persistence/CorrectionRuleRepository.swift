import Foundation
import VoxFlowVoiceCorrection

protocol CorrectionRuleLoading {
    func list() throws -> [CorrectionRule]
}

protocol CorrectionRuleRepository: CorrectionRuleLoading {
    func save(_ rule: CorrectionRule) throws
    func rule(id: UUID) throws -> CorrectionRule?
    func setEnabled(_ isEnabled: Bool, id: UUID, updatedAt: Date) throws
    func recordApplications(ruleIDs: [UUID], at date: Date) throws
    func delete(id: UUID) throws
    func clearAll() throws
}

extension CorrectionRuleRepository {
    func recordApplications(ruleIDs: [UUID], at date: Date) throws {}
}

final class CorrectionRuleSnapshotProvider {
    private let loader: any CorrectionRuleLoading
    private let lock = NSLock()
    private var currentSnapshot = RuleSnapshot.empty

    init(loader: any CorrectionRuleLoading) {
        self.loader = loader
    }

    func refresh() -> RuleSnapshot {
        lock.lock()
        defer { lock.unlock() }

        do {
            let rules = try loader.list()
            currentSnapshot = RuleSnapshot(
                version: currentSnapshot.version + 1,
                rules: rules
            )
        } catch {
            return currentSnapshot
        }
        return currentSnapshot
    }
}
