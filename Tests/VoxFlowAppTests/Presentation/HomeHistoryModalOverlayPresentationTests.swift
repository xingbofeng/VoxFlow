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
