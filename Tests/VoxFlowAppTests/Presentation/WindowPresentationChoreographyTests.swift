import XCTest
@testable import VoxFlowApp

final class WindowPresentationChoreographyTests: XCTestCase {
    func testSettingsTabMapsToWorkbenchSettingsSections() {
        XCTAssertEqual(SettingsSection(settingsTab: .asr), .dictationModels)
        XCTAssertEqual(SettingsSection(settingsTab: .llm), .correctionModels)
        XCTAssertEqual(SettingsSection(settingsTab: .shortcut), .system)
    }
}
