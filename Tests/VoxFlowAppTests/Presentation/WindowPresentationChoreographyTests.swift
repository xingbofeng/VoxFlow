import XCTest
@testable import VoxFlowApp

final class WindowPresentationChoreographyTests: XCTestCase {
    func testSettingsTabMapsToSettingsDestinations() {
        XCTAssertEqual(SettingsDestination(settingsTab: .asr), .models)
        XCTAssertEqual(SettingsDestination(settingsTab: .llm), .models)
        XCTAssertEqual(SettingsDestination(settingsTab: .shortcut), .voice)
    }
}
