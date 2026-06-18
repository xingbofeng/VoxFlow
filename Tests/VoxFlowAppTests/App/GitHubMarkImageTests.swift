import XCTest
@testable import VoxFlowApp

final class GitHubMarkImageTests: XCTestCase {
    func testGitHubMarkLoadsAsTemplateImageForThemeTinting() throws {
        let image = try XCTUnwrap(GitHubMarkImage.load())

        XCTAssertTrue(image.isTemplate)
    }
}
