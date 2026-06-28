import XCTest
@testable import VoxFlowApp

final class PermissionGuideContentTests: XCTestCase {
    func testAllPermissionItemsExposeExpectedStatusesAndDestinations() {
        let items = PermissionGuideContent.allPermissionItems(
            microphonePermission: .granted,
            speechPermission: .denied,
            accessibilityTrusted: true,
            screenRecordingGranted: false,
            engineType: .qwen3
        )

        XCTAssertEqual(
            items.map(\.title),
            [
                L10n.localize("permission.item.accessibility_title"),
                L10n.localize("permission.item.microphone_title"),
                L10n.localize("permission.item.speech_title"),
                L10n.localize("permission.item.screen_recording_title")
            ]
        )
        XCTAssertEqual(items.map(\.granted), [true, true, false, false])
        XCTAssertEqual(items[2].status, L10n.localize("permission.status.denied"))
        XCTAssertEqual(
            items[0].settingsURL,
            PermissionGuideContent.systemSettingsURL(for: .accessibility)
        )
        XCTAssertEqual(
            items[3].settingsURL,
            PermissionGuideContent.systemSettingsURL(for: .screenRecording)
        )
    }

    func testRecordingPermissionItemsUseCurrentPermissionStates() {
        let items = PermissionGuideContent.recordingPermissionItems(
            microphonePermission: .denied,
            speechPermission: .granted
        )

        XCTAssertEqual(items.map(\.title), [
            L10n.localize("permission.item.microphone_title"),
            L10n.localize("permission.item.speech_title"),
        ])
        XCTAssertEqual(items.map(\.status), [
            L10n.localize("permission.status.denied"),
            L10n.localize("permission.status.granted"),
        ])
        XCTAssertEqual(items.map(\.granted), [false, true])
    }

    @MainActor
    func testSystemSettingsURLMatchesSettingsViewModelRouting() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = SettingsViewModel(environment: environment)

        XCTAssertEqual(
            PermissionGuideContent.systemSettingsURL(for: .microphone),
            viewModel.systemSettingsURL(for: .microphone)
        )
        XCTAssertEqual(
            PermissionGuideContent.systemSettingsURL(for: .speech),
            viewModel.systemSettingsURL(for: .speech)
        )
        XCTAssertEqual(
            PermissionGuideContent.systemSettingsURL(for: .accessibility),
            viewModel.systemSettingsURL(for: .accessibility)
        )
        XCTAssertEqual(
            PermissionGuideContent.systemSettingsURL(for: .screenRecording),
            viewModel.systemSettingsURL(for: .screenRecording)
        )
    }
}
