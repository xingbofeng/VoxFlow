import Foundation
import XCTest
@testable import VoxFlowApp

final class BrandIdentityTests: XCTestCase {
    func testProductBrandUsesVoxFlowAndChineseDisplayName() {
        XCTAssertEqual(ProductBrand.englishName, Bundle.main.localizedString(forKey: "product.brand.english_name", value: "VoxFlow", table: "Localizable"))
        XCTAssertEqual(ProductBrand.chineseDisplayName, Bundle.main.localizedString(forKey: "product.brand.chinese_display_name", value: "码上写", table: "Localizable"))
        let preferredLocale = Bundle.main.preferredLocalizations.first ?? "en"
        let expectedDisplayName = preferredLocale.lowercased().hasPrefix("zh")
            ? Bundle.main.localizedString(forKey: "product.brand.chinese_display_name", value: "码上写", table: "Localizable")
            : ProductBrand.englishName
        XCTAssertEqual(ProductBrand.displayName, expectedDisplayName)
        XCTAssertEqual(ProductBrand.bundleIdentifier, "com.voxflow.app")
    }

    func testInfoPlistKeepsStableBundleIDAndUsesVisibleBrand() throws {
        let plist = try Self.infoPlist()

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.voxflow.app")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "VoxFlow")
        XCTAssertEqual(plist["CFBundleName"] as? String, "VoxFlow")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "码上写")
        XCTAssertTrue((plist["NSMicrophoneUsageDescription"] as? String)?.contains("码上写") == true)
        XCTAssertTrue((plist["NSSpeechRecognitionUsageDescription"] as? String)?.contains("码上写") == true)
        XCTAssertTrue((plist["NSSpeechRecognitionUsageDescription"] as? String)?.contains("生成字幕") == true)
    }

    func testMakefileProducesVoxFlowBundleAndDMG() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        let buildBody = try Self.makeTargetBody("build", in: makefile)

        XCTAssertTrue(makefile.contains("APP_NAME := VoxFlow"))
        XCTAssertTrue(makefile.contains("SWIFT_EXECUTABLE := VoxFlowApp"))
        XCTAssertTrue(makefile.contains("DMG_NAME := VoxFlow-$(VERSION)-macOS"))
        XCTAssertTrue(makefile.contains("run: prelaunch-cleanup build"))
        XCTAssertTrue(makefile.contains("CURRENT_BUNDLE_ID := com.voxflow.app"))
        XCTAssertTrue(makefile.contains("DEV_BUNDLE_ID := com.voxflow.app.dev"))
        XCTAssertFalse(makefile.contains(obsoleteXingbofengBundleIdentifier))
        XCTAssertFalse(makefile.contains("OBSOLETE_BUNDLE_ID"))
        XCTAssertFalse(makefile.contains("RENAMED_BUNDLE_ID"))
        XCTAssertFalse(makefile.contains("TEMP_RENAMED_BUNDLE_ID"))
        XCTAssertTrue(makefile.contains("Set :CFBundleIdentifier $(CURRENT_BUNDLE_ID)"))
        XCTAssertTrue(buildBody.contains("Set :CFBundleIdentifier $(CURRENT_BUNDLE_ID)"))
        XCTAssertFalse(buildBody.contains("Set :CFBundleIdentifier $(DEV_BUNDLE_ID)"))
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
        XCTAssertTrue(makefile.contains("NATIVE_RELEASE_BIN_DIR := $(SWIFTPM_BUILD_DIR)/$(SWIFT_NATIVE_ARCH)-apple-macosx/release"))
        XCTAssertTrue(makefile.contains(".PHONY:"))
        XCTAssertTrue(makefile.contains("build-native: prepare-runtime"))
        XCTAssertTrue(makefile.contains("$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) $(SWIFT_RELEASE_FLAGS) --arch $(SWIFT_NATIVE_ARCH)"))
        XCTAssertTrue(makefile.contains("\"$(NATIVE_RELEASE_BIN_DIR)/$(SWIFT_EXECUTABLE)\""))
        XCTAssertTrue(makefile.contains("run-native: prelaunch-cleanup build-native"))
        XCTAssertTrue(makefile.contains("lipo \"$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)\" -verify_arch $(SWIFT_NATIVE_ARCH)"))

        XCTAssertTrue(makefile.contains("build: prepare-runtime"))
        XCTAssertTrue(makefile.contains("$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) $(SWIFT_RELEASE_FLAGS) --arch arm64"))
        XCTAssertFalse(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch x86_64"))
        XCTAssertTrue(makefile.contains("lipo \"$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)\" -verify_arch arm64"))
        XCTAssertTrue(makefile.contains("run: prelaunch-cleanup build"))
    }

    func testMakefileSupportsDebugDevelopmentAppBundleWithoutChangingReleaseBuilds() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        let buildDevBody = try Self.makeTargetBody("build-dev", in: makefile)

        XCTAssertTrue(makefile.contains("SWIFT_DEBUG_FLAGS := -c debug -Xswiftc -warnings-as-errors"))
        XCTAssertTrue(makefile.contains("NATIVE_DEBUG_BIN_DIR := $(SWIFTPM_BUILD_DIR)/$(SWIFT_NATIVE_ARCH)-apple-macosx/debug"))
        XCTAssertTrue(makefile.contains("build-dev: prepare-runtime"))
        XCTAssertTrue(makefile.contains("$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) $(SWIFT_DEBUG_FLAGS) --arch $(SWIFT_NATIVE_ARCH)"))
        XCTAssertTrue(makefile.contains("\"$(NATIVE_DEBUG_BIN_DIR)/$(SWIFT_EXECUTABLE)\""))
        XCTAssertTrue(makefile.contains("run-dev: prelaunch-cleanup build-dev"))
        XCTAssertTrue(buildDevBody.contains("Set :CFBundleIdentifier $(DEV_BUNDLE_ID)"))
        XCTAssertTrue(buildDevBody.contains("Set :CFBundleName $(DEV_BUNDLE_NAME)"))
        XCTAssertTrue(buildDevBody.contains("Set :CFBundleDisplayName $(DEV_DISPLAY_NAME)"))
        XCTAssertTrue(makefile.contains("debug: prepare-runtime"))

        XCTAssertTrue(makefile.contains("build-native: prepare-runtime"))
        XCTAssertTrue(makefile.contains("$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) $(SWIFT_RELEASE_FLAGS) --arch $(SWIFT_NATIVE_ARCH)"))
        XCTAssertTrue(makefile.contains("build: prepare-runtime"))
        XCTAssertTrue(makefile.contains("$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) $(SWIFT_RELEASE_FLAGS) --arch arm64"))
        XCTAssertFalse(makefile.contains("swift build $(SWIFT_RELEASE_FLAGS) --arch x86_64"))
    }

    func testAppBundleBuildsFailFastWhenPrivacyUsageDescriptionsAreMissing() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        for target in ["build", "build-native", "build-dev"] {
            let body = try Self.makeTargetBody(target, in: makefile)

            XCTAssertTrue(body.contains("Print :NSMicrophoneUsageDescription"))
            XCTAssertTrue(body.contains("Print :NSSpeechRecognitionUsageDescription"))
        }
    }

    func testMakefileSeparatesDevelopmentAndReleaseAppBundles() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        let buildBody = try Self.makeTargetBody("build", in: makefile)
        let buildDevBody = try Self.makeTargetBody("build-dev", in: makefile)
        let runDevBody = try Self.makeTargetBody("run-dev", in: makefile)
        let cleanupBody = try Self.makeTargetBody("prelaunch-cleanup", in: makefile)

        XCTAssertTrue(makefile.contains("BUNDLE_DIR := $(BUILD_DIR)/release/$(APP_NAME).app"))
        XCTAssertTrue(makefile.contains("DEV_BUNDLE_DIR := $(BUILD_DIR)/dev/$(APP_NAME).app"))
        XCTAssertTrue(buildBody.contains("\"$(BUNDLE_DIR)/Contents/MacOS"))
        XCTAssertFalse(buildBody.contains("$(DEV_BUNDLE_DIR)"))
        XCTAssertTrue(buildDevBody.contains("\"$(DEV_BUNDLE_DIR)/Contents/MacOS"))
        XCTAssertFalse(buildDevBody.contains("\"$(BUNDLE_DIR)/Contents/MacOS"))
        XCTAssertTrue(runDevBody.contains("open -n \"$(CURDIR)/$(DEV_BUNDLE_DIR)\""))
        XCTAssertTrue(runDevBody.contains("$(CURDIR)/$(DEV_BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)"))
        XCTAssertTrue(runDevBody.contains("Expected dev app to launch from $(CURDIR)/$(DEV_BUNDLE_DIR)"))
        XCTAssertTrue(cleanupBody.contains("\"$(BUNDLE_DIR)\""))
        XCTAssertTrue(cleanupBody.contains("\"$(DEV_BUNDLE_DIR)\""))
        XCTAssertTrue(cleanupBody.contains("rm -rf \".build/$(APP_NAME).app\""))
    }

    func testReleaseDMGRequiresExplicitStableSigningIdentity() throws {
        let root = Self.repositoryRoot()
        let makefile = try String(
            contentsOf: root.appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )
        let signingGuardBody = try Self.makeTargetBody("require-release-signing-identity", in: makefile)

        XCTAssertTrue(makefile.contains("DEVELOPMENT_CODE_SIGN_IDENTITY ?="))
        XCTAssertTrue(makefile.contains("RELEASE_CODE_SIGN_IDENTITY ?= VoxFlow Release Signing"))
        XCTAssertTrue(makefile.contains("RELEASE_KEYCHAIN_PATH ?="))
        XCTAssertTrue(makefile.contains("CODE_SIGN_KEYCHAIN_OPTION := $(if $(RELEASE_KEYCHAIN_PATH),--keychain \"$(RELEASE_KEYCHAIN_PATH)\",)"))
        XCTAssertTrue(makefile.contains("dmg: CODE_SIGN_IDENTITY = $(RELEASE_CODE_SIGN_IDENTITY)"))
        XCTAssertTrue(makefile.contains("dmg: require-release-signing-identity build"))
        XCTAssertTrue(signingGuardBody.contains("test -n \"$(RELEASE_CODE_SIGN_IDENTITY)\""))
        XCTAssertTrue(signingGuardBody.contains("test \"$(RELEASE_CODE_SIGN_IDENTITY)\" != \"-\""))
        XCTAssertTrue(signingGuardBody.contains("RELEASE_KEYCHAIN_PATH"))
        XCTAssertTrue(signingGuardBody.contains("Release signing keychain not found"))
        XCTAssertTrue(signingGuardBody.contains("security find-identity -v -p codesigning"))
        XCTAssertFalse(signingGuardBody.contains("security find-identity -v \"$(RELEASE_KEYCHAIN_PATH)\""))
        XCTAssertFalse(signingGuardBody.contains("|| true"))

        XCTAssertTrue(release.contains("VOXFLOW_RELEASE_CERTIFICATE_P12_BASE64"))
        XCTAssertTrue(release.contains("VOXFLOW_RELEASE_CERTIFICATE_PASSWORD"))
        XCTAssertTrue(release.contains("VOXFLOW_RELEASE_SIGNING_IDENTITY"))
        XCTAssertTrue(release.contains("VOXFLOW_RELEASE_KEYCHAIN_PATH"))
        XCTAssertTrue(release.contains("security import"))
        XCTAssertFalse(release.contains("security add-trusted-cert"))
        XCTAssertTrue(release.contains("CERTIFICATE_SHA1=$(security find-certificate -a -Z \"$KEYCHAIN_PATH\""))
        XCTAssertTrue(release.contains("VOXFLOW_RELEASE_SIGNING_IDENTITY=$CERTIFICATE_SHA1"))
        XCTAssertTrue(release.contains("codesign -d --extract-certificates \"$GITHUB_WORKSPACE/.build/release/VoxFlow.app\""))
        XCTAssertTrue(release.contains("APP_CERTIFICATE_SHA1=$(openssl x509 -inform DER -in \"$CERTIFICATE_DIR/codesign0\""))
        XCTAssertTrue(release.contains("test \"$APP_CERTIFICATE_SHA1\" = \"$VOXFLOW_RELEASE_SIGNING_IDENTITY\""))
        XCTAssertFalse(release.contains("Authority=$VOXFLOW_RELEASE_SIGNING_IDENTITY"))
        XCTAssertTrue(release.contains("RELEASE_CODE_SIGN_IDENTITY=\"$VOXFLOW_RELEASE_SIGNING_IDENTITY\""))
        XCTAssertTrue(release.contains("RELEASE_KEYCHAIN_PATH=\"$VOXFLOW_RELEASE_KEYCHAIN_PATH\""))
    }

    func testDMGCreationUsesExplicitImageSizeMargin() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        let dmgBody = try Self.makeTargetBody("dmg", in: makefile)

        XCTAssertTrue(dmgBody.contains("du -sm dist/staging"))
        XCTAssertTrue(dmgBody.contains("+ 256"))
        XCTAssertTrue(dmgBody.contains("-size $${dmg_size_mb}m"))
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
            makefile.components(separatedBy: "codesign --force --sign \"$(CODE_SIGN_IDENTITY)\" $(CODE_SIGN_KEYCHAIN_OPTION) \"$(BUNDLE_DIR)/Contents/Helpers/voxflow\"").count - 1,
            2
        )
        XCTAssertEqual(
            makefile.components(separatedBy: "codesign --force --sign \"$(CODE_SIGN_IDENTITY)\" $(CODE_SIGN_KEYCHAIN_OPTION) \"$(BUNDLE_DIR)/Contents/Helpers/vox\"").count - 1,
            2
        )
        XCTAssertTrue(makefile.contains("codesign --force --sign \"$(CODE_SIGN_IDENTITY)\" $(CODE_SIGN_KEYCHAIN_OPTION) \"$(DEV_BUNDLE_DIR)/Contents/Helpers/voxflow\""))
        XCTAssertTrue(makefile.contains("codesign --force --sign \"$(CODE_SIGN_IDENTITY)\" $(CODE_SIGN_KEYCHAIN_OPTION) \"$(DEV_BUNDLE_DIR)/Contents/Helpers/vox\""))
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
        XCTAssertTrue(makefile.contains("MLX_DEFAULT_METALLIB := default.metallib"))
        XCTAssertTrue(makefile.contains("bash \"$(MLX_METALLIB_SCRIPT)\" release"))
        XCTAssertTrue(makefile.contains("bash \"$(MLX_METALLIB_SCRIPT)\" debug"))
        XCTAssertTrue(makefile.contains("\"$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)\""))
        XCTAssertTrue(makefile.contains("\"$(BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)\""))
        XCTAssertTrue(makefile.contains("@test -f \"$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)\""))
        XCTAssertTrue(makefile.contains("@test -f \"$(BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)\""))
        XCTAssertTrue(makefile.contains("codesign --force --sign \"$(CODE_SIGN_IDENTITY)\" $(CODE_SIGN_KEYCHAIN_OPTION) \"$(BUNDLE_DIR)/Contents/MacOS/$(MLX_METALLIB)\""))
        XCTAssertTrue(makefile.contains("codesign --force --sign \"$(CODE_SIGN_IDENTITY)\" $(CODE_SIGN_KEYCHAIN_OPTION) \"$(BUNDLE_DIR)/Contents/MacOS/$(MLX_DEFAULT_METALLIB)\""))
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

    func testPrelaunchCleanupClearsCurrentStatusItemDefaultsOnly() throws {
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
        XCTAssertFalse(cleanupBody.contains("LEGACY_BUNDLE_ID"))
        XCTAssertFalse(cleanupBody.contains("OBSOLETE_BUNDLE_ID"))
        XCTAssertFalse(cleanupBody.contains("RENAMED_BUNDLE_ID"))
        XCTAssertFalse(cleanupBody.contains("REQUESTED_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("CURRENT_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("DEV_BUNDLE_ID"))
        XCTAssertTrue(cleanupBody.contains("/private/tmp/voxflow-dmg-smoke.*/$(APP_NAME).app"))
        XCTAssertTrue(cleanupBody.contains("$(CURDIR)/$(BUNDLE_DIR)/Contents/Helpers/[v]oxflow serve"))
        XCTAssertFalse(makefile.contains("LEGACY_BUNDLE_ID"))
        XCTAssertFalse(makefile.contains(obsoleteXingbofengBundleIdentifier))
        XCTAssertFalse(makefile.contains("OBSOLETE_BUNDLE_ID"))
        XCTAssertFalse(makefile.contains("RENAMED_BUNDLE_ID"))
        XCTAssertFalse(makefile.contains("REQUESTED_BUNDLE_ID"))
        XCTAssertTrue(makefile.contains("STATUS_ITEM_AUTOSAVE_NAMES :="))
        XCTAssertTrue(makefile.contains("VoxFlowMenuBarItem"))
        XCTAssertFalse(makefile.contains("VoxFlowStatusItemMenuExtra"))
        XCTAssertNil(makefile.range(of: #"VoxFlowStatusItem(?:Visible)?V[0-9]+"#, options: .regularExpression))
        XCTAssertNil(makefile.range(of: #"Item-[0-9]+"#, options: .regularExpression))
        XCTAssertTrue(cleanupBody.contains("for autosave_name in $(STATUS_ITEM_AUTOSAVE_NAMES)"))
        XCTAssertTrue(cleanupBody.contains("NSStatusItem Preferred Position $$autosave_name"))
        XCTAssertTrue(cleanupBody.contains("NSStatusItem VisibleCC $$autosave_name"))
        XCTAssertTrue(cleanupBody.contains("VoxFlowStatusItemPlacementResetV1"))
        XCTAssertTrue(cleanupBody.contains("for bundle_id in \"$(CURRENT_BUNDLE_ID)\" \"$(DEV_BUNDLE_ID)\""))
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

    func testHelpLinksUseRenamedRepositoryAndHomepageAddress() {
        XCTAssertEqual(HelpExternalLinks.projectHomepage, "https://mashangxie.app/")
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

        XCTAssertTrue(index.contains("<title>VoxFlow 码上写 - 语音、OCR 和本地 Agent 工作流都进工作台</title>"))
        XCTAssertTrue(index.contains("https://mashangxie.app/"))
        XCTAssertTrue(index.contains("https://github.com/xingbofeng/VoxFlow"))
        XCTAssertFalse(index.contains("github.com/xingbofeng/VoiceInput"))
        XCTAssertTrue(readme.contains("VoxFlow"))
        XCTAssertTrue(readme.contains("https://mashangxie.app/"))
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
        XCTAssertTrue(ci.contains("swift_test_workers=8"))
        XCTAssertTrue(ci.contains("swift_build_jobs=\"$(sysctl -n hw.logicalcpu)\""))
        XCTAssertTrue(ci.contains("make architecture-check"))
        XCTAssertTrue(ci.contains("swift build -c debug -Xswiftc -warnings-as-errors"))
        XCTAssertTrue(ci.contains("cancel-in-progress: true"))
        XCTAssertTrue(ci.contains("timeout-minutes: 40"))
        XCTAssertFalse(ci.contains("make dmg"))
        XCTAssertFalse(ci.contains("dist/VoxFlow-${{ steps.version.outputs.value }}-macOS.dmg"))
        XCTAssertFalse(ci.contains(".build/VoxFlowApp.app"))

        XCTAssertTrue(release.contains(".build/release/VoxFlow.app"))
        XCTAssertTrue(release.contains("dist/VoxFlow-${{ steps.version.outputs.value }}-macOS.dmg"))
        XCTAssertTrue(release.contains("overwrite_files: true"))
        XCTAssertFalse(release.contains(".build/VoxFlow.app"))
        XCTAssertFalse(release.contains(".build/VoxFlowApp.app"))
    }

    func testReleaseWorkflowRunsSameQualityGatesAsCI() throws {
        let root = Self.repositoryRoot()
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(release.contains("swift test"))
        XCTAssertTrue(release.contains("swift_test_workers=8"))
        XCTAssertTrue(release.contains("swift_build_jobs=\"$(sysctl -n hw.logicalcpu)\""))
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

    private static func makeTargetBody(_ target: String, in makefile: String) throws -> String {
        let start = try XCTUnwrap(makefile.range(of: "\n\(target):")?.lowerBound)
        let end = try XCTUnwrap(makefile[start...].range(of: "\n\n")?.lowerBound)
        return String(makefile[start..<end])
    }
}
