import Foundation
import XCTest
@testable import VoiceInputApp

final class BrandIdentityTests: XCTestCase {
    func testProductBrandUsesVoxFlowAndChineseDisplayName() {
        XCTAssertEqual(ProductBrand.englishName, "VoxFlow")
        XCTAssertEqual(ProductBrand.chineseDisplayName, "随声写")
        XCTAssertEqual(ProductBrand.legacyName, "VoiceInput")
        XCTAssertEqual(ProductBrand.bundleIdentifier, "com.voiceinput.app")
        XCTAssertEqual(ProductBrand.legacyBundleIdentifier, "com.voiceinput.app")
    }

    func testInfoPlistKeepsStableBundleIDAndUsesVisibleBrand() throws {
        let plist = try Self.infoPlist()

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.voiceinput.app")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "VoxFlow")
        XCTAssertEqual(plist["CFBundleName"] as? String, "VoxFlow")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "随声写")
        XCTAssertTrue((plist["NSMicrophoneUsageDescription"] as? String)?.contains("随声写") == true)
        XCTAssertTrue((plist["NSSpeechRecognitionUsageDescription"] as? String)?.contains("随声写") == true)
    }

    func testMakefileProducesVoxFlowBundleAndDMG() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("APP_NAME := VoxFlow"))
        XCTAssertTrue(makefile.contains("SWIFT_EXECUTABLE := VoiceInputApp"))
        XCTAssertTrue(makefile.contains("DMG_NAME := VoxFlow-$(VERSION)-macOS"))
        XCTAssertTrue(makefile.contains("run: prelaunch-cleanup build"))
        XCTAssertTrue(makefile.contains("CURRENT_BUNDLE_ID := com.voiceinput.app"))
        XCTAssertTrue(makefile.contains("LEGACY_BUNDLE_ID := com.voiceinput.app"))
        XCTAssertTrue(makefile.contains("TEMP_RENAMED_BUNDLE_ID := com.xingbofeng.VoxFlow"))
        XCTAssertTrue(makefile.contains("Set :CFBundleIdentifier $(CURRENT_BUNDLE_ID)"))
        XCTAssertTrue(makefile.contains("lsregister"))
    }

    func testHelpLinksUseRenamedRepositoryAndPagesAddress() {
        XCTAssertEqual(HelpExternalLinks.projectHomepage, "https://xingbofeng.github.io/VoxFlow/")
        XCTAssertEqual(HelpExternalLinks.githubRepository, "https://github.com/xingbofeng/VoxFlow")
        XCTAssertEqual(HelpExternalLinks.latestRelease, "https://github.com/xingbofeng/VoxFlow/releases/latest")
    }

    func testLandingPageAndReadmeUseCurrentBrandWithMigrationNote() throws {
        let root = Self.repositoryRoot()
        let index = try String(
            contentsOf: root.appendingPathComponent("docs/index.html"),
            encoding: .utf8
        )
        let readme = try String(
            contentsOf: root.appendingPathComponent("README.md"),
            encoding: .utf8
        )

        XCTAssertTrue(index.contains("<title>随声写 VoxFlow"))
        XCTAssertTrue(index.contains("https://github.com/xingbofeng/VoxFlow"))
        XCTAssertFalse(index.contains("github.com/xingbofeng/VoiceInput"))
        XCTAssertTrue(readme.contains("VoxFlow 原 VoiceInput"))
    }

    func testCIAndReleaseWorkflowsVerifyVoxFlowArtifacts() throws {
        let root = Self.repositoryRoot()
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        for workflow in [ci, release] {
            XCTAssertTrue(workflow.contains(".build/VoxFlow.app"))
            XCTAssertTrue(workflow.contains("dist/VoxFlow-${{ steps.version.outputs.value }}-macOS.dmg"))
            XCTAssertFalse(workflow.contains(".build/VoiceInputApp.app"))
        }
    }

    private static func infoPlist() throws -> [String: Any] {
        let url = repositoryRoot()
            .appendingPathComponent("Sources/VoiceInputApp/Resources/Info.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private static func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("Package.swift").path
            ) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
