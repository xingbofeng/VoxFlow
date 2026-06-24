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
        XCTAssertTrue(source.contains("最近资产"))
        XCTAssertTrue(source.contains("动作"))
        XCTAssertTrue(source.contains("⌘"))
        XCTAssertTrue(source.contains("K"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"k\", modifiers: .command)"))
        XCTAssertTrue(source.contains("actionMenu"))
        XCTAssertTrue(source.contains("actionMenuRow"))
        XCTAssertTrue(source.contains("typeFilterMenu"))
        XCTAssertTrue(source.contains("typeFilterPanel"))
        XCTAssertTrue(source.contains("assetPreviewPane"))
        XCTAssertTrue(source.contains("RightClickActionView"))
        XCTAssertFalse(source.contains(".popover(isPresented: $viewModel.isActionPanelPresented"))
        XCTAssertFalse(source.contains(".contextMenu"))
        XCTAssertFalse(source.contains("Ask AI"))
        XCTAssertFalse(source.contains("Tab"))
    }

    func testPaletteListsScrollSelectedRowsIntoViewForKeyboardWraparound() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Palette/PaletteView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("ScrollViewReader"))
        XCTAssertTrue(source.contains("scrollHomeSelectionIntoView"))
        XCTAssertTrue(source.contains("scrollAssetSelectionIntoView"))
        XCTAssertTrue(source.contains("result.id,"))
        XCTAssertTrue(source.contains("asset.id,"))
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
        XCTAssertTrue(source.contains("await DictationTargetActivation.activate(previousTarget)"))
        XCTAssertTrue(source.contains("handleKeyDown"))
        XCTAssertTrue(source.contains("keyCode == 53"))
        XCTAssertFalse(source.contains("NSApp.activate(ignoringOtherApps: true)"))
    }

    func testPaletteShortcutTogglesVisiblePanelInsteadOfOpeningMainWindow() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("paletteWindowController?.isVisible == true"))
        XCTAssertTrue(source.contains("paletteWindowController?.close()"))
        XCTAssertTrue(source.contains("paletteWindowController?.present()"))
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

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
