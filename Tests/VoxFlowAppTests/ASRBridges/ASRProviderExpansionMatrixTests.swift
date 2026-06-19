import VoxFlowASRCore
import XCTest
@testable import VoxFlowApp

final class ASRProviderExpansionMatrixTests: XCTestCase {
    func testTask11TargetsAllRequestedProviderVariants() {
        let variants = ASRProviderExpansionMatrix.task11Entries.map(\.variantID)

        XCTAssertEqual(
            Set(variants),
            [
                "qwen3-asr-0.6b",
                "qwen3-asr-1.7b",
                "whisper-large-v3",
                "nvidia-nemotron-asr-0.6b",
                "parakeet-eou-120m",
                "omnilingual-asr-300m",
                "funasr-fp32",
                "paraformer",
            ]
        )
    }

    func testEveryTask11EntryRequiresProductionReadinessAndSmokeGates() {
        for entry in ASRProviderExpansionMatrix.task11Entries {
            XCTAssertTrue(entry.requiresModelStoreLifecycle, entry.variantID)
            XCTAssertTrue(entry.requiresRuntimePrewarmCanary, entry.variantID)
            XCTAssertTrue(entry.requiresProviderLiveSmoke, entry.variantID)
            XCTAssertTrue(entry.requiresAppForegroundInputSmoke, entry.variantID)
        }
    }

    func testTask11StreamingSemanticsAreExplicitAndNeverDescriptorOnly() throws {
        let entries = Dictionary(
            uniqueKeysWithValues: ASRProviderExpansionMatrix.task11Entries.map { ($0.variantID, $0) }
        )

        XCTAssertEqual(
            try XCTUnwrap(entries["qwen3-asr-0.6b"]).streamingSemantics,
            .companionPartialFinal
        )
        XCTAssertEqual(
            try XCTUnwrap(entries["qwen3-asr-1.7b"]).streamingSemantics,
            .companionPartialFinal
        )
        XCTAssertEqual(try XCTUnwrap(entries["whisper-large-v3"]).streamingSemantics, .offlineFinalOnly)
        XCTAssertEqual(try XCTUnwrap(entries["nvidia-nemotron-asr-0.6b"]).streamingSemantics, .nativeStreaming)
        XCTAssertEqual(try XCTUnwrap(entries["parakeet-eou-120m"]).streamingSemantics, .nativeStreaming)
        XCTAssertEqual(try XCTUnwrap(entries["omnilingual-asr-300m"]).streamingSemantics, .offlineFinalOnly)
        XCTAssertEqual(try XCTUnwrap(entries["funasr-fp32"]).streamingSemantics, .rollingWindowConfirmedSegments)
        XCTAssertEqual(try XCTUnwrap(entries["paraformer"]).streamingSemantics, .rollingWindowConfirmedSegments)

        for entry in entries.values {
            XCTAssertFalse(entry.runtimeRoute.isEmpty, entry.variantID)
            XCTAssertFalse(entry.providerTargetName.isEmpty, entry.variantID)
            XCTAssertFalse(entry.modelStoreID.isEmpty, entry.variantID)
        }
    }

    func testExpansionMatrixIsDocumented() {
        XCTAssertEqual(
            ASRProviderExpansionMatrix.documentationPath,
            "docs/asr-provider-expansion-matrix.md"
        )
    }

    func testQwen17MatrixRecordsSpeechSwiftSharedModelAndSessionIsolation() throws {
        let qwen06 = try XCTUnwrap(
            ASRProviderExpansionMatrix.task11Entries.first { $0.variantID == "qwen3-asr-0.6b" }
        )
        let qwen17 = try XCTUnwrap(
            ASRProviderExpansionMatrix.task11Entries.first { $0.variantID == "qwen3-asr-1.7b" }
        )

        XCTAssertTrue(qwen06.runtimeRoute.contains("speech-swift"))
        XCTAssertTrue(qwen06.runtimeRoute.contains("shared"))
        XCTAssertTrue(qwen06.runtimeRoute.contains("isolated"))
        XCTAssertTrue(qwen17.runtimeRoute.contains("speech-swift"))
        XCTAssertTrue(qwen17.runtimeRoute.contains("shared"))
        XCTAssertTrue(qwen17.runtimeRoute.contains("isolated"))
        XCTAssertEqual(qwen06.status, .implemented)
        XCTAssertEqual(qwen17.status, .implemented)
    }

    func testTask11RowsAreImplementedAfterProviderWiringLands() {
        for entry in ASRProviderExpansionMatrix.task11Entries {
            XCTAssertEqual(entry.status, .implemented, entry.variantID)
        }
    }
}
