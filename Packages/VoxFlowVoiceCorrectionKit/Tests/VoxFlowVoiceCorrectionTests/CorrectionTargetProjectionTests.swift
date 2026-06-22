import Foundation
import Testing
@testable import VoxFlowVoiceCorrection

@Suite("Correction target projection")
struct CorrectionTargetProjectionTests {
    @Test("groups aliases by explicit target")
    func groupsAliasesByExplicitTarget() {
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let target = CorrectionTargetTerm(id: targetID, text: "Qwen")
        let rules = [
            makeRule(original: "q 问", replacement: "Qwen", targetID: targetID, appliedCount: 2),
            makeRule(original: "queue win", replacement: "Qwen", targetID: targetID, appliedCount: 3)
        ]

        let projections = CorrectionTargetProjection.build(targets: [target], rules: rules)

        #expect(projections.count == 1)
        #expect(projections.first?.target.text == "Qwen")
        #expect(projections.first?.aliases.map(\.original) == ["q 问", "queue win"])
        #expect(projections.first?.aliasPreview == "q 问、queue win")
        #expect(projections.first?.appliedCount == 5)
    }

    @Test("builds fallback targets for legacy rules without target identifiers")
    func buildsFallbackTargetsForLegacyRules() {
        let rules = [
            makeRule(original: "q 问", replacement: "Qwen"),
            makeRule(original: "Q问", replacement: "Qwen"),
            makeRule(original: "vox flow", replacement: "VoxFlow")
        ]

        let projections = CorrectionTargetProjection.build(targets: [], rules: rules)

        #expect(projections.map(\.target.text) == ["Qwen", "VoxFlow"])
        #expect(projections.first?.aliases.map(\.original) == ["q 问", "Q问"])
    }

    private func makeRule(
        original: String,
        replacement: String,
        targetID: UUID? = nil,
        appliedCount: Int = 0
    ) -> CorrectionRule {
        CorrectionRule(
            id: UUID(),
            targetID: targetID,
            original: original,
            replacement: replacement,
            appliedCount: appliedCount,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
