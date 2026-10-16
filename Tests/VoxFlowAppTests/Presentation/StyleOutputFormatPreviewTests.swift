import XCTest
import VoxFlowTextProcessing
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

    // MARK: - Preview consistency with the deterministic pipeline

    func testPreviewPunctuationPolicyMatchesDeterministicPipelineForLess() {
        // less -> noEnding: the preview must strip ordinary ending
        // punctuation exactly like StyleOutputFormatter does in the pipeline.
        let text = "This afternoon I will align the login flow and API response."
        let pipelineOutput = StyleOutputFormatter.process(
            text,
            policy: StyleOutputPunctuation.less.deterministicPolicy.map {
                StyleOutputFormatPolicy(punctuation: $0)
            } ?? StyleOutputFormatPolicy()
        )

        let previewOutput = StyleOutputFormatPreviewText.applyPunctuationPolicy(.less, to: text)

        XCTAssertEqual(previewOutput, pipelineOutput)
        XCTAssertFalse(previewOutput.hasSuffix("."), "less 预览应剥掉句号，与管线 noEnding 行为一致")
    }

    func testPreviewPunctuationPolicyPreserveKeepsTextUntouched() {
        // preserve keeps user punctuation: the preview must not strip the
        // ending period (previously it wrongly shared the noEnding path).
        let text = "I will check the API response."

        let previewOutput = StyleOutputFormatPreviewText.applyPunctuationPolicy(.preserve, to: text)

        XCTAssertEqual(previewOutput, text, "preserve 预览不应改动用户标点")
    }

    func testPreviewPunctuationPolicyCompleteAppendsEndingMark() {
        let text = "I will check the API response"

        let previewOutput = StyleOutputFormatPreviewText.applyPunctuationPolicy(.complete, to: text)

        XCTAssertTrue(
            previewOutput.hasSuffix(".") || previewOutput.hasSuffix("。"),
            "complete 预览应补齐句末标点"
        )
    }
}
