import Foundation
import XCTest
@testable import VoxFlowApp

/// Tests for ASRHotwordCapabilityMatrix — verifies each provider's support
/// mode, count limits, format, pruning, and unsupported reasons match
/// the research-decisions.md Provider 预研矩阵.
///
/// Covers tasks 6.1, 6.10, 6.11, 6.12 and quality gates 59, 60.
final class ASRHotwordCapabilityTests: XCTestCase {

    // MARK: - Task 6.1: Capability matrix per provider

    func testAppleSpeechUsesNativeHotwordWithContextualStrings() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .apple)
        XCTAssertEqual(cap.supportMode, .nativeHotword)
        XCTAssertTrue(cap.showsHotwordTag)
        XCTAssertFalse(cap.requiresConfiguration)

        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .apple,
            candidates: ["VoxFlow", "ContextBoost"]
        )
        XCTAssertEqual(payload.contextualStrings, ["VoxFlow", "ContextBoost"])
        XCTAssertEqual(payload.delivered.count, 2)
        XCTAssertEqual(payload.prunedCount, 0)
    }

    func testWhisperKitDoesNotAdvertiseHotwordUntilLivePromptIsFixed() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .whisper)
        XCTAssertEqual(cap.supportMode, .unsupported)
        XCTAssertFalse(cap.showsHotwordTag)
        XCTAssertEqual(cap.unsupportedReason, "whisper_prompt_empty_final")

        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .whisper,
            candidates: ["VoxFlow", "Qwen3-ASR"]
        )
        XCTAssertNil(payload.promptString)
        XCTAssertTrue(payload.delivered.isEmpty)
    }

    func testGroqWhisperUsesPromptContextWith224TokenBudget() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .groqWhisper)
        XCTAssertEqual(cap.supportMode, .promptContext)
        XCTAssertEqual(cap.maxBudget, 224)
        XCTAssertEqual(cap.budgetUnit, .tokens)

        // Chinese prompt budget must be conservative enough for Groq's 224-token limit.
        let candidates = (1...240).map { "热词\($0)" }
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .groqWhisper,
            candidates: candidates
        )
        XCTAssertLessThan(payload.delivered.count, candidates.count)
        XCTAssertGreaterThan(payload.prunedCount, 0)
        XCTAssertLessThanOrEqual(
            payload.delivered.reduce(0) { $0 + ASRHotwordCapability.estimateTokens($1) },
            224
        )
    }

    func testQwen3UsesPromptContextForContextParameter() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .qwen3)
        XCTAssertEqual(cap.supportMode, .promptContext)

        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .qwen3,
            candidates: ["VoxFlow", "speech-swift"]
        )
        XCTAssertEqual(payload.contextString, "VoxFlow, speech-swift")
    }

    func testNvidiaNemotronUsesNativeHotwordWithWordBoosting() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .nvidiaNemotron)
        XCTAssertEqual(cap.supportMode, .nativeHotword)

        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .nvidiaNemotron,
            candidates: ["ContextBoost", "Nemotron"]
        )
        XCTAssertEqual(payload.boostingPhrases, ["ContextBoost", "Nemotron"])
    }

    func testTencentCloudUsesNativeHotwordWithHotwordList() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .tencentCloud)
        XCTAssertEqual(cap.supportMode, .nativeHotword)
        XCTAssertEqual(cap.maxCount, 128)

        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .tencentCloud,
            candidates: ["VoxFlow"]
        )
        XCTAssertEqual(payload.hotwordList, ["VoxFlow|11"])
    }

    func testTencentCloudWeightsDecreaseByPriorityOrder() {
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .tencentCloud,
            candidates: ["最高优先", "第二优先", "第三优先", "普通优先", "最低优先"]
        )
        XCTAssertEqual(
            payload.hotwordList,
            ["最高优先|11", "第二优先|10", "第三优先|9", "普通优先|8", "最低优先|7"]
        )
    }

    func testTencentCloudFiltersTermsThatViolateDocumentedLengthLimits() {
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .tencentCloud,
            candidates: [
                "有效热词",
                String(repeating: "中", count: 11),
                String(repeating: "a", count: 31),
                "valid-latin-term",
            ]
        )
        XCTAssertEqual(payload.delivered, ["有效热词", "valid-latin-term"])
        XCTAssertEqual(payload.hotwordList, ["有效热词|11", "valid-latin-term|10"])
        XCTAssertEqual(payload.prunedCount, 2)
    }

    func testTencentCloudPrunesAt128() {
        let candidates = (1...200).map { "词\($0)" }
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .tencentCloud,
            candidates: candidates
        )
        XCTAssertEqual(payload.delivered.count, 128)
        XCTAssertEqual(payload.prunedCount, 72)
    }

    func testAliyunDashScopeUsesConfiguredVocabulary() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .aliyunDashScope)
        XCTAssertEqual(cap.supportMode, .configuredVocabulary)
        XCTAssertTrue(cap.requiresConfiguration)
        XCTAssertTrue(cap.showsHotwordTag)
    }

    func testAliyunDashScopeWithoutVocabularyIDRecordsReason() {
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .aliyunDashScope,
            candidates: ["VoxFlow"],
            hasVocabularyID: false
        )
        XCTAssertEqual(payload.unsupportedReason, "missing_vocabulary_id")
        XCTAssertEqual(payload.delivered.count, 0)
    }

    func testAliyunDashScopeWithVocabularyIDDelivers() {
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .aliyunDashScope,
            candidates: ["VoxFlow"],
            hasVocabularyID: true
        )
        XCTAssertNil(payload.unsupportedReason)
        XCTAssertEqual(payload.delivered.count, 1)
    }

    // MARK: - Task 6.9: Unsupported providers

    func testParakeetStreamingUnsupported() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .parakeetStreaming)
        XCTAssertEqual(cap.supportMode, .unsupported)
        XCTAssertFalse(cap.showsHotwordTag)
        XCTAssertEqual(cap.unsupportedReason, "provider_no_hotword_api")
    }

    func testOmnilingualASRUnsupported() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .omnilingualASR)
        XCTAssertEqual(cap.supportMode, .unsupported)
        XCTAssertFalse(cap.showsHotwordTag)
    }

    func testParaformerUnsupported() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .paraformer)
        XCTAssertEqual(cap.supportMode, .unsupported)
        XCTAssertFalse(cap.showsHotwordTag)
    }

    func testFunASRUnsupported() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .funASR)
        XCTAssertEqual(cap.supportMode, .unsupported)
        XCTAssertFalse(cap.showsHotwordTag)
    }

    func testSenseVoiceUnsupported() {
        let cap = ASRHotwordCapabilityMatrix.capability(for: .senseVoice)
        XCTAssertEqual(cap.supportMode, .unsupported)
        XCTAssertFalse(cap.showsHotwordTag)
    }

    // MARK: - Task 59: Unsupported providers don't fake support

    func testUnsupportedProviderPayloadHasEmptyDelivered() {
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .funASR,
            candidates: ["VoxFlow", "Qwen3-ASR"]
        )
        XCTAssertTrue(payload.delivered.isEmpty)
        XCTAssertEqual(payload.prunedCount, 2)
        XCTAssertNotNil(payload.unsupportedReason)
    }

    // MARK: - Task 60: Each supported provider's count and format tested

    func testTraceSummaryFormat() {
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .tencentCloud,
            candidates: (1...200).map { "词\($0)" }
        )
        XCTAssertTrue(payload.traceSummary.contains("候选 200"))
        XCTAssertTrue(payload.traceSummary.contains("下发 128"))
        XCTAssertTrue(payload.traceSummary.contains("剪枝 72"))
    }

    func testUnsupportedTraceSummary() {
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .parakeetStreaming,
            candidates: ["VoxFlow"]
        )
        XCTAssertTrue(payload.traceSummary.contains("未下发"))
        XCTAssertTrue(payload.traceSummary.contains("provider_no_hotword_api"))
    }

    // MARK: - Apple Speech secure field skip

    func testAppleSpeechPayloadRespectsSecureFieldAtCallSite() {
        // The capability matrix itself doesn't check secure field;
        // the call site (DictationOrchestrator) is responsible for skipping.
        // Here we verify the payload is buildable when candidates are provided.
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: .apple,
            candidates: ["VoxFlow"]
        )
        XCTAssertEqual(payload.contextualStrings, ["VoxFlow"])
    }
}
