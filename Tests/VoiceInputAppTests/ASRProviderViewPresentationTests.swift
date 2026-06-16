import XCTest
@testable import VoiceInputApp

final class ASRProviderViewPresentationTests: XCTestCase {
    func testAppleProviderUsesAppleLogoSymbol() {
        XCTAssertEqual(
            ASRProviderIcon.systemSymbolName(providerID: ASRProviderID.appleSpeech),
            "apple.logo"
        )
    }

    func testProviderCardHasFullCardSelectionSurface() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoiceInputApp/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("cardSelectionSurface(provider)"))
        XCTAssertTrue(source.contains("Color.clear"))
    }

    func testProviderCardPrefersTextBadgeBeforeBundledImage() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoiceInputApp/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let badgeRange = try XCTUnwrap(source.range(of: "ASRProviderIcon.textBadge"))
        let imageRange = try XCTUnwrap(source.range(of: "ASRProviderIcon.load"))
        XCTAssertLessThan(badgeRange.lowerBound, imageRange.lowerBound)
    }
}
