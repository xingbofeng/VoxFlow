import XCTest
@testable import VoxFlowApp

@MainActor
final class StyleConfigurationModalPresentationTests: XCTestCase {
    func testStyleConfigurationModalsCanCloseFromHeaderAndBackdrop() {
        XCTAssertTrue(StyleConfigurationModalPresentationPolicy.showsCloseButton)
        XCTAssertTrue(StyleConfigurationModalPresentationPolicy.dismissesOnBackdropTap)
        XCTAssertTrue(StyleConfigurationModalPresentationPolicy.dismissesOnEscapeKey)
    }

    func testAutoMatchDraftUsesSelectedProfileDescriptionOnFirstOpen() {
        let settings = StyleAutoMatchSettings(
            contextRounds: ContextRoundsSettings(enabled: false, maxRounds: 2, ttlHours: 12)
        )
        let profile = Self.profile(description: "适合代码评审和技术讨论")

        let draft = StyleAutoMatchSheetPresentation.makeDraft(
            from: profile,
            settings: settings
        )

        XCTAssertEqual(draft.description, "适合代码评审和技术讨论")
        XCTAssertFalse(draft.contextRoundsEnabled)
        XCTAssertEqual(draft.contextRounds, 2)
        XCTAssertEqual(draft.contextTTLHours, 12)
    }

    // MARK: - Helpers

    private static func profile(description: String?) -> StyleProfileRecord {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return StyleProfileRecord(
            id: "test.style",
            name: "测试风格",
            category: "work",
            subtitle: nil,
            mode: "conservative",
            prompt: "p",
            sampleInput: nil,
            sampleOutput: nil,
            llmProviderID: nil,
            model: nil,
            temperature: 0.2,
            enabled: true,
            builtIn: false,
            isDefault: false,
            createdAt: now,
            updatedAt: now,
            allowAutoMatch: true,
            autoMatchDescription: description
        )
    }
}
