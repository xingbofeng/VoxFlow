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

    func testProviderViewKeepsScopeAndTagFiltersInOneToolbarWithoutFastAccurateRow() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("scopeAndTagFilterBar"))
        XCTAssertFalse(source.contains("\n            tagBar\n"))
        XCTAssertTrue(source.contains("ForEach(viewModel.availableTags"))
        XCTAssertTrue(source.contains("viewModel.toggleTag(tag)"))
    }

    func testCloudConfigurationFieldsAreMinimalAndHideOnlySecrets() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("TextField(\"Base URL\""))
        XCTAssertFalse(source.contains("TextField(\"识别引擎"))
        XCTAssertFalse(source.contains("TextField(\"识别模型"))
        XCTAssertTrue(source.contains(#"tencentCredentialField(L10n.localize("asr.provider.tencent.app_id""#))
        XCTAssertTrue(source.contains(#"tencentCredentialField(L10n.localize("asr.provider.tencent.secret_id""#))
        XCTAssertTrue(source.contains(#"tencentCredentialField(L10n.localize("asr.provider.tencent.secret_key""#))
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

    func testProviderCardPrefersBundledImageBeforeTextBadge() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let badgeRange = try XCTUnwrap(source.range(of: "ASRProviderIcon.textBadge"))
        let imageRange = try XCTUnwrap(source.range(of: "ASRProviderIcon.load"))
        XCTAssertLessThan(imageRange.lowerBound, badgeRange.lowerBound)
    }

    func testProviderCardsUseSingleColumnGrid() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("LazyVGrid(columns: providerColumns"))
        XCTAssertTrue(source.contains("GridItem(.flexible(), spacing: AppTheme.Spacing.grid)"))
        XCTAssertFalse(source.contains("GridItem(.flexible(), spacing: AppTheme.Spacing.grid),\n            GridItem(.flexible(), spacing: AppTheme.Spacing.grid)"))
    }

    func testProviderViewShowsLocalModelControlsForAllOfflineDownloadableProviders() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("provider.supportsLocalModelControls"))
        XCTAssertFalse(source.contains("provider.id == ASRProviderID.qwen3\n                || provider.id == ASRProviderID.funASR"))
    }

    func testProviderViewOffersCleanupButtonForDownloadableLocalModels() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(#"Label(L10n.localize("asr.provider.local_model.clean""#))
        XCTAssertTrue(source.contains("viewModel.deleteLocalModel(id: provider.id)"))
        XCTAssertTrue(source.contains(".disabled(viewModel.isDownloading && viewModel.downloadingProviderID != provider.id)"))
    }

    func testProviderViewShowsLocalModelSizeAndDownloadedBytes() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(#"Text(L10n.localize("asr.provider.local_model.size_label""#))
        XCTAssertTrue(source.contains("viewModel.localModelSizeSummary(providerID: provider.id)"))
        XCTAssertTrue(source.contains("progress.detailText"))
        XCTAssertTrue(source.contains("progress.modelSizeText"))
    }

    func testProviderViewOnlyShowsHeavyControlsInsideExpandedCards() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var expandedProviderID"))
        XCTAssertTrue(source.contains("let isExpanded = isProviderExpanded(provider)"))
        XCTAssertTrue(source.contains("if isExpanded {"))
        XCTAssertTrue(source.contains("private func isProviderExpanded"))
        XCTAssertTrue(source.contains("toggleExpandedProvider"))
    }

    func testDefaultProviderCardsDoNotAutoExpand() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("expandedProviderID == provider.id"))
        XCTAssertFalse(source.contains("provider.isDefault || expandedProviderID == provider.id"))
    }

    func testCollapsedProviderCardsHideTagsAndControlsUntilExpanded() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("if isExpanded {\n                providerTagsRow(provider"))
        XCTAssertTrue(source.contains("providerExpandedControls(provider)"))
        XCTAssertFalse(source.contains("expandedProviderID = provider.id\n                viewModel.selectDefaultProvider"))
    }

    func testCollapsedProviderCardsHideVerboseSummaryContent() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("providerSummary(provider, isExpanded: isExpanded)"))
        XCTAssertTrue(source.contains("private func providerSummary(_ provider: ASRProviderDescriptor, isExpanded: Bool)"))
        XCTAssertTrue(source.contains("if isExpanded {\n                Text(provider.privacySummary)"))
        XCTAssertTrue(source.contains("if isExpanded, let links = provider.externalLinks"))
    }

    func testProviderViewDoesNotRunQwenRuntimePreflightDuringRendering() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("ASRManager.isQwen3RuntimeSupported"))
    }

    func testProviderViewDoesNotReloadProvidersOnAppear() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains(".onAppear { viewModel.load() }"))
    }

    func testProviderScopeButtonsUseFullRectangularHitTargets() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let scopeStart = try XCTUnwrap(source.range(of: "private var scopeAndTagFilterBar"))
        let cardStart = try XCTUnwrap(source.range(of: "private func providerCard"))
        let scopeSource = source[scopeStart.lowerBound..<cardStart.lowerBound]

        XCTAssertTrue(scopeSource.contains(".contentShape(Rectangle())"))
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

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "ASRProviderViewPresentationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
