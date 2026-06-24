import XCTest

final class ContextBoostBenchmarkWorkflowTests: XCTestCase {
    func testContextBoostBenchmarkTargetAndWorkflowsAreConfigured() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = try String(
            contentsOf: root.appendingPathComponent("Packages/VoxFlowContextBoostKit/Package.swift"),
            encoding: .utf8
        )
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(package.contains(#".executable(name: "VoxFlowContextBoostBench""#))
        XCTAssertTrue(package.contains(".executableTarget("))
        XCTAssertTrue(package.contains(#"name: "VoxFlowContextBoostBench""#))
        XCTAssertTrue(ci.contains("VoxFlowContextBoostBench"))
        XCTAssertTrue(release.contains("VoxFlowContextBoostBench"))
    }
}
