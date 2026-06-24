import AppKit
import XCTest
@testable import VoxFlowApp

@MainActor
final class StatusBarIconTests: XCTestCase {
    func testStatusItemUsesVisibleMenuBarPresentation() {
        XCTAssertEqual(StatusBarIcon.visibleTitle, "")
        XCTAssertEqual(StatusBarIcon.accessibilityName, "码上写")
        XCTAssertEqual(StatusBarIcon.imagePosition, .imageOnly)
        XCTAssertNil(StatusBarIcon.tooltip)
        XCTAssertEqual(StatusBarIcon.autosaveName, "VoxFlowStatusItem")
        XCTAssertTrue(StatusBarIcon.persistedAutosaveNames.contains(StatusBarIcon.autosaveName))
        XCTAssertTrue(StatusBarIcon.persistedAutosaveNames.contains("Item-0"))
        XCTAssertTrue(StatusBarIcon.persistedAutosaveNames.contains("VoxFlowStatusItemRuntime"))
        XCTAssertEqual(StatusBarIcon.buttonIdentifier.rawValue, "VoxFlowStatusBarButton")
        XCTAssertEqual(StatusBarIcon.preferredLength, NSStatusItem.squareLength)
        XCTAssertEqual(
            StatusBarIcon.persistedBundleIdentifiers,
            ["com.voxflow.app", "com.voiceinput.app"]
        )
    }

    func testConfigureAppliesCompactVisibleIconAndRestoresVisibility() throws {
        try skipSystemStatusBarOnHeadlessCI()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem.isVisible = false

        StatusBarIcon.configure(statusItem)

        let button = try XCTUnwrap(statusItem.button)
        XCTAssertTrue(statusItem.isVisible)
        XCTAssertEqual(statusItem.length, NSStatusItem.squareLength)
        XCTAssertEqual(
            statusItem.autosaveName,
            NSStatusItem.AutosaveName(StatusBarIcon.autosaveName)
        )
        XCTAssertEqual(button.title, "")
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.image?.accessibilityDescription, "码上写")
        XCTAssertEqual(button.image?.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(button.image?.isTemplate, true)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.identifier, StatusBarIcon.buttonIdentifier)
        XCTAssertNil(button.contentTintColor)
        XCTAssertEqual(button.accessibilityLabel(), "码上写")
        XCTAssertFalse(
            try statusBarIconSource().contains("highlightsBy = []"),
            "Status item should keep AppKit's natural menu bar highlight behavior."
        )
    }

    func testConfigureDoesNotOverrideStatusButtonHighlightMask() throws {
        XCTAssertFalse(
            try statusBarIconSource().contains("highlightsBy = []"),
            "Custom highlight masks make the menu bar item diverge from the native status item behavior."
        )
    }

    func testConfigureUsesStableAutosaveNameAfterClearingHiddenState() throws {
        try skipSystemStatusBarOnHeadlessCI()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem.autosaveName = NSStatusItem.AutosaveName(
            "test.StatusBarIcon.hidden.\(UUID().uuidString)"
        )

        StatusBarIcon.configure(statusItem)

        XCTAssertEqual(
            statusItem.autosaveName,
            NSStatusItem.AutosaveName(StatusBarIcon.autosaveName)
        )
        XCTAssertNotEqual(statusItem.autosaveName, NSStatusItem.AutosaveName("VoxFlowStatusItemRuntime"))
        XCTAssertTrue(statusItem.isVisible)
    }

    func testConfigureReappliesTemplateImageWhenButtonContentWasBlanked() throws {
        try skipSystemStatusBarOnHeadlessCI()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        let button = try XCTUnwrap(statusItem.button)
        button.title = ""
        button.image = nil

        StatusBarIcon.configure(statusItem, usesGrayIcon: true)

        XCTAssertEqual(button.title, "")
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.image?.isTemplate, true)
        XCTAssertEqual(button.contentTintColor, .secondaryLabelColor)
    }

    func testStatusItemClearsAutomaticallyPersistedHiddenState() throws {
        try skipSystemStatusBarOnHeadlessCI()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        let persistedName = NSStatusItem.AutosaveName(
            "test.StatusBarIcon.\(UUID().uuidString)"
        )
        statusItem.autosaveName = persistedName
        statusItem.isVisible = false

        StatusBarIcon.restoreVisibility(of: statusItem)

        XCTAssertNotEqual(statusItem.autosaveName, persistedName)
        XCTAssertEqual(
            statusItem.autosaveName,
            NSStatusItem.AutosaveName(StatusBarIcon.autosaveName)
        )
        XCTAssertTrue(statusItem.isVisible)
    }

    func testStatusItemUsesStableAutosaveNameWhenRestoringVisibility() throws {
        try skipSystemStatusBarOnHeadlessCI()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        let persistedName = NSStatusItem.AutosaveName(
            "test.StatusBarIcon.hidden.\(UUID().uuidString)"
        )
        statusItem.autosaveName = persistedName
        statusItem.isVisible = false

        StatusBarIcon.restoreVisibility(of: statusItem)

        XCTAssertTrue(statusItem.isVisible)
        XCTAssertEqual(
            statusItem.autosaveName,
            NSStatusItem.AutosaveName(StatusBarIcon.autosaveName)
        )
        XCTAssertNotEqual(statusItem.autosaveName, persistedName)
    }

    func testClearsLegacyAndCurrentPersistedStatusItemDefaultsAtRuntime() {
        let currentSuite = "test.StatusBarIcon.current.\(UUID().uuidString)"
        let legacySuite = "test.StatusBarIcon.legacy.\(UUID().uuidString)"
        let currentDefaults = UserDefaults(suiteName: currentSuite)!
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer {
            currentDefaults.removePersistentDomain(forName: currentSuite)
            legacyDefaults.removePersistentDomain(forName: legacySuite)
        }
        for defaults in [currentDefaults, legacyDefaults] {
            defaults.set(42, forKey: "NSStatusItem Preferred Position VoxFlowStatusItem")
            defaults.set(false, forKey: "NSStatusItem VisibleCC VoxFlowStatusItem")
            defaults.set(43, forKey: "NSStatusItem Preferred Position VoxFlowStatusItemV2")
            defaults.set(false, forKey: "NSStatusItem VisibleCC VoxFlowStatusItemV2")
            defaults.set(44, forKey: "NSStatusItem Preferred Position VoxFlowStatusItemRuntime")
            defaults.set(false, forKey: "NSStatusItem VisibleCC VoxFlowStatusItemRuntime")
            defaults.set(46, forKey: "NSStatusItem Preferred Position \(StatusBarIcon.autosaveName)")
            defaults.set(false, forKey: "NSStatusItem Visible \(StatusBarIcon.autosaveName)")
            defaults.set(false, forKey: "NSStatusItem VisibleCC \(StatusBarIcon.autosaveName)")
            defaults.set(45, forKey: "NSStatusItem Preferred Position Item-0")
            defaults.set(false, forKey: "NSStatusItem Visible Item-0")
            defaults.set(false, forKey: "NSStatusItem VisibleCC Item-0")
            defaults.set(true, forKey: "VoxFlowStatusItemPlacementResetV1")
            defaults.set("keep", forKey: "Unrelated")
        }

        StatusBarIcon.clearPersistedVisibilityState(bundleIdentifiers: [currentSuite, legacySuite])

        for defaults in [currentDefaults, legacyDefaults] {
            XCTAssertNil(defaults.object(forKey: "NSStatusItem Preferred Position VoxFlowStatusItem"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem VisibleCC VoxFlowStatusItem"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem Preferred Position VoxFlowStatusItemV2"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem VisibleCC VoxFlowStatusItemV2"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem Preferred Position VoxFlowStatusItemRuntime"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem VisibleCC VoxFlowStatusItemRuntime"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem Preferred Position \(StatusBarIcon.autosaveName)"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem Visible \(StatusBarIcon.autosaveName)"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem VisibleCC \(StatusBarIcon.autosaveName)"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem Preferred Position Item-0"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem Visible Item-0"))
            XCTAssertNil(defaults.object(forKey: "NSStatusItem VisibleCC Item-0"))
            XCTAssertNil(defaults.object(forKey: "VoxFlowStatusItemPlacementResetV1"))
            XCTAssertEqual(defaults.string(forKey: "Unrelated"), "keep")
        }
    }

    func testCurrentBundleVisibilityStateUsesStandardDefaultsInsteadOfSuiteName() {
        let defaults = UserDefaults.standard
        defaults.set(42, forKey: "NSStatusItem Preferred Position VoxFlowStatusItem")
        defaults.set(false, forKey: "NSStatusItem VisibleCC VoxFlowStatusItem")
        defaults.set(false, forKey: "NSStatusItem Visible \(StatusBarIcon.autosaveName)")
        defaults.set(false, forKey: "NSStatusItem VisibleCC VoxFlowStatusItemRuntime")
        defaults.set(false, forKey: "NSStatusItem VisibleCC Item-0")
        defaults.set(true, forKey: "VoxFlowStatusItemPlacementResetV1")
        defer {
            defaults.removeObject(forKey: "NSStatusItem Preferred Position VoxFlowStatusItem")
            defaults.removeObject(forKey: "NSStatusItem VisibleCC VoxFlowStatusItem")
            defaults.removeObject(forKey: "NSStatusItem Visible \(StatusBarIcon.autosaveName)")
            defaults.removeObject(forKey: "NSStatusItem VisibleCC VoxFlowStatusItemRuntime")
            defaults.removeObject(forKey: "NSStatusItem VisibleCC Item-0")
            defaults.removeObject(forKey: "VoxFlowStatusItemPlacementResetV1")
        }
        var requestedSuites: [String] = []

        StatusBarIcon.clearPersistedVisibilityState(
            bundleIdentifiers: [ProductBrand.bundleIdentifier],
            defaultsFactory: { suiteName in
                requestedSuites.append(suiteName)
                return nil
            }
        )

        XCTAssertTrue(requestedSuites.isEmpty)
        XCTAssertNil(defaults.object(forKey: "NSStatusItem Preferred Position VoxFlowStatusItem"))
        XCTAssertNil(defaults.object(forKey: "NSStatusItem VisibleCC VoxFlowStatusItem"))
        XCTAssertNil(defaults.object(forKey: "NSStatusItem Visible \(StatusBarIcon.autosaveName)"))
        XCTAssertNil(defaults.object(forKey: "NSStatusItem VisibleCC VoxFlowStatusItemRuntime"))
        XCTAssertNil(defaults.object(forKey: "NSStatusItem VisibleCC Item-0"))
        XCTAssertNil(defaults.object(forKey: "VoxFlowStatusItemPlacementResetV1"))
    }

    private func skipSystemStatusBarOnHeadlessCI() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["CI"] == "true",
            "NSStatusBar.system requires a fully initialized WindowServer session."
        )
    }

    private func statusBarIconSource() throws -> String {
        try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/AppKitAdapters/StatusBarIcon.swift"),
            encoding: .utf8
        )
    }

    private static func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
