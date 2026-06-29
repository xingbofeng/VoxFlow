import AppKit
import XCTest
@testable import VoxFlowApp

final class AppPresentationPolicyTests: XCTestCase {
    func testAppUsesRegularForegroundActivationPolicy() {
        XCTAssertEqual(AppPresentationPolicy.activationPolicy, .regular)
        XCTAssertEqual(AppPresentationPolicy.workbenchActivationPolicy, .regular)
        XCTAssertEqual(AppPresentationPolicy.menuBarOnlyActivationPolicy, .accessory)
        XCTAssertTrue(AppPresentationPolicy.usesMainMenu)
    }

    func testAppOpensWorkbenchOnLaunchAsVisibleFallback() {
        XCTAssertTrue(AppPresentationPolicy.opensWorkbenchOnLaunch)
        XCTAssertTrue(AppPresentationPolicy.restoresWorkbenchOnReopen)
    }

    func testScreenshotCaptureKeepsVoxFlowOverlaysWhenAppIsFrontmost() {
        XCTAssertFalse(
            AppPresentationPolicy.shouldDismissVoxFlowOverlaysBeforeScreenshotCapture(
                appIsFrontmost: true
            )
        )
    }

    func testScreenshotCaptureDismissesVoxFlowOverlaysWhenAppIsNotFrontmost() {
        XCTAssertTrue(
            AppPresentationPolicy.shouldDismissVoxFlowOverlaysBeforeScreenshotCapture(
                appIsFrontmost: false
            )
        )
    }

    func testInfoPlistUsesDefaultForegroundPresentationPolicy() throws {
        let plistURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertNil(plist["LSUIElement"])
    }

    func testMainStronglyRetainsAppDelegateForStatusItemLifetime() throws {
        let main = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Sources/VoxFlowApp/App/main.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(main.contains("static let delegate = AppDelegate()"))
        XCTAssertTrue(main.contains("app.delegate = delegate"))
        XCTAssertTrue(main.contains("app.setActivationPolicy(AppPresentationPolicy.activationPolicy)"))
        XCTAssertTrue(main.contains("app.run()"))
    }

    func testAppDelegateCreatesStatusItemAfterRuntimeInitializationMatchesForegroundLaunch() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let launchRange = try XCTUnwrap(source.range(of: "func applicationDidFinishLaunching"))
        let launchSource = source[launchRange.lowerBound...]
        let bootstrapRange = try XCTUnwrap(launchSource.range(of: "AppRuntime.bootstrap()"))
        let orchestratorRange = try XCTUnwrap(launchSource.range(of: "setupDictationOrchestrator()"))
        let statusItemRange = try XCTUnwrap(launchSource.range(of: "setupStatusItem()"))
        let menuRange = try XCTUnwrap(launchSource.range(of: "setupMenu()"))

        XCTAssertLessThan(
            bootstrapRange.lowerBound,
            statusItemRange.lowerBound,
            "Match the known-good foreground launch path: initialize the app runtime before registering the status item."
        )
        XCTAssertLessThan(
            orchestratorRange.lowerBound,
            statusItemRange.lowerBound,
            "Avoid registering a placeholder status item before the menu bar button can be fully configured."
        )
        XCTAssertLessThan(statusItemRange.lowerBound, menuRange.lowerBound)
        XCTAssertFalse(launchSource.contains("DispatchQueue.main.async"))
    }

    func testStatusItemIsConfiguredDuringCreationBeforeMenuAttachment() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let setupStatusItemRange = try XCTUnwrap(source.range(of: "private func setupStatusItem()"))
        let setupStatusItemSource = source[setupStatusItemRange.lowerBound...]
        let configureRange = try XCTUnwrap(setupStatusItemSource.range(of: "StatusBarIcon.configure(statusItem)"))
        let setupMenuRange = try XCTUnwrap(setupStatusItemSource.range(of: "private func setupMenu()"))
        let setupMenuSource = setupStatusItemSource[setupMenuRange.lowerBound...]
        let attachRange = try XCTUnwrap(setupMenuSource.range(of: "menuBarCoordinator.attach(to: statusItem)"))

        XCTAssertLessThan(configureRange.lowerBound, setupMenuRange.lowerBound)
        XCTAssertNotNil(attachRange)
        XCTAssertFalse(setupMenuSource.contains("StatusBarIcon.configure(statusItem)"))
    }

    func testStatusItemAppearanceRefreshReappliesCompleteStatusBarIconConfiguration() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let refreshRange = try XCTUnwrap(source.range(of: "private func refreshStatusItemAppearance()"))
        let refreshSource = source[refreshRange.lowerBound...]

        XCTAssertTrue(refreshSource.contains("StatusBarIcon.configure(statusItem, usesGrayIcon: usesGrayIcon)"))
        XCTAssertFalse(refreshSource.contains("statusItem.button?.image?.isTemplate = true"))
    }

    func testPrelaunchCleanupResetsMenuExtraPlacementCaches() throws {
        let makefile = try String(
            contentsOf: Self.repositoryRoot().appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertTrue(makefile.contains("VoxFlowMenuBarItem"))
        XCTAssertFalse(makefile.contains("VoxFlowStatusItemMenuExtra"))
        XCTAssertTrue(makefile.contains("NSStatusItem Preferred Position"))
        XCTAssertTrue(makefile.contains("NSStatusItem Visible "))
        XCTAssertTrue(makefile.contains("NSStatusItem VisibleCC"))
        XCTAssertTrue(makefile.contains("killall ControlCenter"))
    }

    func testWindowCoordinatorRestoresDockBeforeActivationAndGatesCloseHidingOnSetting() throws {
        let coordinatorSource = try String(
            contentsOf: try Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/WindowCoordinator.swift"),
            encoding: .utf8
        )
        let mainWindowSource = try String(
            contentsOf: try Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/MainWindowController.swift"),
            encoding: .utf8
        )

        let restoreRange = try XCTUnwrap(
            coordinatorSource.range(of: "NSApp.setActivationPolicy(AppPresentationPolicy.workbenchActivationPolicy)")
        )
        let activateRange = try XCTUnwrap(
            coordinatorSource.range(of: "NSApp.activate(ignoringOtherApps: true)")
        )

        XCTAssertLessThan(
            restoreRange.lowerBound,
            activateRange.lowerBound,
            "Showing the workbench must restore the regular Dock presentation before activating the app."
        )
        XCTAssertTrue(coordinatorSource.contains("hideDockAfterWorkbenchCloses()"))
        XCTAssertTrue(coordinatorSource.contains("onClose: { [weak self] in"))
        XCTAssertTrue(coordinatorSource.contains("SettingsSystemOption.hideDockIconWhenWorkbenchCloses"))
        XCTAssertTrue(coordinatorSource.contains("AppPresentationPolicy.presentationPolicyAfterWorkbenchClose"))
        XCTAssertTrue(mainWindowSource.contains("NSWindowDelegate"))
        XCTAssertTrue(mainWindowSource.contains("func windowWillClose"))
        XCTAssertTrue(mainWindowSource.contains("onClose()"))
    }

    func testPresentationPolicyAfterWorkbenchCloseHidesDockWhenEnabled() {
        XCTAssertEqual(
            AppPresentationPolicy.presentationPolicyAfterWorkbenchClose(hideDockWhenWorkbenchCloses: true),
            AppPresentationPolicy.menuBarOnlyActivationPolicy
        )
    }

    func testPresentationPolicyAfterWorkbenchCloseKeepsRegularDockWhenDisabled() {
        XCTAssertEqual(
            AppPresentationPolicy.presentationPolicyAfterWorkbenchClose(hideDockWhenWorkbenchCloses: false),
            AppPresentationPolicy.workbenchActivationPolicy
        )
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
            domain: "AppPresentationPolicyTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
