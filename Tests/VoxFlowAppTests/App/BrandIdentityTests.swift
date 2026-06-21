import Foundation
import XCTest
@testable import VoxFlowApp

final class BrandIdentityTests: XCTestCase {
    func testProductBrandUsesVoxFlowAndChineseDisplayName() {
        XCTAssertEqual(ProductBrand.englishName, "VoxFlow")
        XCTAssertEqual(ProductBrand.chineseDisplayName, "码上写")
        XCTAssertEqual(ProductBrand.bundleIdentifier, "com.voxflow.app")
        XCTAssertEqual(ProductBrand.legacyBundleIdentifier, "com.voiceinput.app")
    }

    func testInfoPlistKeepsStableBundleIDAndUsesVisibleBrand() throws {
        let plist = try Self.infoPlist()

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.voxflow.app")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "VoxFlow")
        XCTAssertEqual(plist["CFBundleName"] as? String, "VoxFlow")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "码上写")
        XCTAssertTrue((plist["NSMicrophoneUsageDescription"] as? String)?.contains("码上写") == true)
        XCTAssertTrue((plist["NSSpeechRecognitionUsageDescription"] as? String)?.contains("码上写") == true)
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
        XCTAssertFalse(makefile.contains(obsoleteXingbofengBundleIdentifier))
        XCTAssertFalse(makefile.contains("OBSOLETE_BUNDLE_ID"))
        XCTAssertFalse(makefile.contains("RENAMED_BUNDLE_ID"))
        XCTAssertFalse(makefile.contains("TEMP_RENAMED_BUNDLE_ID"))
        XCTAssertTrue(makefile.contains("Set :CFBundleIdentifier $(CURRENT_BUNDLE_ID)"))
        XCTAssertTrue(makefile.contains("lsregister"))
        XCTAssertTrue(makefile.contains("$(LSREGISTER)\" -f \"$(BUNDLE_DIR)\""))
    }

    func testKeychainServiceUsesCurrentBundleIDNamespace() throws {
        let service = try XCTUnwrap(
            Mirror(reflecting: KeychainCredentialStore()).children.first { $0.label == "service" }?.value as? String
        )
        XCTAssertEqual(service, "com.voxflow.app.credentials")
    }

    func testMakefileSupportsNativeDevelopmentAndArm64ReleaseBuilds() throws {
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
        XCTAssertFalse(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch x86_64"))
        XCTAssertTrue(makefile.contains("lipo \"$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)\" -verify_arch arm64"))
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
        XCTAssertFalse(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch x86_64"))
    }

    func testMakefileDetectsCargoWithoutAssumingSwiftArchitectureMatchesRustTriple() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("rustup which cargo"))
        XCTAssertTrue(makefile.contains("rustup which rustc"))
        XCTAssertTrue(makefile.contains("command -v cargo"))
        XCTAssertTrue(makefile.contains("command -v rustc"))
        XCTAssertFalse(makefile.contains("stable-$(SWIFT_NATIVE_ARCH)-apple-darwin/bin/cargo"))
        XCTAssertTrue(makefile.contains("RUST_CARGO ?="))
        XCTAssertTrue(makefile.contains("RUSTC ?="))
        XCTAssertTrue(makefile.contains("RUSTC=\"$(RUSTC)\" \"$(RUST_CARGO)\" build"))
        XCTAssertTrue(makefile.contains("prepare-agent-helper:"))
    }

    func testMakefileSignsBundledAgentHelperAndShim() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertEqual(
            makefile.components(separatedBy: "codesign --force --sign \"$(CODE_SIGN_IDENTITY)\" \"$(BUNDLE_DIR)/Contents/Helpers/voxflow\"").count - 1,
            3
        )
        XCTAssertEqual(
            makefile.components(separatedBy: "codesign --force --sign \"$(CODE_SIGN_IDENTITY)\" \"$(BUNDLE_DIR)/Contents/Helpers/vox\"").count - 1,
            3
        )
    }

    func testMakefileBundlesMLXMetallibForSpeechSwiftRuntime() throws {
        let root = Self.repositoryRoot()
        let makefile = try String(
            contentsOf: root.appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        let scriptURL = root.appendingPathComponent("scripts/build-mlx-metallib.sh")

        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path))
        XCTAssertTrue(makefile.contains("MLX_METALLIB_SCRIPT := scripts/build-mlx-metallib.sh"))
        XCTAssertTrue(makefile.contains("MLX_METALLIB := mlx.metallib"))
        XCTAssertTrue(makefile.contains("bash \"$(MLX_METALLIB_SCRIPT)\" release"))
        XCTAssertTrue(makefile.contains("bash \"$(MLX_METALLIB_SCRIPT)\" debug"))
        XCTAssertTrue(makefile.contains("\"$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)\""))
        XCTAssertTrue(makefile.contains("@test -f \"$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)\""))
        XCTAssertTrue(makefile.contains("codesign --force --sign \"$(CODE_SIGN_IDENTITY)\" \"$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)\""))
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
        XCTAssertFalse(cleanupBody.contains("OBSOLETE_BUNDLE_ID"))
        XCTAssertFalse(cleanupBody.contains("RENAMED_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("REQUESTED_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("CURRENT_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("/private/tmp/voxflow-dmg-smoke.*/$(APP_NAME).app"))
        XCTAssertTrue(cleanupBody.contains("$(CURDIR)/$(BUNDLE_DIR)/Contents/Helpers/[v]oxflow serve"))
        XCTAssertTrue(makefile.contains("LEGACY_BUNDLE_ID := com.voiceinput.app"))
        XCTAssertFalse(makefile.contains(obsoleteXingbofengBundleIdentifier))
        XCTAssertFalse(makefile.contains("OBSOLETE_BUNDLE_ID"))
        XCTAssertFalse(makefile.contains("RENAMED_BUNDLE_ID"))
        XCTAssertTrue(makefile.contains("REQUESTED_BUNDLE_ID := com.VoxFlow.app"))
        XCTAssertTrue(makefile.contains("STATUS_ITEM_AUTOSAVE_NAMES :="))
        XCTAssertTrue(makefile.contains("VoxFlowStatusItem"))
        XCTAssertTrue(makefile.contains("VoxFlowStatusItemRuntime"))
        XCTAssertTrue(makefile.contains("Item-0"))
        XCTAssertTrue(cleanupBody.contains("for autosave_name in $(STATUS_ITEM_AUTOSAVE_NAMES)"))
        XCTAssertTrue(cleanupBody.contains("NSStatusItem Preferred Position $$autosave_name"))
        XCTAssertTrue(cleanupBody.contains("NSStatusItem VisibleCC $$autosave_name"))
        XCTAssertTrue(cleanupBody.contains("VoxFlowStatusItemPlacementResetV1"))
        XCTAssertTrue(cleanupBody.contains("for bundle_id in \"$(LEGACY_BUNDLE_ID)\" \"$(REQUESTED_BUNDLE_ID)\" \"$(CURRENT_BUNDLE_ID)\""))
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

        XCTAssertTrue(index.contains("<title>码上写 VoxFlow"))
        XCTAssertTrue(index.contains("https://github.com/xingbofeng/VoxFlow"))
        XCTAssertFalse(index.contains("github.com/xingbofeng/VoiceInput"))
        XCTAssertTrue(readme.contains("VoxFlow"))
    }

    func testCIKeepsFastChecksAndReleaseWorkflowVerifiesVoxFlowArtifacts() throws {
        let root = Self.repositoryRoot()
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(ci.contains("swift test"))
        XCTAssertTrue(ci.contains("make architecture-check"))
        XCTAssertTrue(ci.contains("swift build -c debug -Xswiftc -warnings-as-errors"))
        XCTAssertTrue(ci.contains("cancel-in-progress: true"))
        XCTAssertFalse(ci.contains("make dmg"))
        XCTAssertFalse(ci.contains("dist/VoxFlow-${{ steps.version.outputs.value }}-macOS.dmg"))
        XCTAssertFalse(ci.contains(".build/VoxFlowApp.app"))

        XCTAssertTrue(release.contains(".build/VoxFlow.app"))
        XCTAssertTrue(release.contains("dist/VoxFlow-${{ steps.version.outputs.value }}-macOS.dmg"))
        XCTAssertFalse(release.contains(".build/VoxFlowApp.app"))
    }

    func testReleaseWorkflowRunsSameQualityGatesAsCI() throws {
        let root = Self.repositoryRoot()
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(release.contains("swift test"))
        XCTAssertTrue(release.contains("make architecture-check"))
        XCTAssertTrue(release.contains("swift build -c debug -Xswiftc -warnings-as-errors"))
        XCTAssertLessThan(
            try XCTUnwrap(release.range(of: "make architecture-check")?.lowerBound),
            try XCTUnwrap(release.range(of: "make dmg")?.lowerBound),
            "Release must fail architecture violations before packaging."
        )
        XCTAssertLessThan(
            try XCTUnwrap(release.range(of: "swift build -c debug -Xswiftc -warnings-as-errors")?.lowerBound),
            try XCTUnwrap(release.range(of: "make dmg")?.lowerBound),
            "Release must fail warnings before packaging."
        )
    }

    func testReleaseWorkflowVerifiesTagPlistVersionAndReleaseNotesMatch() throws {
        let root = Self.repositoryRoot()
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )
        let plistVersion = try XCTUnwrap(Self.infoPlist()["CFBundleShortVersionString"] as? String)
        let releaseNotesPath = root.appendingPathComponent(".github/release-notes/v\(plistVersion).md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: releaseNotesPath.path))
        XCTAssertTrue(release.contains("TAG_VERSION=\"${GITHUB_REF_NAME#v}\""))
        XCTAssertTrue(release.contains("PLIST_VERSION="))
        XCTAssertTrue(release.contains("test \"$TAG_VERSION\" = \"$PLIST_VERSION\""))
        XCTAssertTrue(release.contains("test -f \".github/release-notes/v${PLIST_VERSION}.md\""))
    }

    private static func infoPlist() throws -> [String: Any] {
        let url = repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Resources/Info.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private var obsoleteXingbofengBundleIdentifier: String {
        ["com", "xingbofeng", "VoxFlow"].joined(separator: ".")
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
