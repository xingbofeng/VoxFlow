import XCTest
import VoxFlowTextInsertion
@testable import VoxFlowApp

@MainActor
final class OutputServiceTests: XCTestCase {
    // MARK: - Dictation mode: target unchanged -> inject

    func testDictationSuccessInjectsWhenTargetUnchanged() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: target,
            originalTarget: target
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(injector.injectedTexts, ["hello"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testDictationInjectsWhenBothTargetsNil() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: nil,
            originalTarget: nil
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(injector.injectedTexts, ["hello"])
    }

    func testAutomaticTextInputModeUsesCurrentFastPastePath() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: nil,
            originalTarget: nil,
            textInputMode: .automatic
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(injector.injectedTexts, ["hello"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testFastPasteTextInputModeUsesCurrentFastPastePath() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: nil,
            originalTarget: nil,
            textInputMode: .fastPaste
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(injector.injectedTexts, ["hello"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testSimulatedTypingModeFailsRecoverablyUntilTypingInserterExists() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: nil,
            originalTarget: nil,
            textInputMode: .simulatedTyping
        )

        XCTAssertEqual(result, .injectionFailed(reason: "Simulated typing is not available yet"))
        XCTAssertTrue(injector.injectedTexts.isEmpty)
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testSimulatedTypingModeUsesCoordinatorWhenAvailable() async {
        let fastPaste = StubTextInjector(result: .success)
        let simulatedTyping = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInsertionCoordinator: TextInsertionCoordinator(
                fastPasteInserter: fastPaste,
                simulatedTypingInserter: simulatedTyping
            ),
            clipboardService: clipboard
        )

        let result = await service.deliver(
            text: "typed text",
            mode: .dictation,
            target: nil,
            originalTarget: nil,
            textInputMode: .simulatedTyping
        )

        XCTAssertEqual(result, .injected)
        XCTAssertTrue(fastPaste.injectedTexts.isEmpty)
        XCTAssertEqual(simulatedTyping.injectedTexts, ["typed text"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testDefaultTextInputModeAppliesToExistingDeliverSignature() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            defaultTextInputMode: .simulatedTyping
        )

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: nil,
            originalTarget: nil
        )

        XCTAssertEqual(result, .injectionFailed(reason: "Simulated typing is not available yet"))
        XCTAssertTrue(injector.injectedTexts.isEmpty)
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    // MARK: - Dictation mode: app changed -> copy

    func testDictationCopiesWhenAppChanged() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let original = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let current = DictationTarget(bundleID: "com.apple.Safari", appName: "Safari")

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: current,
            originalTarget: original
        )

        XCTAssertEqual(result, .targetChanged(reason: "Target application changed from Editor to Safari"))
        XCTAssertEqual(clipboard.copiedTexts, ["hello"])
        XCTAssertTrue(injector.injectedTexts.isEmpty, "Should not inject when app changed")
    }

    // MARK: - Dictation mode: window changed -> copy

    func testDictationCopiesWhenWindowChanged() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let original = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowID: "win-1",
            windowTitle: "Doc A"
        )
        let current = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowID: "win-2",
            windowTitle: "Doc B"
        )

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: current,
            originalTarget: original
        )

        XCTAssertEqual(result, .targetChanged(reason: "Target window changed"))
        XCTAssertEqual(clipboard.copiedTexts, ["hello"])
        XCTAssertTrue(injector.injectedTexts.isEmpty, "Should not inject when window changed")
    }

    func testDictationInjectsWhenWindowIDWasNil() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let original = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowID: nil
        )
        let current = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowID: "win-1"
        )

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: current,
            originalTarget: original
        )

        // Window ID was nil originally, so we don't consider it changed
        XCTAssertEqual(result, .injected)
        XCTAssertEqual(injector.injectedTexts, ["hello"])
    }

    // MARK: - Agent compose mode

    func testAgentComposeCopiesWhenTargetUnchanged() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        let result = await service.deliver(
            text: "agent text",
            mode: .agentCompose,
            target: target,
            originalTarget: target
        )

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(clipboard.copiedTexts, ["agent text"])
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    func testAgentComposeCopiesWithoutInvokingInjectorWhenInjectorWouldFail() async {
        let injector = StubTextInjector(result: .permissionDenied)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        let result = await service.deliver(
            text: "agent text",
            mode: .agentCompose,
            target: target,
            originalTarget: target
        )

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(clipboard.copiedTexts, ["agent text"])
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    func testAgentComposeCopiesWhenTargetChanged() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        let result = await service.deliver(
            text: "agent text",
            mode: .agentCompose,
            target: DictationTarget(bundleID: "com.apple.Safari", appName: "Safari"),
            originalTarget: target
        )

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(clipboard.copiedTexts, ["agent text"])
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    func testAgentComposeCopiesWhenNoOriginalTargetWasCaptured() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let result = await service.deliver(
            text: "agent text",
            mode: .agentCompose,
            target: nil,
            originalTarget: nil
        )

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(clipboard.copiedTexts, ["agent text"])
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    // MARK: - In-app text target

    func testInAppTextTargetWritesTextWithoutUsingClipboardOrInjector() {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        var writtenText: String?

        let result = service.deliverToInAppTextTarget(
            text: "note text",
            target: InAppTextOutputTarget { text in
                writtenText = text
            }
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(writtenText, "note text")
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    // MARK: - Injection failure handling

    func testInjectionPermissionDeniedCopiesToClipboard() async {
        let injector = StubTextInjector(result: .permissionDenied)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        let result = await service.deliver(
            text: "fallback text",
            mode: .dictation,
            target: target,
            originalTarget: target
        )

        XCTAssertEqual(result, .permissionDenied(reason: "Accessibility permission denied"))
        XCTAssertEqual(result.kind, .permissionDenied)
        XCTAssertEqual(clipboard.copiedTexts, ["fallback text"])
    }

    func testInjectionFailureKeepsTextInClipboard() async {
        let injector = StubTextInjector(result: .eventCreationFailed)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        let result = await service.deliver(
            text: "fallback text",
            mode: .dictation,
            target: target,
            originalTarget: target
        )

        XCTAssertEqual(result, .injectionFailed(reason: "Failed to create paste event"))
        // Clipboard service was NOT called again — text is already on clipboard
        // from the fast paste attempt (the inserter leaves it there on eventCreationFailed)
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testInjectionCancelledReturnsCancelled() async {
        let injector = StubTextInjector(result: .cancelled)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        let result = await service.deliver(
            text: "cancelled text",
            mode: .dictation,
            target: target,
            originalTarget: target
        )

        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
        XCTAssertEqual(injector.injectedTexts, ["cancelled text"])
    }
}

// MARK: - Test Doubles

@MainActor
private final class StubTextInjector: TextInserting {
    let result: TextInsertionResult
    private(set) var injectedTexts: [String] = []

    init(result: TextInsertionResult) {
        self.result = result
    }

    func insert(_ text: String) async -> TextInsertionResult {
        injectedTexts.append(text)
        return result
    }
}

private final class StubClipboardService: ClipboardSetting {
    private(set) var copiedTexts: [String] = []

    func setString(_ text: String) {
        copiedTexts.append(text)
    }
}
