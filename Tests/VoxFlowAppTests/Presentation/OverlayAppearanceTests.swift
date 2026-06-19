import AppKit
import XCTest
@testable import VoxFlowApp

@MainActor
final class OverlayAppearanceTests: XCTestCase {
    func testHUDUsesOpaqueWhiteBackground() {
        let color = OverlayAppearance.backgroundColor.usingColorSpace(.deviceRGB)

        XCTAssertEqual(color?.redComponent, 1)
        XCTAssertEqual(color?.greenComponent, 1)
        XCTAssertEqual(color?.blueComponent, 1)
        XCTAssertEqual(color?.alphaComponent, 0.98)
    }

    func testStatusTextCellCentersItsDrawingRectVertically() {
        let cell = VerticallyCenteredTextFieldCell(textCell: "听写中")
        cell.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let bounds = NSRect(x: 0, y: 0, width: 72, height: 26)

        let drawingRect = cell.drawingRect(forBounds: bounds)

        XCTAssertEqual(drawingRect.midY, bounds.midY, accuracy: 0.5)
    }

    func testShowMakesHUDOpaqueImmediately() {
        let controller = OverlayWindowController()

        controller.show()

        XCTAssertEqual(controller.window?.alphaValue, 1.0)
    }

    func testTemporaryTimeoutMessageDismissesHUD() async throws {
        let controller = OverlayWindowController()
        controller.showTemporaryMessage("请求超时", duration: 0.01)

        XCTAssertEqual(controller.currentText, "请求超时")
        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertFalse(controller.window?.isVisible ?? true)
        XCTAssertEqual(controller.currentText, "")
    }

    func testStaleDismissCompletionDoesNotHideNewTimeoutMessage() async throws {
        let controller = OverlayWindowController()
        controller.show()
        controller.dismiss()
        controller.showTemporaryMessage("请求超时", duration: 0.5)

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(controller.window?.isVisible ?? false)
        XCTAssertEqual(controller.currentText, "请求超时")

        let deadline = ContinuousClock.now + .seconds(2)
        while controller.window?.isVisible == true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(controller.window?.isVisible ?? true)
        XCTAssertEqual(controller.currentText, "")
    }

    func testTemporaryMessageAutoDismissDoesNotHideNewRecordingHUD() async throws {
        let controller = OverlayWindowController()
        controller.showTemporaryMessage("请求超时", duration: 0.01)
        controller.show()
        controller.updateTranscription("", isRefining: false)

        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertTrue(controller.window?.isVisible ?? false)
        XCTAssertEqual(controller.currentText, "正在聆听...")
    }

    func testTemporaryMessageCanInvokeClickAction() {
        let controller = OverlayWindowController()
        var didClick = false

        controller.showTemporaryMessage("请求超时", duration: 1.0) {
            didClick = true
        }
        controller.performTemporaryMessageClickForTesting()

        XCTAssertTrue(didClick)
    }
}
