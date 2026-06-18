import XCTest
@testable import VoxFlowApp

final class ASRProviderIconTests: XCTestCase {
    func testBundledProviderIconsLoadAsTemplateImages() throws {
        let providerIDs = [
            ASRProviderID.appleSpeech,
            ASRProviderID.assemblyAI,
            ASRProviderID.elevenLabsScribe,
            ASRProviderID.funASR,
            ASRProviderID.groqWhisper,
            ASRProviderID.mistralVoxtral,
            ASRProviderID.nvidiaNemotron,
            ASRProviderID.paraformer,
            ASRProviderID.qwen3,
            ASRProviderID.qwenCloudASR,
            ASRProviderID.senseVoice,
            ASRProviderID.volcengineDoubao,
            ASRProviderID.whisper,
        ]

        for providerID in providerIDs {
            let image = try XCTUnwrap(ASRProviderIcon.load(providerID: providerID))
            XCTAssertTrue(image.isTemplate, "\(providerID) icon must accept the app tint")
        }
    }

    func testBundledProviderIconsDoNotFallBackToTextBadges() {
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.appleSpeech))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.assemblyAI))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.elevenLabsScribe))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.funASR))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.groqWhisper))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.mistralVoxtral))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.nvidiaNemotron))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.paraformer))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.qwen3))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.qwenCloudASR))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.senseVoice))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.volcengineDoubao))
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.whisper))
    }

    func testAppleProviderDoesNotUseSystemSymbolWhenBundledIconExists() {
        XCTAssertNil(ASRProviderIcon.systemSymbolName(providerID: ASRProviderID.appleSpeech))
    }
}
