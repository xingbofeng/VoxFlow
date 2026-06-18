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

        XCTAssertEqual(items.map(\.title), ["辅助功能", "麦克风", "语音识别", "屏幕录制"])
        XCTAssertEqual(items.map(\.granted), [true, true, false, false])
        XCTAssertEqual(items[2].status, "未授权")
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

        XCTAssertEqual(items.map(\.title), ["麦克风", "语音识别"])
        XCTAssertEqual(items.map(\.status), ["未授权", "已授权"])
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
