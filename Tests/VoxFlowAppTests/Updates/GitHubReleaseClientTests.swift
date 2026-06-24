import XCTest
@testable import VoxFlowApp

@MainActor
final class GitHubReleaseClientTests: XCTestCase {
    func testDecodesStableReleaseWithDMGAsset() throws {
        let release = try decodeFixture("latest-newer")

        XCTAssertEqual(release.version, "1.6.2")
        XCTAssertEqual(release.tagName, "v1.6.2")
        XCTAssertEqual(release.releasePageURL.absoluteString, "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.6.2")
        XCTAssertEqual(release.downloadURL.absoluteString, "https://github.com/xingbofeng/VoxFlow/releases/download/v1.6.2/VoxFlow-1.6.2-macOS.dmg")
        XCTAssertEqual(release.releaseNotes, "修复稳定性问题并改进更新检测。")
        XCTAssertTrue(release.isStableCandidate)
    }

    func testDecodesPrereleaseAsNotStableCandidate() throws {
        let release = try decodeFixture("latest-prerelease")

        XCTAssertEqual(release.version, "1.7.0")
        XCTAssertFalse(release.isStableCandidate)
        XCTAssertTrue(release.isPrerelease)
    }

    func testNoDMGAssetFallsBackToReleasePageURL() throws {
        let release = try decodeFixture("latest-no-dmg")

        XCTAssertEqual(release.downloadURL, release.releasePageURL)
        XCTAssertTrue(release.isStableCandidate)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try decodeFixture("latest-malformed"))
    }

    private func decodeFixture(_ name: String) throws -> RemoteRelease {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures/Updates"
            )
        )
        let data = try Data(contentsOf: url)
        return try GitHubReleaseClient.decodeRelease(data: data)
    }
}
