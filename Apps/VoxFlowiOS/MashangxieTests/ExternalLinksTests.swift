import XCTest
@testable import Mashangxie

final class ExternalLinksTests: XCTestCase {
    func testAboutLinksPointToRepositoryDocs() {
        XCTAssertEqual(ExternalLinks.githubRepository.absoluteString, "https://github.com/xingbofeng/VoxFlow")
        XCTAssertEqual(
            ExternalLinks.privacyPolicy.absoluteString,
            "https://github.com/xingbofeng/VoxFlow/blob/main/docs/PRIVACY.md"
        )
        XCTAssertEqual(
            ExternalLinks.thirdPartyLicenses.absoluteString,
            "https://github.com/xingbofeng/VoxFlow/blob/main/docs/third-party-licenses.md"
        )
    }
}
