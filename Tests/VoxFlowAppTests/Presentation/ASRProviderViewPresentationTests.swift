import XCTest
@testable import VoxFlowApp

final class ASRProviderViewPresentationTests: XCTestCase {
    func testAppleProviderUsesBundledIcon() throws {
        XCTAssertNil(ASRProviderIcon.systemSymbolName(providerID: ASRProviderID.appleSpeech))
        XCTAssertNotNil(ASRProviderIcon.load(providerID: ASRProviderID.appleSpeech))
    }

    func testProviderCardHasFullCardSelectionSurface() {
        let descriptor = makeProvider(
            isAvailable: true,
            isDefault: false,
            localModelAction: .none
        )
        let presentation = ASRProviderCardInteractionPresentation(provider: descriptor)

        XCTAssertTrue(presentation.isSelectionEnabled)
        XCTAssertTrue(presentation.selectionPassthroughRegions.contains(.blank))
    }

    func testProviderCardInteractionTreatsHeaderAndTagsAsSelectionRegions() {
        let descriptor = makeProvider(
            isAvailable: true,
            isDefault: false,
            localModelAction: .none
        )
        let presentation = ASRProviderCardInteractionPresentation(provider: descriptor)

        XCTAssertTrue(presentation.isSelectionEnabled)
        XCTAssertEqual(
            presentation.selectionPassthroughRegions,
            [.icon, .name, .status, .tags, .blank]
        )
    }

    func testProviderCardInteractionKeepsModelControlsOutOfSelectionRegions() {
        let descriptor = makeProvider(
            isAvailable: true,
            isDefault: false,
            localModelAction: .repair
        )
        let presentation = ASRProviderCardInteractionPresentation(provider: descriptor)

        XCTAssertTrue(presentation.controlOnlyRegions.isSuperset(of: [
            .variantPicker,
            .downloadButton,
            .deleteButton,
            .repairButton,
        ]))
        XCTAssertFalse(presentation.selectionPassthroughRegions.contains(.variantPicker))
        XCTAssertFalse(presentation.selectionPassthroughRegions.contains(.repairButton))
    }

    func testProviderCardInteractionAllowsAvailableCloudProviderSelectionWithExternalLinks() {
        let descriptor = ASRProviderDescriptor(
            id: ASRProviderID.qwenCloudASR,
            displayName: "阿里云",
            providerType: "qwenCloudASR",
            capabilities: [.streaming, .cloud],
            tags: ["在线"],
            isAvailable: true,
            isDefault: false,
            statusMessage: "已配置",
            privacySummary: "在线识别",
            modelSize: nil,
            engineType: .aliyunDashScope,
            externalLinks: ASRProviderExternalLinks(
                apiKeyURL: URL(string: "https://example.com/key")!,
                modelsURL: URL(string: "https://example.com/models")!
            )
        )
        let presentation = ASRProviderCardInteractionPresentation(provider: descriptor)

        XCTAssertEqual(presentation.cardTapBehavior, .selectProvider)
        XCTAssertTrue(presentation.handlesCardTap)
        XCTAssertTrue(presentation.controlOnlyRegions.contains(.externalLinks))
        XCTAssertFalse(presentation.selectionPassthroughRegions.contains(.externalLinks))
    }

    func testProviderCardInteractionDisablesSelectionForUnavailableOrCurrentProvider() {
        let unavailable = ASRProviderCardInteractionPresentation(
            provider: makeProvider(isAvailable: false, isDefault: false, localModelAction: .download)
        )
        let current = ASRProviderCardInteractionPresentation(
            provider: makeProvider(isAvailable: true, isDefault: true, localModelAction: .none)
        )

        XCTAssertFalse(unavailable.isSelectionEnabled)
        XCTAssertFalse(current.isSelectionEnabled)
    }

    func testProviderCardInteractionIgnoresUnavailableTapWhenLocalModelActionExists() {
        let downloadable = ASRProviderCardInteractionPresentation(
            provider: makeProvider(isAvailable: false, isDefault: false, localModelAction: .download)
        )
        let repairable = ASRProviderCardInteractionPresentation(
            provider: makeProvider(isAvailable: false, isDefault: false, localModelAction: .repair)
        )

        XCTAssertEqual(downloadable.cardTapBehavior, .ignore)
        XCTAssertFalse(downloadable.handlesCardTap)
        XCTAssertEqual(repairable.cardTapBehavior, .ignore)
        XCTAssertFalse(repairable.handlesCardTap)
    }

    func testProviderCardInteractionRoutesUnactionableUnavailableTapToFeedback() {
        let unavailable = ASRProviderCardInteractionPresentation(
            provider: makeProvider(isAvailable: false, isDefault: false, localModelAction: .none)
        )
        let current = ASRProviderCardInteractionPresentation(
            provider: makeProvider(isAvailable: true, isDefault: true, localModelAction: .none)
        )

        XCTAssertEqual(unavailable.cardTapBehavior, .showUnavailableFeedback)
        XCTAssertTrue(unavailable.handlesCardTap)
        XCTAssertEqual(current.cardTapBehavior, .ignore)
        XCTAssertFalse(current.handlesCardTap)
    }

    func testProviderCardTagsUseStandardSingleLineVocabulary() {
        let descriptor = ASRProviderDescriptor(
            id: ASRProviderID.qwen3,
            displayName: "Qwen3-ASR",
            providerType: "qwen3",
            capabilities: [.streaming, .local, .accurate, .multilingual, .punctuation],
            tags: ["本地", "离线", "中文", "English", "ja-JP", "ko-KR", "1.7B", "CoreML", "非流式"],
            isAvailable: true,
            isDefault: false,
            statusMessage: "本地模型已就绪",
            privacySummary: "语音仅在本机处理，不会上传。",
            modelSize: .size1_7B,
            engineType: .qwen3
        )

        XCTAssertEqual(
            ASRProviderTagPresentation.cardTags(for: descriptor),
            ["离线", "流式", "准确", "中文", "英文", "多语言", "CoreML", "智能纠错"]
        )
    }

    func testAllProviderCardTagsStayInsideApprovedVocabulary() {
        let approvedTags: Set<String> = ["离线", "在线", "流式", "非流式", "快速", "准确", "中文", "英文", "多语言", "智能纠错", "CoreML"]

        let descriptors = [
            ASRProviderDescriptor(
                id: ASRProviderID.appleSpeech,
                displayName: "系统自带",
                providerType: "appleSpeech",
                capabilities: [.streaming, .fast, .multilingual, .punctuation],
                tags: ["系统", "流式", "多语言"],
                isAvailable: true,
                isDefault: true,
                statusMessage: "系统语音识别可用",
                privacySummary: "使用系统语音识别能力，可能依赖 Apple 服务。",
                modelSize: nil,
                engineType: .apple
            ),
            ASRProviderDescriptor(
                id: ASRProviderID.groqWhisper,
                displayName: "Groq",
                providerType: "groq",
                capabilities: [.fileTranscription, .cloud, .fast, .accurate],
                tags: ["在线", "非流式", "快速", "准确", "Whisper"],
                isAvailable: true,
                isDefault: false,
                statusMessage: "已配置",
                privacySummary: "在线识别",
                modelSize: nil,
                engineType: .groqWhisper
            ),
        ]

        for descriptor in descriptors {
            XCTAssertTrue(approvedTags.isSuperset(of: ASRProviderTagPresentation.cardTags(for: descriptor)))
        }
    }

    func testProviderCardTagsExposeNonStreamingCapability() {
        let descriptor = ASRProviderDescriptor(
            id: ASRProviderID.whisper,
            displayName: "Whisper",
            providerType: "whisper",
            capabilities: [.fileTranscription, .local, .accurate, .multilingual],
            tags: ["本地", "离线", "非流式", "多语言"],
            isAvailable: true,
            isDefault: false,
            statusMessage: "本地模型已就绪",
            privacySummary: "语音仅在本机处理，不会上传。",
            modelSize: nil,
            engineType: .whisper
        )

        XCTAssertEqual(
            ASRProviderTagPresentation.cardTags(for: descriptor),
            ["离线", "非流式", "准确", "多语言"]
        )
    }

    private func makeProvider(
        isAvailable: Bool,
        isDefault: Bool,
        localModelAction: ASRProviderLocalModelAction
    ) -> ASRProviderDescriptor {
        ASRProviderDescriptor(
            id: ASRProviderID.qwen3,
            displayName: "Qwen3-ASR",
            providerType: "qwen3",
            capabilities: [.streaming, .local],
            tags: ["本地", "离线"],
            isAvailable: isAvailable,
            localModelAction: localModelAction,
            isDefault: isDefault,
            statusMessage: "本地模型已就绪",
            privacySummary: "语音仅在本机处理，不会上传。",
            modelSize: .size0_6B,
            engineType: .qwen3
        )
    }

}
