import XCTest

final class HomeHistoryModalOverlayPresentationTests: XCTestCase {
    func testHistoryDetailOverlayIsHostedByMainShellInsteadOfDashboardContent() throws {
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

        XCTAssertTrue(shellSource.contains("if let detail = homeViewModel.selectedDetail"))
        XCTAssertTrue(shellSource.contains("HomeHistoryDetailOverlay(viewModel: homeViewModel, detail: detail)"))
        XCTAssertFalse(dashboardBody.contains("HomeHistoryDetailOverlay("))
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
