import AppKit
import XCTest
import VoxFlowTextInsertion
@testable import VoxFlowApp

@MainActor
final class OutputServiceTests: XCTestCase {
    func testSystemClipboardServiceCanWriteToIsolatedPasteboard() throws {
        let pasteboard = try XCTUnwrap(
            NSPasteboard(name: NSPasteboard.Name("OutputServiceTests-\(UUID().uuidString)"))
        )
        let service = SystemClipboardService(pasteboard: pasteboard)

        XCTAssertTrue(service.setString("isolated clipboard text"))

        XCTAssertEqual(pasteboard.string(forType: .string), "isolated clipboard text")
    }

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

    func testDictationSuccessUpdatesPasteLastResultStore() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let lastResultStore = InMemoryLastResultStore()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            lastResultStore: lastResultStore
        )

        let result = await service.deliver(
            text: "dictation text",
            mode: .dictation,
            target: nil,
            originalTarget: nil
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(lastResultStore.lastResultText, "dictation text")
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
        XCTAssertEqual(clipboard.copiedTexts, ["hello"])
    }

    func testAgentComposeInjectionFailureReportsCopyFailureWhenFallbackCopyFails() async {
        let injector = StubTextInjector(result: .eventCreationFailed)
        let clipboard = StubClipboardService(succeeds: false)
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )

        let result = await service.deliver(
            text: "hello",
            mode: .agentCompose,
            target: nil,
            originalTarget: nil
        )

        XCTAssertEqual(
            result,
            .copyFailed(reason: "Failed to create paste event and clipboard write failed")
        )
        XCTAssertEqual(clipboard.copiedTexts, ["hello"])
    }

    func testInjectionFailureReportsCopyFailureWhenFallbackCopyFails() async {
        let injector = StubTextInjector(result: .eventCreationFailed)
        let clipboard = StubClipboardService(succeeds: false)
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

        XCTAssertEqual(
            result,
            .copyFailed(reason: "Failed to create paste event and clipboard write failed")
        )
        XCTAssertEqual(clipboard.copiedTexts, ["hello"])
    }

    func testUnavailableInsertionReportsCopyFailureWhenFallbackCopyFails() async {
        let injector = StubTextInjector(result: .unavailable(reason: "Input mode unavailable"))
        let clipboard = StubClipboardService(succeeds: false)
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

        XCTAssertEqual(
            result,
            .copyFailed(reason: "Input mode unavailable and clipboard write failed")
        )
        XCTAssertEqual(clipboard.copiedTexts, ["hello"])
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
        XCTAssertEqual(clipboard.copiedTexts, ["hello"])
    }

    func testDeliverReadsTextInputModeProviderForEachOutput() async {
        let fastPaste = StubTextInjector(result: .success)
        let simulatedTyping = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        var mode = TextInputMode.fastPaste
        let service = DefaultOutputService(
            textInsertionCoordinator: TextInsertionCoordinator(
                fastPasteInserter: fastPaste,
                simulatedTypingInserter: simulatedTyping
            ),
            clipboardService: clipboard,
            textInputMode: { mode }
        )

        _ = await service.deliver(text: "first", mode: .dictation, target: nil, originalTarget: nil)
        mode = .simulatedTyping
        _ = await service.deliver(text: "second", mode: .dictation, target: nil, originalTarget: nil)

        XCTAssertEqual(fastPaste.injectedTexts, ["first"])
        XCTAssertEqual(simulatedTyping.injectedTexts, ["second"])
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

    func testAgentComposeInjectsIntoUnchangedTarget() async {
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

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(injector.injectedTexts, ["agent text"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testAgentComposeDoesNotOverwritePasteLastResultStore() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let lastResultStore = InMemoryLastResultStore()
        lastResultStore.setLastResultText("previous dictation")
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            lastResultStore: lastResultStore
        )

        let result = await service.deliver(
            text: "agent text",
            mode: .agentCompose,
            target: nil,
            originalTarget: nil
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(lastResultStore.lastResultText, "previous dictation")
    }

    func testAgentComposeFallsBackToClipboardWhenPermissionWouldBeDenied() async {
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

        XCTAssertEqual(result, .permissionDenied(reason: "Accessibility permission denied"))
        XCTAssertEqual(clipboard.copiedTexts, ["agent text"])
    }

    func testAgentComposeCopiesWhenTargetChanges() async {
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

        guard case .targetChanged = result else {
            return XCTFail("Expected targetChanged, got \(result)")
        }
        XCTAssertEqual(clipboard.copiedTexts, ["agent text"])
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    func testAgentComposeInjectsWhenNoOriginalTargetWasCaptured() async {
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

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(injector.injectedTexts, ["agent text"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
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

    func testInjectionFailureCopiesToClipboardExplicitly() async {
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
        XCTAssertEqual(clipboard.copiedTexts, ["fallback text"])
    }

    func testInputOnlyDeliveryDoesNotCopyWhenInjectionFails() async {
        let injector = StubTextInjector(result: .eventCreationFailed)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )

        let result = await service.deliverInputOnly(
            text: "input only text",
            mode: .dictation
        )

        XCTAssertEqual(result, .injectionFailed(reason: "Failed to create paste event"))
        XCTAssertEqual(injector.injectedTexts, ["input only text"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testInputOnlyDeliveryDoesNotCopyWhenPermissionIsDenied() async {
        let injector = StubTextInjector(result: .permissionDenied)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )

        let result = await service.deliverInputOnly(
            text: "input only text",
            mode: .dictation
        )

        XCTAssertEqual(result, .permissionDenied(reason: "Accessibility permission denied"))
        XCTAssertEqual(injector.injectedTexts, ["input only text"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testInputOnlyDeliveryDoesNotCopyWhenTextInputModeIsUnavailable() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            defaultTextInputMode: .simulatedTyping
        )

        let result = await service.deliverInputOnly(
            text: "input only text",
            mode: .dictation
        )

        XCTAssertEqual(result, .injectionFailed(reason: "Simulated typing is not available yet"))
        XCTAssertTrue(injector.injectedTexts.isEmpty)
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

    func testInjectionCancelledDoesNotUpdatePasteLastResultStore() async {
        let injector = StubTextInjector(result: .cancelled)
        let clipboard = StubClipboardService()
        let lastResultStore = InMemoryLastResultStore()
        lastResultStore.setLastResultText("previous text")
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            lastResultStore: lastResultStore
        )

        let result = await service.deliver(
            text: "cancelled text",
            mode: .dictation,
            target: nil,
            originalTarget: nil
        )

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(lastResultStore.lastResultText, "previous text")
    }

    func testOutputDeliveryLogIncludesTargetsOutputKindAndFallbackReason() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/TextProcessingBridges/OutputService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("text_output_delivered"))
        XCTAssertTrue(source.contains("outputKind="))
        XCTAssertTrue(source.contains("originalTarget="))
        XCTAssertTrue(source.contains("currentTarget="))
        XCTAssertTrue(source.contains("fallbackReason="))
    }

    private static func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw NSError(domain: "OutputServiceTests", code: 1)
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
    private let succeeds: Bool

    init(succeeds: Bool = true) {
        self.succeeds = succeeds
    }

    func setString(_ text: String) -> Bool {
        copiedTexts.append(text)
        return succeeds
    }
}
