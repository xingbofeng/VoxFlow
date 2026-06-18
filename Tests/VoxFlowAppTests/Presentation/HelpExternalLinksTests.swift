import XCTest
@testable import VoxFlowApp

final class HelpExternalLinksTests: XCTestCase {
    func testProjectHomepageUsesLandingPage() {
        XCTAssertEqual(HelpExternalLinks.projectHomepage, "https://xingbofeng.github.io/VoxFlow/")
    }

    func testGitHubRepositoryRemainsSeparateEntry() {
        XCTAssertEqual(HelpExternalLinks.githubRepository, "https://github.com/xingbofeng/VoxFlow")
    }
}
