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

    func testGeneralPasteboardWriterCanMarkInternalWrites() throws {
        let pasteboard = try XCTUnwrap(
            NSPasteboard(name: NSPasteboard.Name("OutputServiceTests-\(UUID().uuidString)"))
        )
        let guarder = ClipboardInternalWriteGuard()
        let writer = GeneralPasteboardWriter(
            pasteboard: pasteboard,
            internalWriteGuard: guarder
        )

        writer.copy("internal dashboard copy")

        XCTAssertEqual(pasteboard.string(forType: .string), "internal dashboard copy")
        XCTAssertTrue(pasteboard.types?.contains(.voxFlowInternalMarker) == true)
        XCTAssertTrue(guarder.shouldIgnore(changeCount: pasteboard.changeCount, types: pasteboard.types ?? []))
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

    func testSuccessfulInsertionRecordsRecentTextOutputForClipboardSuppression() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        var recorded: [(text: String, target: DictationTarget?)] = []
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            recentTextOutputRecorder: { text, target in
                recorded.append((text, target))
            }
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        let result = await service.deliver(
            text: "你好。 😊",
            mode: .dictation,
            target: target,
            originalTarget: target
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(recorded.map(\.text), ["你好。 😊"])
        XCTAssertEqual(recorded.first?.target, target)
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

    func testAgentComposeCopiesWithoutAttemptingInsertion() async {
        let injector = StubTextInjector(result: .success)
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

        XCTAssertEqual(result, .copyFailed(reason: "Clipboard write failed"))
        XCTAssertEqual(clipboard.copiedTexts, ["hello"])
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    func testOutputPolicyKeepsAgentComposeCopyOnly() {
        let policy = DefaultOutputPolicy()
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        XCTAssertEqual(
            policy.action(mode: .agentCompose, target: target, originalTarget: target),
            .copy(reason: .agentCompose)
        )
    }

    func testOutputPolicyRequestsCopyWhenTargetChanged() {
        let policy = DefaultOutputPolicy()
        let original = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let current = DictationTarget(bundleID: "com.apple.Safari", appName: "Safari")

        XCTAssertEqual(
            policy.action(mode: .dictation, target: current, originalTarget: original),
            .copy(reason: .targetChanged("Target application changed from Editor to Safari"))
        )
    }

    func testOutputPolicyRequestsInsertionForUnchangedDictationTarget() {
        let policy = DefaultOutputPolicy()
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        XCTAssertEqual(
            policy.action(mode: .dictation, target: target, originalTarget: target),
            .insert
        )
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
            textInputMode: { _ in mode }
        )

        _ = await service.deliver(text: "first", mode: .dictation, target: nil, originalTarget: nil)
        mode = .simulatedTyping
        _ = await service.deliver(text: "second", mode: .dictation, target: nil, originalTarget: nil)

        XCTAssertEqual(fastPaste.injectedTexts, ["first"])
        XCTAssertEqual(simulatedTyping.injectedTexts, ["second"])
    }

    // MARK: - Per-app output method override

    func testOutputPolicyResolvesTextInputModeFromAppRuleBeforeGlobalMode() async {
        let fastPaste = StubTextInjector(result: .success)
        let simulatedTyping = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let environment = AppEnvironment(container: try! DependencyContainer.inMemory())
        let ruleStore = OutputMethodRuleStore(settingsRepository: environment.settingsRepository)
        try! ruleStore.save(
            OutputMethodRule(
                id: "rule-xcode",
                bundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                inputMode: .simulatedTyping
            )
        )
        let service = DefaultOutputService(
            textInsertionCoordinator: TextInsertionCoordinator(
                fastPasteInserter: fastPaste,
                simulatedTypingInserter: simulatedTyping
            ),
            clipboardService: clipboard,
            textInputMode: { target in
                SettingsBackedTextOutputConfiguration(
                    settingsRepository: environment.settingsRepository
                )
                .textInputMode(for: target)
            }
        )
        let target = DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode")

        _ = await service.deliver(
            text: "typed text",
            mode: .dictation,
            target: target,
            originalTarget: target
        )
        // 无规则的其它应用继续走全局默认（automatic → fastPaste）。
        _ = await service.deliver(
            text: "pasted text",
            mode: .dictation,
            target: DictationTarget(bundleID: "com.example.notes", appName: "Notes"),
            originalTarget: DictationTarget(bundleID: "com.example.notes", appName: "Notes")
        )

        XCTAssertEqual(simulatedTyping.injectedTexts, ["typed text"])
        XCTAssertEqual(fastPaste.injectedTexts, ["pasted text"])
    }

    func testOutputPolicyAppRuleDoesNotAffectAgentComposeCopy() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let environment = AppEnvironment(container: try! DependencyContainer.inMemory())
        try! OutputMethodRuleStore(settingsRepository: environment.settingsRepository).save(
            OutputMethodRule(
                id: "rule-safari",
                bundleID: "com.apple.Safari",
                appName: "Safari",
                inputMode: .simulatedTyping
            )
        )
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            textInputMode: { target in
                SettingsBackedTextOutputConfiguration(
                    settingsRepository: environment.settingsRepository
                )
                .textInputMode(for: target)
            }
        )
        let target = DictationTarget(bundleID: "com.apple.Safari", appName: "Safari")

        let result = await service.deliver(
            text: "agent text",
            mode: .agentCompose,
            target: target,
            originalTarget: target
        )

        XCTAssertEqual(result, .copied)
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    func testOutputPolicyKeepsGlobalModeWhenNoRuleMatchesTarget() async {
        let fastPaste = StubTextInjector(result: .success)
        let simulatedTyping = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let environment = AppEnvironment(container: try! DependencyContainer.inMemory())
        try! OutputMethodRuleStore(settingsRepository: environment.settingsRepository).save(
            OutputMethodRule(
                id: "rule-xcode",
                bundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                inputMode: .simulatedTyping
            )
        )
        let service = DefaultOutputService(
            textInsertionCoordinator: TextInsertionCoordinator(
                fastPasteInserter: fastPaste,
                simulatedTypingInserter: simulatedTyping
            ),
            clipboardService: clipboard,
            textInputMode: { target in
                SettingsBackedTextOutputConfiguration(
                    settingsRepository: environment.settingsRepository
                )
                .textInputMode(for: target)
            }
        )
        let otherApp = DictationTarget(bundleID: "com.apple.Terminal", appName: "Terminal")

        let result = await service.deliver(
            text: "hello",
            mode: .dictation,
            target: otherApp,
            originalTarget: otherApp
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(fastPaste.injectedTexts, ["hello"])
        XCTAssertTrue(simulatedTyping.injectedTexts.isEmpty)
    }

    func testOutputMethodRuleStoreSaveWithSameBundleIDReplacesExistingRule() throws {
        let environment = AppEnvironment(container: try! DependencyContainer.inMemory())
        let store = OutputMethodRuleStore(settingsRepository: environment.settingsRepository)
        try store.save(
            OutputMethodRule(
                id: "rule-old",
                bundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                inputMode: .simulatedTyping
            )
        )

        // 模式胶囊点击切换走的就是"同 bundleID 重新 save"路径:旧 id 被替换,只剩新模式。
        try store.save(
            OutputMethodRule(
                id: "rule-new",
                bundleID: "com.apple.dt.Xcode",
                appName: "Xcode",
                inputMode: .fastPaste
            )
        )

        let rules = try store.list()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.id, "rule-new")
        XCTAssertEqual(rules.first?.inputMode, .fastPaste)
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

    func testAgentComposeCopiesForUnchangedTarget() async {
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
        XCTAssertTrue(injector.injectedTexts.isEmpty)
        XCTAssertEqual(clipboard.copiedTexts, ["agent text"])
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

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(lastResultStore.lastResultText, "previous dictation")
    }

    func testAgentComposeDoesNotRequestInsertionWhenPermissionWouldBeDenied() async {
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

    func testAgentComposeCopiesWhenTargetChangesWithoutTargetChangedFailure() async {
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
        XCTAssertTrue(injector.injectedTexts.isEmpty)
        XCTAssertEqual(clipboard.copiedTexts, ["agent text"])
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

    // MARK: - Voice command: replace the focused input area

    func testCancelledVoiceCommandDoesNotSelectOrReplaceInputArea() async {
        let injector = StubTextInjector(result: .success)
        let poster = StubSelectAllShortcutPoster()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: StubClipboardService(),
            selectAllShortcutPoster: poster,
            inputAreaTextProvider: { _ in "original" }
        )
        let task = Task { @MainActor in
            await service.deliverReplacingInputArea(
                text: "edited", mode: .command, target: nil,
                originalTarget: nil, expectedInputText: "original"
            )
        }
        task.cancel()

        let result = await task.value

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(poster.postCount, 0)
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    func testVoiceCommandCancelledWhileSelectionSettlesDoesNotInsert() async {
        let injector = StubTextInjector(result: .success)
        let poster = StubSelectAllShortcutPoster()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: StubClipboardService(),
            selectAllShortcutPoster: poster,
            inputAreaTextProvider: { _ in "original" }
        )
        var task: Task<OutputResult, Never>?
        poster.onPost = { task?.cancel() }
        task = Task { @MainActor in
            await service.deliverReplacingInputArea(
                text: "edited", mode: .command, target: nil,
                originalTarget: nil, expectedInputText: "original"
            )
        }

        let result = await task!.value

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(poster.postCount, 1)
        XCTAssertTrue(injector.injectedTexts.isEmpty)
    }

    func testVoiceCommandSelectsWholeFieldBeforeInsertingEditedText() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let poster = StubSelectAllShortcutPoster()
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            selectAllShortcutPoster: poster,
            inputAreaTextProvider: { _ in "原文内容" },
            selectAllSettleNanoseconds: 0
        )

        let result = await service.deliverReplacingInputArea(
            text: "改写后的内容",
            mode: .command,
            target: target,
            originalTarget: target,
            expectedInputText: "原文内容"
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(poster.postCount, 1)
        XCTAssertEqual(injector.injectedTexts, ["改写后的内容"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    func testVoiceCommandRefusesRewriteWhenInputAreaChangedAfterSnapshot() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let poster = StubSelectAllShortcutPoster()
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            selectAllShortcutPoster: poster,
            inputAreaTextProvider: { _ in "用户手动改过的内容" },
            selectAllSettleNanoseconds: 0
        )

        let result = await service.deliverReplacingInputArea(
            text: "改写后的内容",
            mode: .command,
            target: target,
            originalTarget: target,
            expectedInputText: "原文内容"
        )

        guard case .inputChanged = result else {
            return XCTFail("Expected inputChanged, got \(result)")
        }
        XCTAssertEqual(poster.postCount, 0)
        XCTAssertTrue(injector.injectedTexts.isEmpty)
        XCTAssertEqual(clipboard.copiedTexts, ["改写后的内容"])
    }

    func testVoiceCommandCopiesWhenTargetChangedInsteadOfReplacingField() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let poster = StubSelectAllShortcutPoster()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            selectAllShortcutPoster: poster,
            inputAreaTextProvider: { _ in "原文内容" },
            selectAllSettleNanoseconds: 0
        )

        let result = await service.deliverReplacingInputArea(
            text: "改写后的内容",
            mode: .command,
            target: DictationTarget(bundleID: "com.example.other", appName: "Other"),
            originalTarget: DictationTarget(bundleID: "com.example.editor", appName: "Editor"),
            expectedInputText: "原文内容"
        )

        guard case .targetChanged = result else {
            return XCTFail("Expected targetChanged, got \(result)")
        }
        XCTAssertEqual(poster.postCount, 0)
        XCTAssertTrue(injector.injectedTexts.isEmpty)
        XCTAssertEqual(clipboard.copiedTexts, ["改写后的内容"])
    }

    func testVoiceCommandReportsInjectionFailureWhenSelectAllEventCannotBePosted() async {
        let injector = StubTextInjector(result: .success)
        let clipboard = StubClipboardService()
        let poster = StubSelectAllShortcutPoster(error: .eventCreationFailed)
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard,
            selectAllShortcutPoster: poster,
            inputAreaTextProvider: { _ in "原文内容" },
            selectAllSettleNanoseconds: 0
        )

        let result = await service.deliverReplacingInputArea(
            text: "改写后的内容",
            mode: .command,
            target: target,
            originalTarget: target,
            expectedInputText: "原文内容"
        )

        guard case .injectionFailed = result else {
            return XCTFail("Expected injectionFailed, got \(result)")
        }
        XCTAssertTrue(injector.injectedTexts.isEmpty)
        XCTAssertEqual(clipboard.copiedTexts, ["改写后的内容"])
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

@MainActor
private final class StubSelectAllShortcutPoster: SelectAllShortcutPosting {
    private(set) var postCount = 0
    var onPost: (() -> Void)?
    private let error: SelectAllShortcutPostingError?

    init(error: SelectAllShortcutPostingError? = nil) {
        self.error = error
    }

    func postSelectAllShortcut() throws {
        postCount += 1
        onPost?()
        if let error {
            throw error
        }
    }
}
