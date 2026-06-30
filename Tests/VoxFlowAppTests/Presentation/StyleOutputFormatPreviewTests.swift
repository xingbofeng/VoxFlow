import XCTest
@testable import VoxFlowApp

@MainActor
final class StyleOutputFormatPreviewTests: XCTestCase {
    func testPreviewSampleIsFullParagraph() {
        let sample = StyleOutputFormatPreviewText.sampleInput

        XCTAssertGreaterThan(sample.count, 40)
        XCTAssertTrue(sample.contains(" "))
    }

    func testPreviewOutputShowsAllFormatDimensions() {
        let output = StyleOutputFormatPreviewText.output(
            for: StyleOutputFormat(
                punctuation: .complete,
                capitalization: .normal,
                tone: .energetic,
                emoji: .required
            )
        )
        let restrained = StyleOutputFormatPreviewText.output(
            for: StyleOutputFormat(
                punctuation: .complete,
                capitalization: .normal,
                tone: .restrained,
                emoji: .required
            )
        )

        XCTAssertTrue(output.contains("Then I will"))
        XCTAssertNotEqual(output, restrained)
        XCTAssertTrue(output.contains("🎉"))
        XCTAssertTrue(output.hasSuffix("。") || output.hasSuffix("."))
    }

    func testPreviewOutputReflectsRelaxedLightPunctuationWithoutEmoji() {
        let output = StyleOutputFormatPreviewText.output(
            for: StyleOutputFormat(
                punctuation: .less,
                capitalization: .relaxed,
                tone: .natural,
                emoji: .none
            )
        )

        XCTAssertTrue(output.contains("then i will"))
        XCTAssertFalse(output.contains("🤣"))
        XCTAssertFalse(output.contains("😊"))
        XCTAssertFalse(output.hasSuffix("。"))
        XCTAssertFalse(output.hasSuffix("."))
    }

    func testRequiredEmojiPreviewAndLabelAreDistinctFromOptionalEmojiStyle() {
        let output = StyleOutputFormatPreviewText.output(
            for: StyleOutputFormat(
                punctuation: .less,
                capitalization: .normal,
                tone: .energetic,
                emoji: .required
            )
        )

        XCTAssertTrue(output.contains("🎉"))
        XCTAssertFalse(output.contains("🤣"))
        XCTAssertEqual(outputEmojiLabel(.required), L10n.localize("style.output_format.emoji.required", comment: ""))
        XCTAssertTrue(outputEmojiLabel(.required).contains("🤣"))
    }

    func testSummaryTextShowsAllFourOutputFormatControls() {
        let format = StyleOutputFormat(
            punctuation: .less,
            capitalization: .normal,
            tone: .energetic,
            emoji: .required
        )

        XCTAssertEqual(
            format.summaryText,
            [
                outputPunctuationLabel(.less),
                outputCapitalizationLabel(.normal),
                outputToneLabel(.energetic),
                outputEmojiLabel(.required),
            ].joined(separator: " · ")
        )
    }

    func testPromptRulesShowSelectedCombinationAsStructuredJSON() {
        let rules = StyleOutputFormat(
            punctuation: .less,
            capitalization: .normal,
            tone: .energetic,
            emoji: .required
        ).promptRules

        XCTAssertTrue(rules.contains(#""polished""#))
        XCTAssertTrue(rules.contains(#""corrections""#))
        XCTAssertTrue(rules.contains(#""key_terms""#))
        XCTAssertFalse(rules.contains("Output: I will"))
    }

    func testVisibleOutputFormatOptionsUseThreeLevelsInLowToHighInterventionOrder() {
        XCTAssertEqual(StyleOutputPunctuation.allCases, [.preserve, .less, .complete])
        XCTAssertEqual(StyleOutputCapitalization.allCases, [.preserve, .relaxed, .normal])
        XCTAssertEqual(StyleOutputTone.allCases, [.restrained, .natural, .energetic])
        XCTAssertEqual(StyleOutputEmoji.allCases, [.none, .natural, .required])
    }
}
