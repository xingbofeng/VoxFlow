import XCTest
@testable import VoxFlowApp

final class VoiceCorrectionViewPresentationTests: XCTestCase {
    func testAutomaticLearningFeedbackUsesStandardVisibleOverlay() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("message: viewModel.lastActionMessage"))
        XCTAssertFalse(source.contains("VoiceCorrectionToastView"))
    }

    func testNavigationContainsTopLevelVoiceCorrectionTab() {
        XCTAssertTrue(NavigationRoute.allCases.contains(.voiceCorrection))
        XCTAssertEqual(NavigationRoute.voiceCorrection.title, "词汇表")
        XCTAssertEqual(NavigationRoute.voiceCorrection.systemImage, "text.badge.checkmark")
    }

    func testVoiceCorrectionViewFocusesOnVocabularyHotwordsAndTextReplacement() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("correction.view.description"))
        XCTAssertTrue(source.contains("vocabularyTabs"))
        XCTAssertTrue(source.contains("hotwordPanel"))
        XCTAssertTrue(source.contains("vocabulary.hotwords.input_placeholder"))
        XCTAssertTrue(source.contains("vocabulary.hotwords.file_button"))
        XCTAssertTrue(source.contains("learningDrawer"))
        XCTAssertTrue(source.contains("textReplacementPanel"))
        XCTAssertTrue(source.contains("vocabulary.text_replacement.modal.trigger"))
        XCTAssertTrue(source.contains("vocabulary.text_replacement.modal.replacement"))
        XCTAssertFalse(source.contains("规则列表"))
        XCTAssertFalse(source.contains("原文"))
        XCTAssertFalse(source.contains("待确认候选"))
        XCTAssertFalse(source.contains("学习候选"))
        XCTAssertFalse(source.contains("Shadow Mode"))
        XCTAssertFalse(source.contains("启用易错词修正"))
        XCTAssertFalse(source.contains("自动学习直接生效"))
        XCTAssertFalse(source.contains("Benchmark"))
        XCTAssertFalse(source.contains("匹配策略"))
    }

    func testVoiceCorrectionSettingsMovedToSettingsPage() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("settings.task.easy_word.title"))
        XCTAssertTrue(source.contains("settings.task.easy_word.enable.title"))
        XCTAssertTrue(source.contains("settings.task.easy_word.auto_learning.title"))
        XCTAssertTrue(source.contains("settings.task.easy_word.auto_learning_immediate.title"))
        XCTAssertTrue(source.contains("settings.task.easy_word.shadow_mode.title"))
    }

    // MARK: - Task 5.7: No "误听写法" main entry; text replacement terminology

    func testVocabularyCenterLocalizationKeysExist() {
        XCTAssertEqual(L10n.localize("vocabulary.tab.hotwords", comment: ""), "热词")
        XCTAssertEqual(L10n.localize("vocabulary.tab.text_replacement", comment: ""), "文本替换")
        XCTAssertEqual(L10n.localize("vocabulary.text_replacement.modal.trigger", comment: ""), "触发词")
        XCTAssertEqual(L10n.localize("vocabulary.text_replacement.modal.replacement", comment: ""), "替换为")
        XCTAssertEqual(L10n.localize("vocabulary.text_replacement.modal.regex", comment: ""), "RegEx")
        XCTAssertEqual(L10n.localize("vocabulary.hotwords.toast.duplicate", comment: ""), "热词已存在")
        XCTAssertEqual(L10n.localize("vocabulary.learning.drawer_title", comment: ""), "自动学习建议")
        XCTAssertEqual(L10n.localize("vocabulary.learning.action.collapse", comment: ""), "收起自动学习建议")
        XCTAssertEqual(L10n.localize("vocabulary.learning.action.expand", comment: ""), "展开自动学习建议")
        XCTAssertEqual(L10n.localize("vocabulary.learning.toast.accepted", comment: ""), "已加入热词")
    }

    func testVocabularyCenterUsesHotwordTabsChipsAndLearningDrawer() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("VoiceCorrectionVocabularyTab.allCases"))
        XCTAssertTrue(source.contains("selectedVocabularyTab"))
        XCTAssertTrue(source.contains("HotwordChip"))
        XCTAssertTrue(source.contains("filteredHotwordRows"))
        XCTAssertTrue(source.contains("LearningCandidateRow"))
        XCTAssertTrue(source.contains("acceptLearningCandidate"))
        XCTAssertTrue(source.contains("ignoreLearningCandidate"))
        XCTAssertTrue(source.contains("VoiceCorrectionReplacementPopover"))
        XCTAssertTrue(source.contains("hitCountText"))

        let viewModelSourceURL = sourceURL.deletingLastPathComponent().appendingPathComponent("VoiceCorrectionViewModel.swift")
        let viewModelSource = try String(contentsOf: viewModelSourceURL, encoding: .utf8)
        XCTAssertTrue(viewModelSource.contains("vocabulary.hotwords.hit_count_format"))
    }

    func testLearningDrawerToggleUsesDisclosureIcon() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/VoiceCorrection/UI/VoiceCorrectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(#""chevron.up""#))
        XCTAssertTrue(source.contains(#""chevron.down""#))
        XCTAssertTrue(source.contains("vocabulary.learning.action.collapse"))
        XCTAssertTrue(source.contains("vocabulary.learning.action.expand"))
        XCTAssertFalse(source.contains(#"isLearningDrawerPresented ? "xmark" : "chevron.left""#))
    }

    func testProcessingChainLocalizationKeysExist() {
        XCTAssertEqual(L10n.localize("transcription.detail.processing_chain", comment: ""), "处理链路")
        XCTAssertEqual(L10n.localize("transcription.detail.text_replacement_section", comment: ""), "文本替换")
        XCTAssertEqual(L10n.localize("transcription.detail.text_replacement_position", comment: ""), "LLM 后、上屏前")
    }

    func testHomeDashboardUsesTextReplacementNotEasyWord() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowApp/Views/HomeDashboardView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("home.detail.trace.pipeline_title"))
        XCTAssertTrue(source.contains("home.detail.voice_correction.title"))
        XCTAssertFalse(source.contains("\"易错词规则\""))
        XCTAssertFalse(source.contains("\"文本纠错过程\""))
    }
}
