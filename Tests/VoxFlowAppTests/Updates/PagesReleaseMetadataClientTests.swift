import XCTest
@testable import VoxFlowApp

@MainActor
final class PagesReleaseMetadataClientTests: XCTestCase {
    func testLiveUpdateCheckUsesPagesMetadataInsteadOfGitHubAPI() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Updates/UpdateCheckCoordinator.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("return PagesReleaseMetadataClient()"))
        XCTAssertFalse(source.contains("return GitHubReleaseClient()"))
    }

    func testDecodesStaticPagesReleaseMetadata() throws {
        let release = try decodeFixture("latest-pages")

        XCTAssertEqual(release.version, "1.6.2")
        XCTAssertEqual(release.tagName, "v1.6.2")
        XCTAssertEqual(release.releasePageURL.absoluteString, "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.6.2")
        XCTAssertEqual(release.downloadURL.absoluteString, "https://github.com/xingbofeng/VoxFlow/releases/download/v1.6.2/VoxFlow-1.6.2-macOS.dmg")
        XCTAssertEqual(release.releaseNotes, "静态更新源，避开 GitHub API rate limit。")
        XCTAssertTrue(release.isStableCandidate)
    }

    func testMalformedPagesMetadataThrows() {
        XCTAssertThrowsError(try PagesReleaseMetadataClient.decodeRelease(data: Data(#"{"version":""}"#.utf8)))
    }

    func testDecodesLandingPageScriptFallbackMetadata() throws {
        let release = try decodeScriptFixture("latest-pages-script")

        XCTAssertEqual(release.version, "1.6.1")
        XCTAssertEqual(release.tagName, "v1.6.1")
        XCTAssertEqual(release.releasePageURL.absoluteString, "https://github.com/xingbofeng/VoxFlow/releases/tag/v1.6.1")
        XCTAssertEqual(release.downloadURL.absoluteString, "https://github.com/xingbofeng/VoxFlow/releases/download/v1.6.1/VoxFlow-1.6.1-macOS.dmg")
        XCTAssertEqual(release.releaseNotes, "")
        XCTAssertTrue(release.isStableCandidate)
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
        return try PagesReleaseMetadataClient.decodeRelease(data: data)
    }

    private func decodeScriptFixture(_ name: String) throws -> RemoteRelease {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "js",
                subdirectory: "Fixtures/Updates"
            )
        )
        let data = try Data(contentsOf: url)
        return try PagesReleaseMetadataClient.decodeReleaseScript(data: data)
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "PagesReleaseMetadataClientTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
