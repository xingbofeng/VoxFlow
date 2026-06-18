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
        candidates
    }

    func candidate(id: String) -> ASRProviderEvaluationCandidate? {
        candidates.first { $0.descriptor.id.rawValue == id }
    }
}
