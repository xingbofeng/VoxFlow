import Foundation
import XCTest
@testable import VoxFlowApp

final class BrandIdentityTests: XCTestCase {
    func testProductBrandUsesVoxFlowAndChineseDisplayName() {
        XCTAssertEqual(ProductBrand.englishName, "VoxFlow")
        XCTAssertEqual(ProductBrand.chineseDisplayName, "随声写")
        XCTAssertEqual(ProductBrand.bundleIdentifier, "com.voxflow.app")
        XCTAssertEqual(ProductBrand.legacyBundleIdentifier, "com.voiceinput.app")
    }

    func testInfoPlistKeepsStableBundleIDAndUsesVisibleBrand() throws {
        let plist = try Self.infoPlist()

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.voxflow.app")
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
        XCTAssertTrue(makefile.contains("SWIFT_EXECUTABLE := VoxFlowApp"))
        XCTAssertTrue(makefile.contains("DMG_NAME := VoxFlow-$(VERSION)-macOS"))
        XCTAssertTrue(makefile.contains("run: prelaunch-cleanup build"))
        XCTAssertTrue(makefile.contains("CURRENT_BUNDLE_ID := com.voxflow.app"))
        XCTAssertFalse(makefile.contains("TEMP_RENAMED_BUNDLE_ID"))
        XCTAssertTrue(makefile.contains("Set :CFBundleIdentifier $(CURRENT_BUNDLE_ID)"))
        XCTAssertTrue(makefile.contains("lsregister"))
        XCTAssertTrue(makefile.contains("$(LSREGISTER)\" -f \"$(BUNDLE_DIR)\""))
    }

    func testMakefileSupportsNativeDevelopmentBuildWithoutChangingUniversalReleaseBuild() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("SWIFT_NATIVE_ARCH := $(shell uname -m)"))
        XCTAssertTrue(makefile.contains("NATIVE_RELEASE_BIN_DIR := $(BUILD_DIR)/$(SWIFT_NATIVE_ARCH)-apple-macosx/release"))
        XCTAssertTrue(makefile.contains(".PHONY:"))
        XCTAssertTrue(makefile.contains("build-native: prepare-runtime"))
        XCTAssertTrue(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch $(SWIFT_NATIVE_ARCH)"))
        XCTAssertTrue(makefile.contains("\"$(NATIVE_RELEASE_BIN_DIR)/$(SWIFT_EXECUTABLE)\""))
        XCTAssertTrue(makefile.contains("run-native: prelaunch-cleanup build-native"))
        XCTAssertTrue(makefile.contains("lipo \"$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)\" -verify_arch $(SWIFT_NATIVE_ARCH)"))

        XCTAssertTrue(makefile.contains("build: prepare-runtime"))
        XCTAssertTrue(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch arm64"))
        XCTAssertTrue(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch x86_64"))
        XCTAssertTrue(makefile.contains("lipo \"$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)\" -verify_arch arm64 x86_64"))
        XCTAssertTrue(makefile.contains("run: prelaunch-cleanup build"))
    }

    func testMakefileSupportsDebugDevelopmentAppBundleWithoutChangingReleaseBuilds() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("SWIFT_DEBUG_FLAGS := -c debug -Xswiftc -warnings-as-errors"))
        XCTAssertTrue(makefile.contains("NATIVE_DEBUG_BIN_DIR := $(BUILD_DIR)/$(SWIFT_NATIVE_ARCH)-apple-macosx/debug"))
        XCTAssertTrue(makefile.contains("build-dev: prepare-runtime"))
        XCTAssertTrue(makefile.contains("swift build $(SWIFT_DEBUG_FLAGS) --arch $(SWIFT_NATIVE_ARCH)"))
        XCTAssertTrue(makefile.contains("\"$(NATIVE_DEBUG_BIN_DIR)/$(SWIFT_EXECUTABLE)\""))
        XCTAssertTrue(makefile.contains("run-dev: prelaunch-cleanup build-dev"))
        XCTAssertTrue(makefile.contains("debug: prepare-runtime"))

        XCTAssertTrue(makefile.contains("build-native: prepare-runtime"))
        XCTAssertTrue(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch $(SWIFT_NATIVE_ARCH)"))
        XCTAssertTrue(makefile.contains("build: prepare-runtime"))
        XCTAssertTrue(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch arm64"))
        XCTAssertTrue(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch x86_64"))
    }

    func testMakefileSkipsSherpaBootstrapWhenRuntimeLibrariesExist() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("SHERPA_ONNX_LIB := Vendor/sherpa-onnx.xcframework/macos-arm64_x86_64/libsherpa-onnx.a"))
        XCTAssertTrue(makefile.contains("ONNXRUNTIME_LIB := Vendor/sherpa-onnx.xcframework/macos-arm64_x86_64/libonnxruntime.a"))
        XCTAssertTrue(makefile.contains("prepare-runtime: $(SHERPA_ONNX_LIB) $(ONNXRUNTIME_LIB)"))
        XCTAssertTrue(makefile.contains("$(SHERPA_ONNX_LIB) $(ONNXRUNTIME_LIB):"))
        XCTAssertTrue(makefile.contains("./scripts/bootstrap-sherpa-onnx.sh"))
    }

    func testPrelaunchCleanupClearsLegacyAndCurrentStatusItemDefaults() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        let cleanupStart = try XCTUnwrap(
            makefile.range(of: "\nprelaunch-cleanup:")?.lowerBound
        )
        let nextTarget = try XCTUnwrap(
            makefile[cleanupStart...].range(of: "\n\n")?.lowerBound
        )
        let cleanupBody = String(makefile[cleanupStart..<nextTarget])

        XCTAssertTrue(cleanupBody.contains("$(LSREGISTER)"), "cleanup should still clear stale local app registration")
        XCTAssertTrue(cleanupBody.contains("LEGACY_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("RENAMED_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("REQUESTED_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("CURRENT_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("/private/tmp/voxflow-dmg-smoke.*/$(APP_NAME).app"))
        XCTAssertTrue(makefile.contains("LEGACY_BUNDLE_ID := com.voiceinput.app"))
        XCTAssertTrue(makefile.contains("RENAMED_BUNDLE_ID := com.xingbofeng.VoxFlow"))
        XCTAssertTrue(makefile.contains("REQUESTED_BUNDLE_ID := com.VoxFlow.app"))
        XCTAssertTrue(makefile.contains("STATUS_ITEM_AUTOSAVE_NAMES :="))
        XCTAssertTrue(makefile.contains("VoxFlowStatusItem"))
        XCTAssertTrue(makefile.contains("VoxFlowStatusItemRuntime"))
        XCTAssertTrue(makefile.contains("Item-0"))
        XCTAssertTrue(cleanupBody.contains("for autosave_name in $(STATUS_ITEM_AUTOSAVE_NAMES)"))
        XCTAssertTrue(cleanupBody.contains("NSStatusItem Preferred Position $$autosave_name"))
        XCTAssertTrue(cleanupBody.contains("NSStatusItem VisibleCC $$autosave_name"))
        XCTAssertTrue(cleanupBody.contains("VoxFlowStatusItemPlacementResetV1"))
        XCTAssertTrue(cleanupBody.contains("for bundle_id in \"$(LEGACY_BUNDLE_ID)\" \"$(RENAMED_BUNDLE_ID)\" \"$(REQUESTED_BUNDLE_ID)\" \"$(CURRENT_BUNDLE_ID)\""))
        XCTAssertTrue(cleanupBody.contains("defaults delete \"$$bundle_id\""))

        // run target body itself should NOT contain defaults delete (delegated to prelaunch-cleanup)
        let runStart = try XCTUnwrap(
            makefile.range(of: "\nrun: prelaunch-cleanup build")?.lowerBound
        )
        let runNext = try XCTUnwrap(
            makefile[runStart...].range(of: "\n\n")?.lowerBound
        )
        let runBody = String(makefile[runStart..<runNext])

        XCTAssertFalse(runBody.contains("defaults delete"), "run target should delegate cleanup to prelaunch-cleanup")
        XCTAssertFalse(runBody.contains("lsregister"), "run target should delegate LS cleanup to prelaunch-cleanup")
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
        XCTAssertTrue(readme.contains("VoxFlow"))
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
            XCTAssertFalse(workflow.contains(".build/VoxFlowApp.app"))
        }
    }

    private static func infoPlist() throws -> [String: Any] {
        let url = repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Resources/Info.plist")
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
