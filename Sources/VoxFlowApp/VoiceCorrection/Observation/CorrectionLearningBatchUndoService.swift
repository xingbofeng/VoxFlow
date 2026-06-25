import Foundation
import VoxFlowVoiceCorrection

struct CorrectionLearningBatchUndoService {
    let ruleRepository: any CorrectionRuleRepository
    let targetRepository: any CorrectionTargetRepository
    let snapshotProvider: CorrectionRuleSnapshotProvider

    @discardableResult
    func undo(_ event: CorrectionObservationLearningEvent) throws -> Int {
        let expectedItems = Dictionary(uniqueKeysWithValues: event.items.map { ($0.ruleID, $0) })
        let storedRules = try ruleRepository.list()
        let matchingRules = storedRules.filter { rule in
            guard let expected = expectedItems[rule.id] else { return false }
            return rule.source == .automaticLearning &&
                rule.targetID == expected.targetID &&
                rule.original == expected.original &&
                rule.replacement == expected.replacement
        }
        for rule in matchingRules {
            try ruleRepository.delete(id: rule.id)
        }

        let remainingRules = try ruleRepository.list()
        for targetID in Set(matchingRules.compactMap(\.targetID)) {
            guard remainingRules.contains(where: { $0.targetID == targetID }) == false,
                  let target = try targetRepository.target(id: targetID),
                  target.source == .automaticLearning
            else {
                continue
            }
            try targetRepository.delete(id: targetID)
        }
        if !matchingRules.isEmpty {
            _ = snapshotProvider.refresh()
        }
        return matchingRules.count
    }
}
