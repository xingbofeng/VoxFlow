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
        XCTAssertTrue(dashboardSource.contains("Label(\"资产\""))
        XCTAssertTrue(dashboardSource.contains("\"搜索资产\""))
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
        XCTAssertTrue(dashboardSource.contains("DetailMetaItem(title: \"服务地址\", value: llmTrace.endpoint)"))
        XCTAssertTrue(dashboardSource.contains(".padding(.bottom, 6)"))
        XCTAssertTrue(dashboardSource.contains("llmTraceMetadata(llmTrace, taskMode: detail.taskMode)"))
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
