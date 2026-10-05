import VoxFlowASRCore
@testable import VoxFlowProviderR2T2
import XCTest

final class R2T2ProviderDescriptorTests: XCTestCase {
    func testDescriptorUsesStablePrefixSemanticsAndDedicatedIdentifier() {
        let descriptor = R2T2ProviderDescriptor.descriptor(modelInstallationState: .notInstalled)

        XCTAssertEqual(descriptor.id, ASRProviderID(rawValue: "confucius4_r2t2"))
        XCTAssertEqual(descriptor.displayName, "Confucius4-R2T2")
        XCTAssertEqual(descriptor.modelInstallationState, .notInstalled)
        XCTAssertEqual(
            descriptor.streamingSemantics,
            .chunkedStablePrefix,
            "R2T2 是稳定前缀流式；不得沿用 Qwen3 的 companionPartialFinal"
        )
    }

    func testDescriptorFirstPhaseCoversChineseAndEnglishOnly() {
        let descriptor = R2T2ProviderDescriptor.descriptor(modelInstallationState: .ready)

        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW", "en-US"])
    }

    func testInstalledStateIsReflectedRatherThanMasked() {
        let descriptor = R2T2ProviderDescriptor.descriptor(
            modelInstallationState: .runtimeUnsupported(reason: "非 arm64")
        )

        XCTAssertEqual(descriptor.modelInstallationState, .runtimeUnsupported(reason: "非 arm64"))
    }
}

final class R2T2LanguageMapperTests: XCTestCase {
    func testChineseAndEnglishMapToUpstreamHints() {
        XCTAssertEqual(R2T2LanguageMapper.languageHint(for: .init(bcp47Tag: "zh-CN")), "zh")
        XCTAssertEqual(R2T2LanguageMapper.languageHint(for: .init(bcp47Tag: "zh-Hant-TW")), "zh")
        XCTAssertEqual(R2T2LanguageMapper.languageHint(for: .init(bcp47Tag: "en-US")), "en")
    }

    func testUnsupportedLanguageFallsBackToUpstreamAutoDetect() {
        XCTAssertNil(
            R2T2LanguageMapper.languageHint(for: .init(bcp47Tag: "ja-JP")),
            "首期只承诺中英；其余交给上游 auto-detect，而不是悄悄映射成中英"
        )
    }
}
