import AppKit
@testable import VoxFlowScreenshotKit
import XCTest

@MainActor
final class ScreenRecordingHUDPanelTests: XCTestCase {
    func testHUDShowsRecordingStatusElapsedTimeAndMicrophoneState() throws {
        let panel = ScreenRecordingHUDPanel()

        panel.update(
            status: ScreenRecordingHUDStatus(
                elapsedSeconds: 75,
                audioMode: .microphone
            )
        )

        let labels = panel.hudView.subviews.compactMap { $0 as? NSTextField }
        let redDot = try XCTUnwrap(
            panel.hudView.subviews.first {
                !($0 is NSTextField) && !($0 is NSButton)
            }
        )

        XCTAssertTrue(labels.contains { $0.stringValue == "01:15" })
        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(redDot.layer?.backgroundColor, NSColor.systemRed.cgColor)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.screenSaver.rawValue)
        XCTAssertEqual(panel.sharingType, .none)
        XCTAssertEqual(panel.contentView?.frame.size.width ?? 0, panel.hudView.frame.width, accuracy: 1)
        XCTAssertEqual(panel.contentView?.frame.size.height ?? 0, panel.hudView.frame.height, accuracy: 1)
    }

    func testHUDFormatsLongElapsedTimeAndSilentMode() {
        let panel = ScreenRecordingHUDPanel()

        panel.update(
            status: ScreenRecordingHUDStatus(
                elapsedSeconds: 3_661,
                audioMode: .none
            )
        )

        let labels = panel.hudView.subviews.compactMap { $0 as? NSTextField }
        XCTAssertTrue(labels.contains { $0.stringValue == "1:01:01" })
        XCTAssertEqual(labels.count, 2)
    }

    func testHUDStopButtonInvokesCallback() throws {
        let view = ScreenRecordingHUDView(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        var stopCount = 0
        view.onStop = {
            stopCount += 1
        }

        let stopButton = try XCTUnwrap(
            view.subviews.compactMap { $0 as? NSButton }.first
        )
        stopButton.performClick(nil)

        XCTAssertEqual(stopCount, 1)
    }
}
