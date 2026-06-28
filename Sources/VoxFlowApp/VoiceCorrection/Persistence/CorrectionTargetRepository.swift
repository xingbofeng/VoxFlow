import Foundation
import VoxFlowVoiceCorrection

protocol CorrectionTargetRepository {
    func save(_ target: CorrectionTargetTerm) throws
    func target(id: UUID) throws -> CorrectionTargetTerm?
    func list() throws -> [CorrectionTargetTerm]
    func delete(id: UUID) throws

    /// Lists active, non-blocklisted targets as hotwords, sorted by hit count
    /// descending, then by manual source priority, then by recency.
    func listHotwords() throws -> [CorrectionTargetTerm]

    /// Marks a hotword as blocklisted, preventing auto-learning from re-adding it.
    func blocklist(id: UUID) throws

    /// Saves a hotword only if its normalized form is not in the blocklist.
    /// Returns true if saved, false if blocked.
    @discardableResult
    func saveHotwordIfNotBlocklisted(_ target: CorrectionTargetTerm) throws -> Bool

    /// Lists automatic-learning candidates that are waiting for user confirmation.
    func listLearningCandidates(limit: Int) throws -> [CorrectionTargetTerm]

    /// Records one key-term observation as an automatic-learning candidate.
    @discardableResult
    func recordKeyTermObservation(_ term: String, now: Date) throws -> CorrectionTargetTerm?

    /// Removes a hotword from the blocklist, allowing auto-learning to re-add it.
    func unblocklist(normalizedText: String) throws
}

extension CorrectionTargetRepository {
    func listHotwords() throws -> [CorrectionTargetTerm] { [] }
    func blocklist(id: UUID) throws {}
    @discardableResult
    func saveHotwordIfNotBlocklisted(_ target: CorrectionTargetTerm) throws -> Bool {
        try save(target)
        return true
    }
    func listLearningCandidates(limit: Int) throws -> [CorrectionTargetTerm] { [] }
    @discardableResult
    func recordKeyTermObservation(_ term: String, now: Date) throws -> CorrectionTargetTerm? { nil }
    func unblocklist(normalizedText: String) throws {}
}
