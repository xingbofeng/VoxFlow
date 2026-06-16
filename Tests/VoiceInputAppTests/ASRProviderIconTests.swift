import XCTest
@testable import VoiceInputApp

final class ASRProviderIconTests: XCTestCase {
    func testBundledProviderIconsLoadAsTemplateImages() throws {
        let providerIDs = [
            ASRProviderID.whisper,
            ASRProviderID.paraformer,
        ]

        for providerID in providerIDs {
            let image = try XCTUnwrap(ASRProviderIcon.load(providerID: providerID))
            XCTAssertTrue(image.isTemplate, "\(providerID) icon must accept the app tint")
        }
    }

    func testProvidersWithoutReliableOfficialLogoUseTextBadges() {
        XCTAssertEqual(ASRProviderIcon.textBadge(providerID: ASRProviderID.funASR), "FA")
        XCTAssertEqual(ASRProviderIcon.textBadge(providerID: ASRProviderID.qwen3), "QW")
        XCTAssertEqual(ASRProviderIcon.textBadge(providerID: ASRProviderID.senseVoice), "SV")
        XCTAssertNil(ASRProviderIcon.textBadge(providerID: ASRProviderID.appleSpeech))
    }
}
