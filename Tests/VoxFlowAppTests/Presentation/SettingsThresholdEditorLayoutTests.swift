import XCTest
@testable import VoxFlowApp
@testable import VoxFlowTextProcessing

final class SettingsThresholdEditorLayoutTests: XCTestCase {
    func testThresholdEditorUsesSideBySideLayoutWithoutInternalScrolling() {
        XCTAssertTrue(SettingsThresholdEditorLayout.usesSideBySideInteraction)
        XCTAssertFalse(SettingsThresholdEditorLayout.showsInternalScrollIndicators)
        XCTAssertFalse(SettingsThresholdEditorLayout.hasFooterAction)
        XCTAssertTrue(SettingsThresholdEditorLayout.hasControlsPaneResetAction)
        XCTAssertGreaterThanOrEqual(
            SettingsThresholdEditorLayout.preferredModalWidth,
            SettingsThresholdEditorLayout.controlsPaneWidth
                + SettingsThresholdEditorLayout.examplesPaneMinWidth
                + SettingsThresholdEditorLayout.contentSpacing
                + SettingsThresholdEditorLayout.horizontalPadding * 2
        )
    }

    func testThresholdEditorWidthsPreventCompressedContent() {
        XCTAssertGreaterThanOrEqual(SettingsThresholdEditorLayout.controlsPaneWidth, 420)
        XCTAssertGreaterThanOrEqual(SettingsThresholdEditorLayout.examplesPaneMinWidth, 340)
        XCTAssertLessThanOrEqual(SettingsThresholdEditorLayout.preferredModalWidth, 1_120)
    }

    func testLongSentenceChinesePreviewRespondsToCJKThresholdChanges() {
        let lowThreshold = SettingsThresholdPreviewSamples.longSentenceChinesePreview(cjkThreshold: 10)
        let highThreshold = SettingsThresholdPreviewSamples.longSentenceChinesePreview(cjkThreshold: 80)

        XCTAssertGreaterThan(lineCount(in: lowThreshold), lineCount(in: highThreshold))
    }

    func testLongSentenceEnglishPreviewRespondsToWordThresholdChanges() {
        let lowThreshold = SettingsThresholdPreviewSamples.longSentenceEnglishPreview(wordThreshold: 5)
        let highThreshold = SettingsThresholdPreviewSamples.longSentenceEnglishPreview(wordThreshold: 80)

        XCTAssertGreaterThan(lineCount(in: lowThreshold), lineCount(in: highThreshold))
    }

    func testPunctuationEnglishPreviewRespondsToWordThresholdChanges() {
        let lowThreshold = SettingsThresholdPreviewSamples.punctuationEnglishPreview(wordThreshold: 1)
        let highThreshold = SettingsThresholdPreviewSamples.punctuationEnglishPreview(wordThreshold: 20)

        XCTAssertTrue(lowThreshold.contains(","))
        XCTAssertTrue(lowThreshold.contains(";"))
        XCTAssertTrue(lowThreshold.hasSuffix("."))
        XCTAssertFalse(highThreshold.hasSuffix("."))
    }

    func testPunctuationChinesePreviewRespondsToCJKThresholdChanges() {
        let lowThreshold = SettingsThresholdPreviewSamples.punctuationChinesePreview(cjkThreshold: 1)
        let highThreshold = SettingsThresholdPreviewSamples.punctuationChinesePreview(cjkThreshold: 20)

        XCTAssertTrue(lowThreshold.contains("，"))
        XCTAssertTrue(lowThreshold.contains("；"))
        XCTAssertTrue(lowThreshold.hasSuffix("？"))
        XCTAssertTrue(highThreshold.contains(","))
        XCTAssertTrue(highThreshold.contains(";"))
        XCTAssertTrue(highThreshold.hasSuffix("?"))
    }

    func testSettingsPreviewUsesSharedDeterministicPreviewEngine() {
        let punctuation = DeterministicTextPreviewEngine.preview(
            SettingsThresholdPreviewSamples.punctuationChinese,
            processor: .punctuationOptimization,
            settings: .init(
                enabled: true,
                punctuationCJKThreshold: 1,
                punctuationWordThreshold: 20
            )
        )
        XCTAssertEqual(
            punctuation,
            SettingsThresholdPreviewSamples.punctuationChinesePreview(cjkThreshold: 1)
        )

        let longSentence = DeterministicTextPreviewEngine.preview(
            SettingsThresholdPreviewSamples.longSentenceChinese,
            processor: .longSentenceBreaking,
            settings: .init(
                enabled: true,
                longSentenceWordThreshold: 80,
                longSentenceCJKThreshold: 10
            )
        )
        XCTAssertEqual(
            longSentence,
            SettingsThresholdPreviewSamples.longSentenceChinesePreview(cjkThreshold: 10)
        )
    }

    private func lineCount(in text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
