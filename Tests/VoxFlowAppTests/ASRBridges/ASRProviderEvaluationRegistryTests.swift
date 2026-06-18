import XCTest
@testable import VoxFlowApp

final class ASRProviderEvaluationRegistryTests: XCTestCase {
    func testNVIDIANemotronKeepsEvaluationMetadataAndIsFormalProvider() throws {
        let evaluationRegistry = ASRProviderEvaluationRegistry()

        let candidate = try XCTUnwrap(evaluationRegistry.candidate(id: ASRProviderID.nvidiaNemotron))

        XCTAssertEqual(candidate.descriptor.displayName, "NVIDIA Nemotron ASR 0.6B")
        XCTAssertEqual(candidate.descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"])
        XCTAssertFalse(candidate.isUserSelectable)
        XCTAssertFalse(candidate.allowsModelDownload)
        XCTAssertFalse(candidate.canAdvertiseReady)
        XCTAssertTrue(candidate.descriptor.modelInstallationState.isUnsupported)

        let formalRegistry = ASRProviderRegistry(asrManager: ASRManager(defaults: isolatedDefaults()))
        let formalDescriptor = try XCTUnwrap(formalRegistry.descriptor(id: ASRProviderID.nvidiaNemotron))
        XCTAssertEqual(formalDescriptor.displayName, "NVIDIA Nemotron ASR 0.6B")
        XCTAssertEqual(formalDescriptor.localModelAction, .download)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "test.ASRProviderEvaluationRegistry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
