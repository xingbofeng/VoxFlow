import XCTest
@testable import VoxFlowApp

final class HomeDashboardStatsLayoutTests: XCTestCase {
    func testSourceBreakdownRendersAsSeparateStatCards() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/HomeDashboardView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let statsGrid = try XCTUnwrap(
            source.range(
                of: #"private struct HomeStatsGrid:[\s\S]*?\nprivate struct HomeStatCard"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(statsGrid.contains("HomeStatCard(title: \"语音\", value: \"\\(stats.sourceBreakdown.dictation)\", systemImage: \"waveform\")"))
        XCTAssertTrue(statsGrid.contains("HomeStatCard(title: \"截图\", value: \"\\(stats.sourceBreakdown.screenshot)\", systemImage: \"camera.viewfinder\")"))
        XCTAssertTrue(statsGrid.contains("HomeStatCard(title: \"剪贴板\", value: \"\\(stats.sourceBreakdown.clipboard)\", systemImage: \"clipboard\")"))
        XCTAssertTrue(statsGrid.contains("HStack(spacing: Self.cardSpacing)"))
        XCTAssertTrue(statsGrid.contains(".compact()"))
        XCTAssertTrue(statsGrid.contains("private static let cardSpacing: CGFloat = 10"))
        XCTAssertFalse(statsGrid.contains("LazyVGrid"))
        XCTAssertFalse(statsGrid.contains("GridItem"))
        XCTAssertFalse(statsGrid.contains("title: \"来源分布\""))
        XCTAssertFalse(statsGrid.contains("stats.sourceBreakdown.summaryText"))
    }

    private static func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw NSError(
            domain: "HomeDashboardStatsLayoutTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Repository root not found"]
        )
    }
}
