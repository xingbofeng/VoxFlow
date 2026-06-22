import Foundation
import VoxFlowASRCore
import VoxFlowProviderNVIDIA

struct ASRProviderEvaluationCandidate: Equatable {
    let descriptor: VoxFlowASRCore.ASRProviderDescriptor
    let isUserSelectable: Bool
    let allowsModelDownload: Bool
    let canAdvertiseReady: Bool
}

struct ASRProviderEvaluationRegistry {
    private let candidates: [ASRProviderEvaluationCandidate]

    init(candidates: [ASRProviderEvaluationCandidate]? = nil) {
        AppLogger.general.debug("ASRProviderEvaluationRegistry init candidates=\(candidates?.count ?? 0)")
        self.candidates = candidates ?? [
            ASRProviderEvaluationCandidate(
                descriptor: NVIDIANemotronProviderDescriptor.current,
                isUserSelectable: false,
                allowsModelDownload: NVIDIANemotronModelMetadata.current.allowsModelDownload,
                canAdvertiseReady: NVIDIANemotronModelMetadata.current.canAdvertiseReady
            )
        ]
    }

    func allCandidates() -> [ASRProviderEvaluationCandidate] {
        AppLogger.general.debug("ASRProviderEvaluationRegistry allCandidates count=\(candidates.count)")
        return candidates
    }

    func candidate(id: String) -> ASRProviderEvaluationCandidate? {
        AppLogger.general.debug("ASRProviderEvaluationRegistry candidate lookup id=\(id)")
        return candidates.first { $0.descriptor.id.rawValue == id }
    }
}
