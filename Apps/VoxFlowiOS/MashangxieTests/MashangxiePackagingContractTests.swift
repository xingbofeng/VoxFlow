import XCTest

final class MashangxiePackagingContractTests: XCTestCase {
    private let appGroupIdentifier = "group.com.mashangxie.ios"

    func testMainAppInfoPlistExposesDictationPermissionsAndColdStartURLScheme() throws {
        let info = try propertyList(at: iosRoot().appendingPathComponent("VoxFlowiOS/Info.plist"))

        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "码上写")
        XCTAssertEqual(info["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(info["MinimumOSVersion"] as? String, "17.0")
        XCTAssertNotNil(info["NSMicrophoneUsageDescription"])
        XCTAssertNotNil(info["NSSpeechRecognitionUsageDescription"])

        let urlTypes = try XCTUnwrap(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains("mashangxie"))
    }

    func testKeyboardInfoPlistDeclaresSystemKeyboardWithOpenAccess() throws {
        let info = try propertyList(at: iosRoot().appendingPathComponent("Keyboard/Info.plist"))
        let extensionInfo = try XCTUnwrap(info["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionInfo["NSExtensionAttributes"] as? [String: Any])

        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "码上写")
        XCTAssertEqual(info["CFBundlePackageType"] as? String, "XPC!")
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.keyboard-service")
        XCTAssertEqual(extensionInfo["NSExtensionPrincipalClass"] as? String, "$(PRODUCT_MODULE_NAME).KeyboardViewController")
        XCTAssertEqual(attributes["PrimaryLanguage"] as? String, "zh-Hans")
        XCTAssertEqual(attributes["RequestsOpenAccess"] as? Bool, true)
        XCTAssertEqual(attributes["IsASCIICapable"] as? Bool, true)
    }

    func testMainAppAndKeyboardShareTheSameAppGroupEntitlement() throws {
        let mainEntitlements = try propertyList(
            at: iosRoot().appendingPathComponent("VoxFlowiOS/Mashangxie.entitlements")
        )
        let keyboardEntitlements = try propertyList(
            at: iosRoot().appendingPathComponent("Keyboard/Keyboard.entitlements")
        )

        XCTAssertEqual(applicationGroups(in: mainEntitlements), [appGroupIdentifier])
        XCTAssertEqual(applicationGroups(in: keyboardEntitlements), [appGroupIdentifier])
    }

    func testXcodeGenKeepsAppKeyboardEmbeddingAndProviderBoundary() throws {
        let project = try String(contentsOf: iosRoot().appendingPathComponent("project.yml"), encoding: .utf8)
        let appTarget = try yamlTargetBlock(named: "Mashangxie", in: project)
        let keyboardTarget = try yamlTargetBlock(named: "MashangxieKeyboard", in: project)
        let sharedTarget = try yamlTargetBlock(named: "Shared", in: project)
        let chineseInputTarget = try yamlTargetBlock(named: "ChineseInput", in: project)

        XCTAssertTrue(project.contains("SWIFT_VERSION: \"6.0\""))
        XCTAssertTrue(project.contains("\"CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]\": \"YES\""))
        XCTAssertTrue(project.contains("\"CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]\": \"NO\""))
        XCTAssertTrue(project.contains("\"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]\": \"-\""))
        XCTAssertTrue(appTarget.contains("PRODUCT_BUNDLE_IDENTIFIER: com.mashangxie.ios"))
        XCTAssertTrue(appTarget.contains("CFBundleDisplayName: 码上写"))
        XCTAssertTrue(appTarget.contains("Copy Dev Cloud Credentials"))
        XCTAssertTrue(appTarget.contains("write-dev-cloud-resource.py"))
        XCTAssertTrue(appTarget.contains("DevCloudCredentials.plist"))
        XCTAssertFalse(project.contains("MASHANGXIE_DEV_ALIYUN_API_KEY_B64"))
        XCTAssertFalse(project.contains("-xcconfig"))
        XCTAssertTrue(appTarget.contains("- target: MashangxieKeyboard"))
        XCTAssertTrue(appTarget.contains("embed: true"))
        XCTAssertTrue(appTarget.contains("- target: ChineseInput"))
        XCTAssertTrue(appTarget.contains("- target: RimeKitObjC"))
        XCTAssertTrue(appTarget.contains("product: VoxFlowASRRuntime"))
        XCTAssertTrue(appTarget.contains("product: VoxFlowProviderApple"))
        XCTAssertTrue(appTarget.contains("product: VoxFlowProviderTencentCloud"))
        XCTAssertTrue(appTarget.contains("product: VoxFlowProviderAliyunDashScope"))
        XCTAssertTrue(appTarget.contains("product: VoxFlowProviderVolcengine"))

        XCTAssertTrue(keyboardTarget.contains("PRODUCT_BUNDLE_IDENTIFIER: com.mashangxie.ios.keyboard"))
        XCTAssertTrue(keyboardTarget.contains("SWIFT_VERSION: \"5.0\""))
        XCTAssertTrue(keyboardTarget.contains("SWIFT_STRICT_CONCURRENCY: minimal"))
        XCTAssertTrue(keyboardTarget.contains("- target: Shared"))
        XCTAssertTrue(keyboardTarget.contains("- target: ChineseInput"))
        XCTAssertTrue(keyboardTarget.contains("- target: RimeKitObjC"))
        XCTAssertTrue(keyboardTarget.contains("embed: true"))
        XCTAssertFalse(keyboardTarget.contains("package: DeviceKit"))
        XCTAssertFalse(keyboardTarget.contains("VoxFlowASRRuntime"))
        XCTAssertFalse(keyboardTarget.contains("VoxFlowMobileCore"))
        XCTAssertFalse(keyboardTarget.contains("VoxFlowAudio"))
        XCTAssertFalse(keyboardTarget.contains("VoxFlowProvider"))

        XCTAssertTrue(sharedTarget.contains("SWIFT_VERSION: \"5.0\""))
        XCTAssertTrue(sharedTarget.contains("SWIFT_STRICT_CONCURRENCY: minimal"))
        XCTAssertTrue(chineseInputTarget.contains("SWIFT_VERSION: \"5.0\""))
        XCTAssertTrue(chineseInputTarget.contains("SWIFT_STRICT_CONCURRENCY: minimal"))
        XCTAssertTrue(chineseInputTarget.contains("APPLICATION_EXTENSION_API_ONLY: \"YES\""))
    }

    func testMakefileKeepsUnsignedAndInstallableAdHocIpaEntryPoints() throws {
        let makefile = try String(
            contentsOf: iosRoot()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        let exportScript = try String(
            contentsOf: iosRoot()
                .appendingPathComponent("Scripts/export-ad-hoc-ipa.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("ios-ipa-unsigned:"))
        XCTAssertTrue(makefile.contains("ios-ipa: ios-keyboard-release-archive"))
        XCTAssertTrue(makefile.contains("IOS_IPA"))
        XCTAssertTrue(makefile.contains("Mashangxie-$(IOS_RELEASE_VERSION)-iOS.ipa"))
        XCTAssertTrue(makefile.contains("ios-keyboard-release-archive:"))
        XCTAssertTrue(makefile.contains("MASHANGXIE_DEVELOPMENT_TEAM"))
        XCTAssertTrue(makefile.contains("MASHANGXIE_APP_PROFILE_SPECIFIER"))
        XCTAssertTrue(makefile.contains("MASHANGXIE_KEYBOARD_PROFILE_SPECIFIER"))
        XCTAssertTrue(makefile.contains("CODE_SIGN_STYLE=Manual"))
        XCTAssertTrue(exportScript.contains("-exportArchive"))
        XCTAssertTrue(exportScript.contains("Add :method string ad-hoc"))
        XCTAssertTrue(exportScript.contains("com.mashangxie.ios.keyboard"))
        XCTAssertTrue(makefile.contains("verify-ios-ipa-contract.sh"))
    }

    func testBuiltKeyboardExtensionEmbedsChineseInputRuntimeFrameworks() throws {
        let appBundle = Bundle.main.bundleURL
        guard appBundle.pathExtension == "app" else {
            throw XCTSkip("MashangxieTests is not running inside the built app bundle")
        }

        let appFrameworks = appBundle.appendingPathComponent("Frameworks", isDirectory: true)
        let extensionFrameworks = appBundle
            .appendingPathComponent("PlugIns", isDirectory: true)
            .appendingPathComponent("MashangxieKeyboard.appex", isDirectory: true)
            .appendingPathComponent("Frameworks", isDirectory: true)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appFrameworks
                    .appendingPathComponent("ChineseInput.framework/ChineseInput")
                    .path
            ),
            "Missing ChineseInput.framework in the containing app removes the @executable_path/../../Frameworks fallback used by keyboard extensions after sideload resigning."
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appFrameworks
                    .appendingPathComponent("RimeKitObjC.framework/RimeKitObjC")
                    .path
            ),
            "Missing RimeKitObjC.framework in the containing app removes the host-app @rpath fallback for the keyboard extension."
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: extensionFrameworks
                    .appendingPathComponent("ChineseInput.framework/ChineseInput")
                    .path
            ),
            "Missing ChineseInput.framework inside the keyboard appex causes a dyld launch crash and leaves only the grey system keyboard shell."
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: extensionFrameworks
                    .appendingPathComponent("RimeKitObjC.framework/RimeKitObjC")
                    .path
            ),
            "Missing RimeKitObjC.framework inside the keyboard appex breaks the Rime-backed Chinese keyboard at launch."
        )
    }

    private func applicationGroups(in plist: [String: Any]) -> [String] {
        plist["com.apple.security.application-groups"] as? [String] ?? []
    }

    private func propertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func yamlTargetBlock(named targetName: String, in yaml: String) throws -> String {
        var lines: [String] = []
        var isCollecting = false

        for line in yaml.components(separatedBy: .newlines) {
            if line == "  \(targetName):" {
                isCollecting = true
                lines.append(line)
                continue
            }

            if isCollecting,
               line.hasPrefix("  "),
               !line.hasPrefix("    "),
               line.hasSuffix(":") {
                break
            }

            if isCollecting {
                lines.append(line)
            }
        }

        if lines.isEmpty {
            XCTFail("Missing target block: \(targetName)")
        }
        return lines.joined(separator: "\n")
    }

    private func iosRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidate = current.appendingPathComponent("project.yml")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw XCTSkip("Apps/VoxFlowiOS root not found")
    }
}
