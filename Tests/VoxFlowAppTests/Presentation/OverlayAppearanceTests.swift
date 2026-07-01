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
        try await waitForTemporaryMessageDismissal(on: controller)

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

    private func waitForTemporaryMessageDismissal(
        on controller: OverlayWindowController,
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if controller.window?.isVisible != true, controller.currentText.isEmpty {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
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
        XCTAssertTrue(labels.contains(L10n.localize("hud.status.confirmation", comment: "")))
        XCTAssertTrue(labels.contains { $0.contains("嗯，什么意思吗？") })
        XCTAssertFalse(labels.contains { $0.contains("点击选择") })
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(labels.contains("1"))
        XCTAssertTrue(labels.contains("voice-input-method-mac"))
        XCTAssertTrue(labels.contains("2"))
        XCTAssertTrue(labels.contains("docs-site"))
        XCTAssertEqual(defaultRows.count, 1)
        XCTAssertTrue(labels.contains("0"))
        XCTAssertTrue(labels.contains(L10n.localize("hud.output.default_label", comment: "")))
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

    func testAgentDispatchConfirmationNumberKeySelectsAgentWithOriginalUtterance() throws {
        let controller = OverlayWindowController()
        var selectedAgentID: String?
        var selectedUtterance: String?
        controller.onAgentCandidateSelected = { agentID, utterance in
            selectedAgentID = agentID
            selectedUtterance = utterance
        }
        controller.updateAgentDispatch(
            .confirmation(
                utterance: "把这段选中文本交给任务助手",
                candidates: [.confirmationFixture(id: "agent-1", name: "前端")]
            )
        )

        let consumed = controller.performAgentConfirmationKeyForTesting(
            try XCTUnwrap(Self.keyDownEvent(keyCode: 18, characters: "1"))
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(selectedAgentID, "agent-1")
        XCTAssertEqual(selectedUtterance, "把这段选中文本交给任务助手")
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testAgentDispatchConfirmationNumberKeysOneThroughNineSelectVisibleCandidates() throws {
        let keyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for index in 0..<9 {
            let controller = OverlayWindowController()
            var selectedAgentID: String?
            var selectedUtterance: String?
            controller.onAgentCandidateSelected = { agentID, utterance in
                selectedAgentID = agentID
                selectedUtterance = utterance
            }
            let candidates = (1...10).map { number in
                AgentSessionCard.confirmationFixture(
                    id: "agent-\(number)",
                    name: "助手 \(number)"
                )
            }
            controller.updateAgentDispatch(
                .confirmation(
                    utterance: "把选中文本交给任务助手",
                    candidates: candidates
                )
            )

            let consumed = controller.performAgentConfirmationKeyForTesting(
                try XCTUnwrap(Self.keyDownEvent(keyCode: keyCodes[index], characters: "\(index + 1)"))
            )

            XCTAssertTrue(consumed)
            XCTAssertEqual(selectedAgentID, "agent-\(index + 1)")
            XCTAssertEqual(selectedUtterance, "把选中文本交给任务助手")
        }
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

    func testAgentDispatchConfirmationEscapeCancelsWithoutSelectingOutput() throws {
        let controller = OverlayWindowController()
        var didSelectCandidate = false
        var didSelectDefaultOutput = false
        controller.onAgentCandidateSelected = { _, _ in
            didSelectCandidate = true
        }
        controller.onAgentDefaultOutputSelected = { _ in
            didSelectDefaultOutput = true
        }
        controller.updateAgentDispatch(
            .confirmation(
                utterance: "取消这次任务助手确认",
                candidates: [.confirmationFixture(id: "agent-1", name: "前端")]
            )
        )

        let consumed = controller.performAgentConfirmationKeyForTesting(
            try XCTUnwrap(Self.keyDownEvent(keyCode: 53, characters: "\u{1b}"))
        )

        XCTAssertTrue(consumed)
        XCTAssertFalse(didSelectCandidate)
        XCTAssertFalse(didSelectDefaultOutput)
        XCTAssertFalse(controller.window?.isVisible ?? true)
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
        XCTAssertTrue(labels.contains(L10n.localize("hud.status.confirmation", comment: "")))
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
        XCTAssertTrue(controller.currentText.contains(L10n.localize("hud.no_agent_available", comment: "")))
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

    func testAgentRuntimeHUDRestoresTaskSummaryAfterTechnicalStreamingOutput() {
        let controller = OverlayWindowController()
        controller.updateAgentComposeStatus(.runtimeProcessing(summary: "正在做 PPT"))

        controller.updateStreamingText("% Total    % Received % Xferd  Average Speed   Time")
        controller.updateAgentComposeStatus(.runtimeProcessing())

        XCTAssertEqual(controller.currentText, "正在做 PPT")
    }

    func testSelectionActionCardUsesExistingHUDWithFourActions() throws {
        let controller = OverlayWindowController()

        controller.showSelectionActions(
            SelectionActionCardPresentation(selectedText: "Artificial intelligence changes how we work.")
        )

        let contentView = try XCTUnwrap(controller.window?.contentView)
        let labels = contentView.descendantTextValues()
        let actionCard = try XCTUnwrap(contentView.descendantViews(withIdentifier: "selectionActionCard").first)
        let actionTiles = contentView.descendantViews(withIdentifier: "selectionActionTile")

        XCTAssertTrue(controller.window?.isVisible ?? false)
        XCTAssertFalse(controller.window?.ignoresMouseEvents ?? true)
        XCTAssertTrue(labels.contains("划词动作"))
        XCTAssertTrue(labels.contains("翻译"))
        XCTAssertTrue(labels.contains("总结"))
        XCTAssertTrue(labels.contains("任务助手"))
        XCTAssertTrue(labels.contains("问 AI"))
        XCTAssertFalse(labels.contains("朗读"))
        XCTAssertEqual(actionTiles.count, 4)
        XCTAssertLessThanOrEqual(controller.window?.frame.width ?? 0, 400)
        XCTAssertLessThanOrEqual(controller.window?.frame.height ?? 0, 260)
        let tileFrames = actionTiles.map { $0.convert($0.bounds, to: actionCard) }
        let firstMidY = try XCTUnwrap(tileFrames.first?.midY)
        XCTAssertTrue(tileFrames.allSatisfy { abs($0.midY - firstMidY) <= 2 })
        for frame in tileFrames {
            XCTAssertEqual(frame.width, frame.height, accuracy: 12)
            XCTAssertGreaterThanOrEqual(frame.width, 78)
            XCTAssertLessThanOrEqual(frame.width, 96)
        }
        XCTAssertLessThan(tileFrames[0].maxX, tileFrames[1].minX)
        XCTAssertLessThan(tileFrames[1].maxX, tileFrames[2].minX)
        XCTAssertLessThan(tileFrames[2].maxX, tileFrames[3].minX)
        XCTAssertTrue(contentView.descendantViews(withIdentifier: "agentCandidateRow").isEmpty)
    }

    func testSelectionActionTileVisibleTextClickSelectsAction() throws {
        let controller = OverlayWindowController()
        var selectedAction: SelectionActionKind?
        var selectedText: String?
        controller.onSelectionActionSelected = { action, text in
            selectedAction = action
            selectedText = text
        }

        controller.showSelectionActions(
            SelectionActionCardPresentation(selectedText: "Click through visible tile content")
        )

        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        let translateLabel = try XCTUnwrap(
            contentView.descendantTextFields().first { $0.stringValue == "翻译" }
        )
        let clickPointInContent = translateLabel.convert(
            NSPoint(x: translateLabel.bounds.midX, y: translateLabel.bounds.midY),
            to: contentView
        )
        let clickPointInWindow = contentView.convert(clickPointInContent, to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: clickPointInWindow,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        contentView.hitTest(clickPointInContent)?.mouseDown(with: event)

        XCTAssertEqual(selectedAction, .translate)
        XCTAssertEqual(selectedText, "Click through visible tile content")
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testSelectionActionCardDisablesTemporaryMessageClickRecognizer() throws {
        let controller = OverlayWindowController()

        controller.showSelectionActions(
            SelectionActionCardPresentation(selectedText: "Tile clicks should not be intercepted")
        )

        let contentView = try XCTUnwrap(controller.window?.contentView)
        let enabledRecognizers = contentView.gestureRecognizers.filter(\.isEnabled)

        XCTAssertTrue(enabledRecognizers.isEmpty)
    }

    func testSelectionActionCardUsesSelectionAnchorBeforeBottomTrailingFallback() throws {
        let controller = OverlayWindowController()
        let anchor = NSRect(x: 240, y: 520, width: 320, height: 24)

        controller.showSelectionActions(
            SelectionActionCardPresentation(selectedText: "Place this beside the current work"),
            anchor: anchor
        )

        let window = try XCTUnwrap(controller.window)
        let frame = window.frame
        XCTAssertEqual(frame.minX, anchor.minX, accuracy: 1)
        XCTAssertLessThanOrEqual(frame.maxY, anchor.minY - 10)

        controller.showSelectionActions(
            SelectionActionCardPresentation(selectedText: "Fallback when selection rect is unavailable"),
            anchor: nil
        )

        let fallbackFrame = try XCTUnwrap(controller.window?.frame)
        let visibleFrame = try XCTUnwrap(controller.window?.screen?.visibleFrame)
        let expectedFallback = WindowPlacementPolicy.bottomTrailingFrame(
            windowSize: fallbackFrame.size,
            visibleFrame: visibleFrame,
            trailingMargin: 24,
            bottomMargin: 28
        )
        XCTAssertEqual(fallbackFrame.origin.x, expectedFallback.origin.x, accuracy: 1)
        XCTAssertEqual(fallbackFrame.origin.y, expectedFallback.origin.y, accuracy: 1)
    }

    func testSelectionActionCardNumberKeySelectsActionAndDismisses() throws {
        let controller = OverlayWindowController()
        var selectedAction: SelectionActionKind?
        var selectedText: String?
        controller.onSelectionActionSelected = { action, text in
            selectedAction = action
            selectedText = text
        }
        controller.showSelectionActions(
            SelectionActionCardPresentation(selectedText: "Explain this API")
        )

        let consumed = controller.performSelectionActionKeyForTesting(
            try XCTUnwrap(Self.keyDownEvent(keyCode: 19, characters: "2"))
        )

        XCTAssertTrue(consumed)
        XCTAssertEqual(selectedAction, .summarize)
        XCTAssertEqual(selectedText, "Explain this API")
        XCTAssertFalse(controller.window?.isVisible ?? true)
    }

    func testSelectionActionCardEscapeCancelsWithoutSelectingAction() throws {
        let controller = OverlayWindowController()
        var didSelectAction = false
        controller.onSelectionActionSelected = { _, _ in
            didSelectAction = true
        }
        controller.showSelectionActions(
            SelectionActionCardPresentation(selectedText: "Cancel this card")
        )

        let consumed = controller.performSelectionActionKeyForTesting(
            try XCTUnwrap(Self.keyDownEvent(keyCode: 53, characters: "\u{1b}"))
        )

        XCTAssertTrue(consumed)
        XCTAssertFalse(didSelectAction)
        XCTAssertFalse(controller.window?.isVisible ?? true)
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
