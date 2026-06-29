import XCTest
@testable import VoxFlowScreenshotKit

final class VoxFlowScreenshotKitModuleTests: XCTestCase {
    func testModuleExposesInteractiveScreenshotProviderProtocol() {
        XCTAssertEqual(
            String(describing: InteractiveScreenshotProviding.self),
            "InteractiveScreenshotProviding"
        )
    }

    func testScreenshotLocalizationFindsPackagedResourceBundleInsideAppResources() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let appBundleURL = temporaryRoot.appendingPathComponent("VoxFlow.app", isDirectory: true)
        let resourcesURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let screenshotBundleURL = resourcesURL
            .appendingPathComponent(ScreenshotL10n.resourceBundleName, isDirectory: true)
        let localizedURL = screenshotBundleURL.appendingPathComponent("en.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: localizedURL, withIntermediateDirectories: true)
        try "\"toolbar.select\" = \"Select\";\n".write(
            to: localizedURL.appendingPathComponent("ScreenshotKit.strings"),
            atomically: true,
            encoding: .utf8
        )

        let bundle = ScreenshotL10n.packagedResourceBundle(
            mainBundleURL: appBundleURL,
            mainResourceURL: resourcesURL
        )

        XCTAssertEqual(bundle?.bundleURL.standardizedFileURL, screenshotBundleURL.standardizedFileURL)
    }
}
