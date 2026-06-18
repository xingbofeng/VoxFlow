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

    func testProviderCardInteractionKeepsExternalLinksOutOfSelectionRegions() {
        let descriptor = ASRProviderDescriptor(
            id: ASRProviderID.qwenCloudASR,
            displayName: "通义千问 ASR",
            providerType: "qwenCloudASR",
            capabilities: [.streaming, .cloud],
            tags: ["在线"],
            isAvailable: false,
            isDefault: false,
            statusMessage: "需要配置 API 密钥",
            privacySummary: "在线识别",
            modelSize: nil,
            engineType: nil,
            externalLinks: ASRProviderExternalLinks(
                apiKeyURL: URL(string: "https://example.com/key")!,
                modelsURL: URL(string: "https://example.com/models")!
            )
        )
        let presentation = ASRProviderCardInteractionPresentation(provider: descriptor)

        XCTAssertEqual(presentation.cardTapBehavior, .ignore)
        XCTAssertFalse(presentation.handlesCardTap)
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

    func testProviderCardInteractionRoutesUnavailableTapToFeedback() {
        let unavailable = ASRProviderCardInteractionPresentation(
            provider: makeProvider(isAvailable: false, isDefault: false, localModelAction: .download)
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
        let scopeStart = try XCTUnwrap(source.range(of: "private var scopeFilterBar"))
        let tagStart = try XCTUnwrap(source.range(of: "private var tagBar"))
        let scopeSource = source[scopeStart.lowerBound..<tagStart.lowerBound]

        XCTAssertTrue(scopeSource.contains(".contentShape(Rectangle())"))
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
