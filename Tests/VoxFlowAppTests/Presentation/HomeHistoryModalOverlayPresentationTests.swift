import XCTest

final class HomeHistoryModalOverlayPresentationTests: XCTestCase {
    func testUnifiedHomeDetailOverlayIsHostedByMainShellInsteadOfDashboardContent() throws {
        let root = try Self.repositoryRoot()
        let shellSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/MainShellView.swift"),
            encoding: .utf8
        )
        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/HomeDashboardView.swift"),
            encoding: .utf8
        )
        let dashboardBody = try XCTUnwrap(
            dashboardSource.components(separatedBy: "private struct HomeActivityCard").first
        )

        XCTAssertTrue(shellSource.contains("if let detail = homeViewModel.selectedHomeDetail"))
        XCTAssertTrue(shellSource.contains("HomeDetailOverlay(viewModel: homeViewModel, detail: detail)"))
        XCTAssertFalse(shellSource.contains("HomeHistoryDetailOverlay("))
        XCTAssertFalse(shellSource.contains("HomeAssetDetailOverlay("))
        XCTAssertFalse(dashboardBody.contains("HomeHistoryDetailOverlay("))
        XCTAssertFalse(dashboardBody.contains("HomeAssetDetailOverlay("))
    }

    func testHomeDashboardPrimaryListUsesAssetsSection() throws {
        let root = try Self.repositoryRoot()
        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/HomeDashboardView.swift"),
            encoding: .utf8
        )
        let dashboardBody = try XCTUnwrap(
            dashboardSource.components(separatedBy: "private struct HomeActivityCard").first
        )

        XCTAssertTrue(dashboardBody.contains("HomeAssetSection(viewModel: viewModel)"))
        XCTAssertFalse(dashboardBody.contains("HomeHistorySection(viewModel: viewModel)"))
        XCTAssertTrue(dashboardSource.contains("Label(L10n.localize(\"home.assets.title\""))
        XCTAssertTrue(dashboardSource.contains("L10n.localize(\"home.assets.search_placeholder\""))
    }

    func testHomeAssetRowsPreferSourceApplicationIconWhenApplicationIsRecorded() throws {
        let root = try Self.repositoryRoot()
        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/HomeDashboardView.swift"),
            encoding: .utf8
        )
        let rowSource = try XCTUnwrap(
            dashboardSource.components(separatedBy: "private struct HomeAssetDetailModal").first
        )

        XCTAssertTrue(rowSource.contains("if let sourceAppName = item.sourceAppName"))
        XCTAssertTrue(rowSource.contains("SourceApplicationIcon("))
        XCTAssertTrue(rowSource.contains("appName: sourceAppName"))
        XCTAssertTrue(rowSource.contains("bundleID: item.sourceAppBundleID"))
        XCTAssertTrue(rowSource.contains("size: 34"))
    }

    func testTraceMetadataKeepsServiceAddressAwayFromLocalPostProcessingCard() throws {
        let root = try Self.repositoryRoot()
        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/HomeDashboardView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(dashboardSource.contains("private func llmTraceMetadata("))
        XCTAssertTrue(dashboardSource.contains("DetailMetaItem(title: L10n.localize(\"home.detail.meta.endpoint\""))
        XCTAssertTrue(dashboardSource.contains(".padding(.bottom, 6)"))
        XCTAssertTrue(dashboardSource.contains("llmTraceMetadata(llmTrace, taskMode: detail.taskMode)"))
    }

    func testHistoryDetailModalCanSaveEditedFinalTextForLearning() throws {
        let root = try Self.repositoryRoot()
        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/HomeDashboardView.swift"),
            encoding: .utf8
        )
        let modalSource = try XCTUnwrap(
            dashboardSource.components(separatedBy: "private struct HomeHistoryDetailModal").dropFirst().first
        )

        XCTAssertTrue(modalSource.contains("@State private var editedFinalText"))
        XCTAssertTrue(modalSource.contains("text: $editedFinalText"))
        XCTAssertTrue(modalSource.contains("TextEditor(text: $text)"))
        XCTAssertTrue(modalSource.contains("viewModel.updateSelectedHistoryFinalText(editedFinalText)"))
    }

    func testHistoryDetailModalUsesSegmentedTraceTabsAndSymmetricJSONDisclosures() throws {
        let root = try Self.repositoryRoot()
        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/HomeDashboardView.swift"),
            encoding: .utf8
        )
        let modalSource = try XCTUnwrap(
            dashboardSource.components(separatedBy: "private struct HomeHistoryDetailModal").dropFirst().first
        )

        XCTAssertTrue(modalSource.contains("Picker(\"\", selection: $selectedDetailTab)"))
        XCTAssertTrue(modalSource.contains("HomeHistoryDetailTab"))
        XCTAssertTrue(modalSource.contains("LLMJSONDisclosure("))
        XCTAssertTrue(modalSource.contains("title: L10n.localize(\"home.detail.llm.request_json_title\""))
        XCTAssertTrue(modalSource.contains("title: L10n.localize(\"home.detail.llm.response_json_title\""))
        XCTAssertFalse(modalSource.contains("RequestJSONDisclosure("))
    }

    func testHistoryDetailTraceTabsDoNotExposeSeparateTextReplacementTab() throws {
        let root = try Self.repositoryRoot()
        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/HomeDashboardView.swift"),
            encoding: .utf8
        )
        let tabSource = try XCTUnwrap(
            dashboardSource.components(separatedBy: "private enum HomeHistoryDetailTab").dropFirst().first?
                .components(separatedBy: "private struct HomeHistoryDetailModal").first
        )

        XCTAssertFalse(tabSource.contains("case voiceCorrection"))
        XCTAssertFalse(tabSource.contains("home.detail.tab.voice_correction"))
        XCTAssertTrue(tabSource.contains("case context"))
        XCTAssertTrue(tabSource.contains("case diagnostic"))
    }

    func testMainWindowCoordinatorCanDismissHomeDetailOverlayForScreenshotCapture() throws {
        let root = try Self.repositoryRoot()
        let coordinatorSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/WindowCoordinator.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/MainWindowController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(coordinatorSource.contains("func dismissHomeDetailOverlay()"))
        XCTAssertTrue(coordinatorSource.contains("mainWindowController?.dismissHomeDetailOverlay()"))
        XCTAssertTrue(controllerSource.contains("private let homeViewModel: HomeDashboardViewModel"))
        XCTAssertTrue(controllerSource.contains("func dismissHomeDetailOverlay()"))
        XCTAssertTrue(controllerSource.contains("homeViewModel.clearSelectedHomeDetail()"))
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("Package.swift").path
            ) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "HomeHistoryModalOverlayPresentationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
