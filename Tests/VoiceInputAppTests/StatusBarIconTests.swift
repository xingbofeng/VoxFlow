import AppKit
import XCTest
@testable import VoiceInputApp

@MainActor
final class StatusBarIconTests: XCTestCase {
    func testStatusItemUsesCompactIconOnlyPresentation() {
        XCTAssertEqual(StatusBarIcon.visibleTitle, "")
        XCTAssertEqual(StatusBarIcon.accessibilityName, "随声写")
        XCTAssertEqual(StatusBarIcon.imagePosition, .imageOnly)
        XCTAssertNil(StatusBarIcon.tooltip)
        XCTAssertEqual(StatusBarIcon.autosaveName, "VoxFlowStatusItem")
        XCTAssertEqual(StatusBarIcon.buttonIdentifier.rawValue, "VoxFlowStatusBarButton")
        XCTAssertEqual(StatusBarIcon.preferredLength, NSStatusItem.squareLength)
    }

    func testStatusBarIconUsesTemplateMenuBarImage() throws {
        let image = try XCTUnwrap(StatusBarIcon.makeImage())

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.accessibilityDescription, "随声写")
    }

    func testStatusItemClearsAutomaticallyPersistedHiddenState() {
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

        XCTAssertEqual(statusItem.autosaveName, StatusBarIcon.autosaveName)
        XCTAssertTrue(statusItem.isVisible)
    }
}
