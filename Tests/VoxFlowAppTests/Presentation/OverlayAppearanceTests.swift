import AppKit
import XCTest
@testable import VoxFlowApp

@MainActor
final class OverlayAppearanceTests: XCTestCase {
    override func tearDown() {
        MainActor.assumeIsolated {
            for window in NSApplication.shared.windows where window.level == .floating {
                window.orderOut(nil)
            }
        }
        super.tearDown()
    }

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

    func testAgentDispatchConfirmationUsesInlineCandidateRowsInsteadOfClickPrompt() throws {
        let controller = OverlayWindowController()
        let candidates = [
            AgentSessionCard.confirmationFixture(id: "agent-1", name: "voice-input-method-mac"),
            AgentSessionCard.confirmationFixture(id: "agent-2", name: "docs-site"),
        ]

        controller.updateAgentDispatch(
            .confirmation(utterance: "嗯，什么意思吗？", candidates: candidates)
        )

        let contentView = try XCTUnwrap(controller.window?.contentView)
        let labels = contentView.descendantTextValues()
        let rows = contentView.descendantViews(withIdentifier: "agentCandidateRow")
        let defaultRows = contentView.descendantViews(withIdentifier: "agentDefaultOutputRow")

        XCTAssertTrue(controller.window?.isVisible ?? false)
        XCTAssertFalse(controller.window?.ignoresMouseEvents ?? true)
        XCTAssertFalse(controller.currentText.contains("点击选择"))
        XCTAssertTrue(labels.contains("需要确认"))
        XCTAssertTrue(labels.contains { $0.contains("嗯，什么意思吗？") })
        XCTAssertFalse(labels.contains { $0.contains("点击选择") })
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(labels.contains("1"))
        XCTAssertTrue(labels.contains("voice-input-method-mac"))
        XCTAssertTrue(labels.contains("2"))
        XCTAssertTrue(labels.contains("docs-site"))
        XCTAssertEqual(defaultRows.count, 1)
        XCTAssertTrue(labels.contains("0"))
        XCTAssertTrue(labels.contains("直接写入当前输入框"))
        XCTAssertTrue(rows.allSatisfy { $0.frame.minX <= 1 })
        XCTAssertTrue(rows.allSatisfy { $0.frame.width >= 500 })
        XCTAssertGreaterThanOrEqual(controller.window?.minSize.height ?? 0, 320)
    }

    func testAgentDispatchConfirmationNumberBadgesUseVerticallyCenteredCells() throws {
        let controller = OverlayWindowController()

        controller.updateAgentDispatch(
            .confirmation(
                utterance: "看一下这个按钮",
                candidates: [.confirmationFixture(id: "agent-1", name: "前端")]
            )
        )

        let textFields = try XCTUnwrap(controller.window?.contentView?.descendantTextFields())
        let oneLabel = try XCTUnwrap(textFields.first { $0.stringValue == "1" })
        let zeroLabel = try XCTUnwrap(textFields.first { $0.stringValue == "0" })
        XCTAssertTrue(oneLabel.cell is VerticallyCenteredTextFieldCell)
        XCTAssertTrue(zeroLabel.cell is VerticallyCenteredTextFieldCell)
    }

    func testAgentDispatchConfirmationZeroKeySelectsDefaultOutput() throws {
        let controller = OverlayWindowController()
        var selectedUtterance: String?
        controller.onAgentDefaultOutputSelected = { utterance in
            selectedUtterance = utterance
        }
        controller.updateAgentDispatch(
            .confirmation(
                utterance: "直接写到输入框",
                candidates: [.confirmationFixture(id: "agent-1", name: "前端")]
            )
        )

        let consumed = controller.performAgentConfirmationKeyForTesting(
            try XCTUnwrap(Self.keyDownEvent(keyCode: 29, characters: "0"))
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(selectedUtterance, "直接写到输入框")
    }

    func testAgentDispatchConfirmationZeroKeyDismissesConfirmationImmediately() throws {
        let controller = OverlayWindowController()
        controller.updateAgentDispatch(
            .confirmation(
                utterance: "直接写到输入框",
                candidates: [.confirmationFixture(id: "agent-1", name: "前端")]
            )
        )

        _ = controller.performAgentConfirmationKeyForTesting(
            try XCTUnwrap(Self.keyDownEvent(keyCode: 29, characters: "0"))
        )

        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testAgentDispatchConfirmationKeyboardShortcutUsesConsumingEventTap() throws {
        let sourceURL = Self.projectRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Presentation/OverlayWindowController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("CGEvent.tapCreate"))
        XCTAssertTrue(source.contains("return nil"))
        XCTAssertFalse(source.contains("addGlobalMonitorForEvents(matching: .keyDown)"))
    }

    func testAgentDispatchConfirmationCancelsPriorTemporaryMessageTimeout() async throws {
        let controller = OverlayWindowController()
        controller.showTemporaryMessage("请求超时", duration: 0.01)

        controller.updateAgentDispatch(
            .confirmation(
                utterance: "把按钮改成白色",
                candidates: [.confirmationFixture(id: "agent-1", name: "前端")]
            )
        )
        try await Task.sleep(nanoseconds: 350_000_000)

        let contentView = try XCTUnwrap(controller.window?.contentView)
        let labels = contentView.descendantTextValues()
        XCTAssertTrue(controller.window?.isVisible ?? false)
        XCTAssertTrue(labels.contains("需要确认"))
        XCTAssertTrue(labels.contains("前端"))
        XCTAssertFalse(labels.contains("请求超时"))
    }

    func testAgentDispatchConfirmationKeepsItsFrameAfterPriorResizeAnimationFinishes() async throws {
        let controller = OverlayWindowController()
        controller.show()
        controller.updateTranscription("正在处理...", isRefining: true)

        controller.updateAgentDispatch(
            .confirmation(
                utterance: "把按钮改成白色",
                candidates: [.confirmationFixture(id: "agent-1", name: "前端")]
            )
        )
        let immediateFrameHeight = controller.window?.frame.height ?? 0
        try await Task.sleep(for: .milliseconds(350))

        let finalFrameHeight = controller.window?.frame.height ?? 0
        let rows = controller.window?.contentView?
            .descendantViews(withIdentifier: "agentCandidateRow") ?? []
        let row = try XCTUnwrap(rows.first)
        XCTAssertGreaterThanOrEqual(immediateFrameHeight, 200)
        XCTAssertEqual(finalFrameHeight, immediateFrameHeight, accuracy: 1)
        XCTAssertEqual(rows.count, 1)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
    }

    func testAgentDispatchConfirmationWithoutCandidatesFallsBackToCompactFailure() {
        let controller = OverlayWindowController()

        controller.updateAgentDispatch(
            .confirmation(utterance: "检查一下按钮", candidates: [])
        )

        let rows = controller.window?.contentView?.descendantViews(withIdentifier: "agentCandidateRow") ?? []
        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(controller.currentText.contains("没有可用任务助手"))
        XCTAssertTrue(controller.currentText.contains("检查一下按钮"))
        XCTAssertLessThan(controller.window?.frame.height ?? 0, 120)
    }

    func testAgentDispatchListeningWithoutAgentsUsesCompactAdaptiveFrame() {
        let controller = OverlayWindowController()

        controller.updateAgentDispatch(.listening(agentNames: []))

        XCTAssertEqual(controller.currentText, "说出要交给任务助手的任务")
        XCTAssertEqual(controller.window?.frame.width, OverlayLayout.windowWidth(textWidth: 240))
        XCTAssertEqual(controller.window?.frame.height, OverlayLayout.minimumCapsuleHeight)
    }

    func testAgentDispatchListeningHidesAgentNamesAndShrinksAfterPriorConfirmationFrame() {
        let controller = OverlayWindowController()
        controller.updateAgentDispatch(
            .confirmation(
                utterance: "看一下这个按钮",
                candidates: [.confirmationFixture(id: "agent-1", name: "前端")]
            )
        )

        controller.updateAgentDispatch(.listening(agentNames: ["voice-input-method-mac"]))

        XCTAssertEqual(controller.currentText, "说出要交给任务助手的任务")
        XCTAssertFalse(controller.currentText.contains("voice-input-method-mac"))
        XCTAssertEqual(controller.window?.frame.width, OverlayLayout.windowWidth(textWidth: 240))
        XCTAssertEqual(controller.window?.frame.height, OverlayLayout.minimumCapsuleHeight)
    }
}

private extension NSView {
    func descendantViews(withIdentifier identifier: String) -> [NSView] {
        let matchesSelf = self.identifier?.rawValue == identifier
        return (matchesSelf ? [self] : [])
            + subviews.flatMap { $0.descendantViews(withIdentifier: identifier) }
    }

    func descendantTextValues() -> [String] {
        let ownText = (self as? NSTextField)?.stringValue
        return (ownText.map { [$0] } ?? [])
            + subviews.flatMap { $0.descendantTextValues() }
    }

    func descendantTextFields() -> [NSTextField] {
        let ownTextField = self as? NSTextField
        return (ownTextField.map { [$0] } ?? [])
            + subviews.flatMap { $0.descendantTextFields() }
    }
}

private extension OverlayAppearanceTests {
    static func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func keyDownEvent(keyCode: UInt16, characters: String) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

private extension AgentSessionCard {
    static func confirmationFixture(id: String, name: String) -> AgentSessionCard {
        AgentSessionCard(
            schemaVersion: 1,
            agentID: id,
            cli: "codex",
            command: ["codex"],
            cwd: "/tmp/project",
            repoName: "project",
            branch: "main",
            status: .active,
            displayName: name
        )
    }
}
