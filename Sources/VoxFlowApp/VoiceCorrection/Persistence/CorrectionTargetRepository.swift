import Foundation
import VoxFlowVoiceCorrection

protocol CorrectionTargetRepository {
    func save(_ target: CorrectionTargetTerm) throws
    func target(id: UUID) throws -> CorrectionTargetTerm?
    func list() throws -> [CorrectionTargetTerm]
    func delete(id: UUID) throws
}
