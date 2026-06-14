import XCTest
@testable import VoiceInputApp

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

    func testAgentComposeAlwaysCopies() async {
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
    }

    func testAgentComposeNeverInjects() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        _ = await service.deliver(
            text: "agent text",
            mode: .agentCompose,
            target: target,
            originalTarget: target
        )

        XCTAssertTrue(injector.injectedTexts.isEmpty, "Agent compose should never call inject")
    }

    func testAgentComposeCopiesEvenWhenTargetChanged() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let original = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let current = DictationTarget(bundleID: "com.apple.Safari", appName: "Safari")

        let result = await service.deliver(
            text: "agent text",
            mode: .agentCompose,
            target: current,
            originalTarget: original
        )

        // Agent compose copies regardless of target change
        XCTAssertEqual(result, .copied)
        XCTAssertEqual(clipboard.copiedTexts, ["agent text"])
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

        XCTAssertEqual(result, .injectionFailed(reason: "Accessibility permission denied"))
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
        // from the injection attempt (TextInjector leaves it there on eventCreationFailed)
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
private final class StubTextInjector: TextInjecting {
    let result: InjectionResult
    private(set) var injectedTexts: [String] = []

    init(result: InjectionResult) {
        self.result = result
    }

    func inject(_ text: String) async -> InjectionResult {
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
