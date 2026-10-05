import VoxFlowASRCore
@testable import VoxFlowProviderR2T2
import XCTest

final class R2T2ASRProviderTests: XCTestCase {
    private let modelURL = URL(fileURLWithPath: "/tmp/r2t2-provider", isDirectory: true)

    private func provider(
        state: ASRModelInstallationState = .ready,
        modelURL: URL? = nil,
        engine: any R2T2StreamingEngine = ScriptedR2T2Stream(pushResults: [], finishResult: "")
    ) -> R2T2ASRProvider {
        R2T2ASRProvider(
            descriptor: R2T2ProviderDescriptor.descriptor(modelInstallationState: state),
            modelURL: modelURL ?? self.modelURL,
            streamFactory: CapturingR2T2StreamFactory(engine: engine)
        )
    }

    func testPrepareSucceedsForAReadyInstalledModel() async throws {
        try await provider().prepare()
    }

    func testMissingModelURLIsReportedAsNotInstalledRatherThanCrashing() async {
        let provider = R2T2ASRProvider(
            descriptor: R2T2ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: nil,
            streamFactory: CapturingR2T2StreamFactory(
                engine: ScriptedR2T2Stream(pushResults: [], finishResult: "")
            )
        )

        await XCTAssertThrowsErrorAsync { try await provider.prepare() }
        let health = await provider.healthCheck()
        XCTAssertEqual(health, .unhealthy(ASRError(
            category: .modelNotInstalled,
            message: R2T2ProviderError.modelNotInstalled.localizedDescription
        )))
    }

    func testEachInstallationStateMapsToItsOwnProviderError() async {
        let cases: [(ASRModelInstallationState, ASRErrorCategory)] = [
            (.notInstalled, .modelNotInstalled),
            (.downloading(progress: 0.4), .modelNotInstalled),
            (.verifying, .modelNotInstalled),
            (.compiling, .modelNotInstalled),
            (.prewarming, .modelNotInstalled),
            (.corrupt, .modelCorrupt),
            (.runtimeUnsupported(reason: "非 arm64"), .runtimeUnsupported),
            (.hardwareUnsupported(reason: "内存不足"), .hardwareUnsupported),
            (.failed(message: "加载失败"), .preparationFailed),
        ]

        for (state, expectedCategory) in cases {
            let health = await provider(state: state).healthCheck()
            guard case .unhealthy(let error) = health else {
                XCTFail("\(state) 应报告为不健康")
                continue
            }
            XCTAssertEqual(error.category, expectedCategory, "\(state) 的分类不对")
        }
    }

    func testMakeSessionForwardsTheMappedLanguageHintAndTheInstalledRoot() async throws {
        let engine = ScriptedR2T2Stream(pushResults: [], finishResult: "")
        let factory = CapturingR2T2StreamFactory(engine: engine)
        let provider = R2T2ASRProvider(
            descriptor: R2T2ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: modelURL,
            streamFactory: factory
        )

        let session = try await provider.makeSession(
            language: ASRLanguageCapability(bcp47Tag: "zh-Hant-TW")
        )
        try await session.start()

        XCTAssertEqual(factory.modelURLs, [modelURL])
        XCTAssertEqual(factory.languageHints, ["zh"])
    }

    func testInstallAndDeleteAreDelegatedToModelStoreInsteadOfBeingReimplemented() async {
        await XCTAssertThrowsErrorAsync { try await self.provider().install() }
        await XCTAssertThrowsErrorAsync { try await self.provider().delete() }
    }

    func testSessionIdentifiersAreUniquePerSession() async throws {
        let provider = provider()

        let first = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let second = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))

        XCTAssertNotEqual(first.sessionID, second.sessionID)
    }
}
