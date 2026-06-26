import XCTest
@testable import VoxFlowApp

final class PaletteViewLayoutTests: XCTestCase {
    func testPaletteViewUsesRaycastStyleLauncherAndAssetsSecondLevel() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("struct PaletteView"))
        XCTAssertTrue(source.contains("搜索应用、命令、资产..."))
        XCTAssertTrue(source.contains("搜索资产..."))
        XCTAssertTrue(source.contains(".frame(width: 760, height: 470)"))
        XCTAssertTrue(source.contains("footerSelectionLabel"))
        XCTAssertTrue(source.contains("footerSelectionTitle"))
        XCTAssertTrue(source.contains("最喜欢"))
        XCTAssertTrue(source.contains("建议"))
        XCTAssertTrue(source.contains("还没有固定项目"))
        XCTAssertTrue(source.contains("动作"))
        XCTAssertTrue(source.contains("⌘"))
        XCTAssertTrue(source.contains("K"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"k\", modifiers: .command)"))
        XCTAssertTrue(source.contains("actionMenu"))
        XCTAssertTrue(source.contains("actionMenuRow"))
        XCTAssertTrue(source.contains("rootActionMenuRow"))
        XCTAssertTrue(source.contains("onOpenApplication"))
        XCTAssertTrue(source.contains("typeFilterMenu"))
        XCTAssertTrue(source.contains("typeFilterPanel"))
        XCTAssertTrue(source.contains("assetPreviewPane"))
        XCTAssertTrue(source.contains("RightClickActionView"))
        XCTAssertFalse(source.contains(".popover(isPresented: $viewModel.isActionPanelPresented"))
        XCTAssertFalse(source.contains(".contextMenu"))
        XCTAssertFalse(source.contains("Ask AI"))
        XCTAssertFalse(source.contains("Tab"))
    }

    func testRootActionCopyMatchesFirstPhaseDesign() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteRootItem.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("case open"))
        XCTAssertTrue(source.contains("加入最喜欢"))
        XCTAssertTrue(source.contains("从最喜欢移除"))
        XCTAssertTrue(source.contains("return [\"⇧\", \"⌘\", \"F\"]"))
        XCTAssertTrue(source.contains("return [\"↩\"]"))
    }

    func testPaletteListsScrollSelectedRowsIntoViewForKeyboardWraparound() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("ScrollViewReader"))
        XCTAssertTrue(source.contains("scrollHomeSelectionIntoView"))
        XCTAssertTrue(source.contains("scrollAssetSelectionIntoView"))
        XCTAssertTrue(source.contains("item.id,"))
        XCTAssertTrue(source.contains("asset.id,"))
    }

    func testPaletteHomeSearchRefreshesSelectionWhenFirstResultIdentityChanges() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".id(viewModel.homeResultListIdentity)"))
        XCTAssertTrue(source.contains("let isSelected = viewModel.selectedHomeResultIndex == index"))
        XCTAssertFalse(source.contains("viewModel.isRootItemSelected(item)"))
        XCTAssertFalse(source.contains(".onChange(of: viewModel.selectedRootItemID)"))
        XCTAssertFalse(source.contains(".id(viewModel.selectedRootItemID)"))
    }

    func testPaletteSelectedRowsUseVisibleHighlightWithoutPressedOnlyHighlight() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("PaletteRowSelectionHighlight(isSelected: isSelected)"))
        XCTAssertTrue(source.contains("let isSelected = viewModel.selectedHomeResultIndex == index"))
        XCTAssertTrue(source.contains("let isSelected = viewModel.selectedAssetIndex == index"))
        XCTAssertTrue(source.contains("Color.accentColor"))
        XCTAssertFalse(source.contains("PaletteRowButtonStyle(isSelected:"))
    }

    func testPaletteWindowControllerUsesFloatingPanel() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteWindowController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("final class PaletteWindowController"))
        XCTAssertTrue(source.contains("NSPanel"))
        XCTAssertTrue(source.contains("PalettePanel"))
        XCTAssertTrue(source.contains(".floating"))
        XCTAssertTrue(source.contains(".nonactivatingPanel"))
        XCTAssertTrue(source.contains("panel.hidesOnDeactivate = false"))
        XCTAssertTrue(source.contains("center()"))
        XCTAssertTrue(source.contains("orderFrontRegardless()"))
        XCTAssertTrue(source.contains("override func sendEvent"))
        XCTAssertTrue(source.contains("var isVisible: Bool"))
        XCTAssertTrue(source.contains("dismissOrGoBack()"))
        XCTAssertTrue(source.contains("addGlobalMonitorForEvents"))
        XCTAssertTrue(source.contains("localMouseMonitor"))
        XCTAssertTrue(source.contains("globalMouseMonitor"))
        XCTAssertTrue(source.contains("closeWhenClickingOutside"))
        XCTAssertTrue(source.contains("temporarilyHideForOriginalTargetAction"))
        XCTAssertTrue(source.contains("actionPanelShortcutAction"))
        XCTAssertTrue(source.contains("PaletteApplicationLaunching"))
        XCTAssertTrue(source.contains("WorkspacePaletteApplicationLauncher"))
        XCTAssertTrue(source.contains("performOpenApplication"))
        XCTAssertTrue(source.contains("recordRootActivation"))
        XCTAssertTrue(source.contains("rootActionPanelShortcutAction"))
        XCTAssertTrue(source.contains("key == \"f\""))
        XCTAssertTrue(source.contains("viewModel.requestSearchFocus()"))
        XCTAssertTrue(source.contains("await DictationTargetActivation.activate(previousTarget)"))
        XCTAssertTrue(source.contains("handleKeyDown"))
        XCTAssertTrue(source.contains("keyCode == 53"))
        XCTAssertFalse(source.contains("NSApp.activate(ignoringOtherApps: true)"))
    }

    func testFailedApplicationLaunchDoesNotRecordUsageOrClosePalette() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteWindowController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func performOpenApplication\(path: String, itemID: PaletteRootItemID\) \{[\s\S]*?\n    \}"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("if applicationLauncher.openApplication(atPath: path)"))
        XCTAssertTrue(method.contains("viewModel.recordRootActivation(itemID: itemID)"))
        XCTAssertTrue(method.contains("close()"))
        XCTAssertFalse(method.contains("else"))
    }

    func testPaletteSearchFieldReceivesExplicitFocusRequests() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("@FocusState private var isSearchFocused"))
        XCTAssertTrue(source.contains(".focused($isSearchFocused)"))
        XCTAssertTrue(source.contains("focusSearchField()"))
        XCTAssertTrue(source.contains(".onChange(of: viewModel.searchFocusRequestID)"))
        XCTAssertTrue(source.contains("await Task.yield()"))
        XCTAssertTrue(source.contains("Task.sleep(nanoseconds: 50_000_000)"))
        XCTAssertTrue(source.contains("return \"应用\""))
    }

    func testWebsiteIconsUseFaviconServiceAndHostPlaceholder() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("https://www.google.com/s2/favicons?domain="))
        XCTAssertTrue(source.contains("websiteIconPlaceholder(for: pageURL)"))
        XCTAssertTrue(source.contains("replacingOccurrences(of: \"www.\", with: \"\")"))
        XCTAssertFalse(source.contains("case .empty, .failure:\n                    Image(systemName: \"link\")"))
    }

    func testPaletteSearchResultsRenderQueryHighlights() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("PaletteHighlightedText"))
        XCTAssertTrue(source.contains("query: viewModel.searchText"))
        XCTAssertTrue(source.contains("matcher.highlight"))
        XCTAssertFalse(source.contains("matchedAliasSnippet"))
        XCTAssertFalse(source.contains("匹配 \\("))
    }

    func testPaletteAssetPreviewUsesScrollableCompactText() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("ScrollView(.vertical"))
        XCTAssertTrue(source.contains(".font(.system(size: 14))"))
        XCTAssertTrue(source.contains(".textSelection(.enabled)"))
        XCTAssertFalse(source.contains(".frame(maxWidth: .infinity, maxHeight: 210, alignment: .topLeading)"))
    }

    func testPaletteShortcutTogglesVisiblePanelInsteadOfOpeningMainWindow() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("paletteWindowController?.isVisible == true"))
        XCTAssertTrue(source.contains("paletteWindowController?.close()"))
        XCTAssertTrue(source.contains("paletteWindowController?.present()"))
        XCTAssertTrue(source.contains("applicationProvider: FileSystemInstalledApplicationProvider()"))
    }

    func testPaletteVoiceCommandsUseToggleVoiceActionInsteadOfOneShotPress() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func handlePaletteCommand\(_ command: PaletteCommand\) \{[\s\S]*?\n    private func togglePaletteVoiceAction"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("togglePaletteVoiceAction(.dictation)"))
        XCTAssertTrue(method.contains("togglePaletteVoiceAction(.agentCompose)"))
        XCTAssertTrue(method.contains("togglePaletteVoiceAction(.agentDispatch)"))
        XCTAssertFalse(method.contains("dictationFeatureController.handlePress(action: .dictation)"))
        XCTAssertTrue(source.contains("dictationFeatureController.handleRelease(action: action)"))
        XCTAssertTrue(source.contains("dictationFeatureController.handlePress(action: action)"))
    }

    func testPaletteStartDictationAlwaysStartsPlainDictation() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func handlePaletteCommand\(_ command: PaletteCommand\) \{[\s\S]*?\n    private func togglePaletteVoiceAction"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("togglePaletteVoiceAction(.dictation)"))
        XCTAssertFalse(method.contains("togglePaletteVoiceAction(primaryPaletteVoiceAction())"))
    }

    func testPaletteTranslateRoutesInputTextToSelectionResultPanel() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("onTranslate: { [weak self] text in"))
        XCTAssertTrue(source.contains("self?.handlePaletteTranslate(text: text)"))
        XCTAssertTrue(source.contains("private func handlePaletteTranslate(text: String)"))
        XCTAssertTrue(source.contains("selectionResultPanelController.present("))
        XCTAssertTrue(source.contains("operation: .translation"))
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
