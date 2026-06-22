import XCTest
@testable import VoxFlowApp

final class AppDelegateEventRoutingTests: XCTestCase {
    func testEscapeKeyRoutingMatchesMacEscapeKeyCode() {
        XCTAssertEqual(HotKeyShortcutRouting.workflowShortcut(keyCode: 53, flags: []), .cancel)
        XCTAssertNil(HotKeyShortcutRouting.workflowShortcut(keyCode: 36, flags: []))
    }

    func testAppDelegateVoiceEnhancementDefaultStaysDisabled() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let disabledDefaultPattern = #"SettingsKey\.audioVoiceEnhancementEnabled,\s*defaultValue:\s*false"#
        XCTAssertNotNil(
            source.range(of: disabledDefaultPattern, options: .regularExpression),
            "AppDelegate must not enable nonlinear voice enhancement unless the user explicitly opts in."
        )
    }

    func testEscapeCancelsActiveAgentDispatchConfirmationEvenAfterDictationIsIdle() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("voiceTaskCoordinator.activeTaskID(for: .agentDispatch)"))
        XCTAssertTrue(source.contains("agentDispatchHandler?.cancel()"))
        XCTAssertTrue(source.contains("hudFeatureController.render(.hidden)"))
    }

    func testHotKeyRoutingSendsDictationPressToNotesWhenNotesCanCapture() {
        let decision = HotKeyRoutingPolicy.decision(
            for: .press,
            action: .dictation,
            dictationState: .idle,
            activeVoiceAction: nil,
            notesState: HotKeyNotesState(shouldCaptureHotKey: true, isActive: true, isRecording: false)
        )

        XCTAssertEqual(decision, .startNotesRecording)
    }

    func testHotKeyRoutingTogglesDictationForShortPressWhenNotesCannotCapture() {
        XCTAssertEqual(
            HotKeyRoutingPolicy.decision(
                for: .shortPress,
                action: .dictation,
                dictationState: .idle,
                activeVoiceAction: nil,
                notesState: HotKeyNotesState(shouldCaptureHotKey: false, isActive: false, isRecording: false)
            ),
            .startDictation(.dictation)
        )

        XCTAssertEqual(
            HotKeyRoutingPolicy.decision(
                for: .shortPress,
                action: .dictation,
                dictationState: .recording,
                activeVoiceAction: .dictation,
                notesState: HotKeyNotesState(shouldCaptureHotKey: false, isActive: false, isRecording: false)
            ),
            .releaseDictation(.dictation)
        )
    }

    func testHotKeyRoutingFinishesNotesRecordingOnReleaseWhenNotesAreRecording() {
        let decision = HotKeyRoutingPolicy.decision(
            for: .release,
            action: .dictation,
            dictationState: .idle,
            activeVoiceAction: nil,
            notesState: HotKeyNotesState(shouldCaptureHotKey: true, isActive: true, isRecording: true)
        )

        XCTAssertEqual(decision, .finishNotesRecording)
    }

    func testHotKeyRoutingIgnoresMismatchedDictationRelease() {
        let decision = HotKeyRoutingPolicy.decision(
            for: .release,
            action: .agentCompose,
            dictationState: .recording,
            activeVoiceAction: .dictation,
            notesState: HotKeyNotesState(shouldCaptureHotKey: false, isActive: false, isRecording: false)
        )

        XCTAssertEqual(decision, .ignore)
    }

    func testClipboardImageOCRDoesNotStartWhileVoiceTaskIsActive() {
        for state in [DictationState.recording, .waitingForFinal, .processing, .injecting] {
            XCTAssertFalse(
                HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
                    .clipboardImageOCR,
                    dictationState: state
                )
            )
        }
    }

    func testScreenshotOCRCanStartWhileVoiceTaskIsActiveWithoutTakingHUD() {
        for state in [DictationState.recording, .waitingForFinal, .processing, .injecting] {
            XCTAssertTrue(
                HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
                    .screenshotOCR,
                    dictationState: state
                )
            )
            XCTAssertFalse(
                HotKeyWorkflowRoutingPolicy.shouldPresentEphemeralWorkflowHUD(
                    .screenshotOCR,
                    dictationState: state
                )
            )
        }
    }

    func testScreenshotOCRNeverPresentsHUD() {
        for state in [DictationState.idle, .recording, .waitingForFinal, .processing, .injecting] {
            XCTAssertFalse(
                HotKeyWorkflowRoutingPolicy.shouldPresentEphemeralWorkflowHUD(
                    .screenshotOCR,
                    dictationState: state
                )
            )
        }
    }

    func testAppDelegateDoesNotShowPreCaptureScreenshotHUD() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("框选截图区域以识别文字"),
            "Screenshot OCR must not show a pre-capture voice HUD because the frozen screenshot frame can capture it."
        )
    }

    func testScreenshotOCRResultPanelOnlyOpensOCRTabWithoutAutoDismissForTextRecognitionCommand() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleScreenshotOCRShortcut\([\s\S]*?\n    private func copyLastResultToClipboardForRecovery"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("screenshotOCRResultPanelController.present("))
        XCTAssertTrue(method.contains("result.captureCompletionKind == .textRecognition"))
        XCTAssertTrue(method.contains("initialTab: opensFromTextRecognitionCommand ? .ocr : .originalImage"))
        XCTAssertTrue(method.contains("autoDismiss: !opensFromTextRecognitionCommand"))
    }

    func testSavedScreenshotRecordRefreshesVisibleScreenshotTab() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func saveScreenshotRecord\(result: ScreenshotOCRResult\) \{[\s\S]*?\n    \}"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        let save = try XCTUnwrap(method.range(of: "try appEnvironment.screenshotRecordRepository.save(record)"))
        let refresh = try XCTUnwrap(method.range(of: "windowCoordinator.refreshScreenshotRecords()"))
        XCTAssertLessThan(save.lowerBound, refresh.lowerBound)
    }

    func testRefreshingScreenshotRecordsSurfacesNewestRecordOnFirstPage() throws {
        let controllerSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/MainWindowController.swift"),
            encoding: .utf8
        )
        let viewModelSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/ViewModels/ScreenshotRecordViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(controllerSource.contains("screenshotRecordViewModel.refreshAfterExternalInsert()"))
        XCTAssertTrue(viewModelSource.contains("func refreshAfterExternalInsert()"))
        XCTAssertTrue(viewModelSource.contains("currentPage = 1"))
    }

    func testAgentDefaultOutputDoesNotRenderAgentDispatchFallbackHUD() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleAgentDefaultOutputSelected\([\s\S]*?\n    private func handleDictationStateChange"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertFalse(
            method.contains("hudFeatureController.handleAgentDispatch(.fallbackInput"),
            "Manual 0/default output should reuse the normal input path and must not show the agent fallback HUD."
        )
    }

    func testAgentDefaultOutputCancelsConfirmationBeforeStartingAsyncWork() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let callback = try XCTUnwrap(
            source.range(
                of: #"overlayController\.onAgentDefaultOutputSelected[\s\S]*?agentDispatchHandler = handler"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )
        let beginDefaultOutput = try XCTUnwrap(callback.range(of: "handler?.beginDefaultOutput()"))
        let asyncTask = try XCTUnwrap(callback.range(of: "Task { @MainActor in"))

        XCTAssertLessThan(beginDefaultOutput.lowerBound, asyncTask.lowerBound)
    }

    @MainActor
    func testAgentDefaultOutputCancellationAfterCorrectionSkipsActivationAndDelivery() async {
        var didActivate = false
        var didDeliver = false
        let operation = AgentDefaultOutputOperation(
            process: { text, _ in TextProcessingResult(rawText: text, finalText: text) },
            activate: { _ in didActivate = true; return true },
            currentTarget: { nil },
            deliver: { _, _, _ in didDeliver = true; return .injected },
            isCancelled: { true }
        )

        let result = await operation.run(utterance: "检查一下", originalTarget: nil)

        XCTAssertNil(result)
        XCTAssertFalse(didActivate)
        XCTAssertFalse(didDeliver)
    }

    @MainActor
    func testAgentDefaultOutputCancellationAfterActivationSkipsDelivery() async {
        var cancellationChecks = 0
        var didDeliver = false
        let operation = AgentDefaultOutputOperation(
            process: { text, _ in TextProcessingResult(rawText: text, finalText: text) },
            activate: { _ in true },
            currentTarget: { nil },
            deliver: { _, _, _ in didDeliver = true; return .injected },
            isCancelled: {
                cancellationChecks += 1
                return cancellationChecks >= 2
            }
        )

        let result = await operation.run(utterance: "检查一下", originalTarget: nil)

        XCTAssertNil(result)
        XCTAssertFalse(didDeliver)
    }

    func testAgentDefaultOutputHUDCompletionKeepsFailureVisibleAndHidesTerminalProcessing() {
        XCTAssertEqual(
            AgentDefaultOutputHUDCompletion(outputResult: .injectionFailed(reason: "失败"), finalText: "保留文本"),
            .failure(message: "写入当前输入框失败", retainedText: "保留文本")
        )
        XCTAssertEqual(
            AgentDefaultOutputHUDCompletion(outputResult: .injected, finalText: "完成"),
            .hidden
        )
        XCTAssertEqual(
            AgentDefaultOutputHUDCompletion(outputResult: .cancelled, finalText: "取消"),
            .hidden
        )
    }

    func testAgentDefaultOutputShowsNormalProcessingHUDWithoutStreamingCorrection() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleAgentDefaultOutputSelected\([\s\S]*?\n    private func handleDictationStateChange"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(
            method.contains("hudFeatureController.render(.processing)"),
            "Manual 0/default output should re-present the normal processing HUD after the Agent confirmation panel is dismissed."
        )
        XCTAssertTrue(
            method.contains("hudFeatureController.processingStarted(utterance)"),
            "Manual 0/default output should show the same processing/correction HUD as normal dictation."
        )
        XCTAssertFalse(
            method.contains("hudFeatureController.updateStreamingText"),
            "Manual 0/default output should not stream correction deltas into the Agent confirmation HUD."
        )
    }

    @MainActor
    func testAgentDefaultOutputUsesNormalDeliveryWithOriginalTarget() async {
        let originalTarget = DictationTarget(bundleID: "com.example.original", appName: "Original")
        let currentTarget = DictationTarget(bundleID: "com.example.current", appName: "Current")
        var deliveredTarget: DictationTarget?
        var deliveredOriginalTarget: DictationTarget?
        let operation = AgentDefaultOutputOperation(
            process: { text, _ in TextProcessingResult(rawText: text, finalText: "纠错结果") },
            activate: { _ in true },
            currentTarget: { currentTarget },
            deliver: { _, target, original in
                deliveredTarget = target
                deliveredOriginalTarget = original
                return .injected
            },
            isCancelled: { false }
        )

        _ = await operation.run(utterance: "原文", originalTarget: originalTarget)

        XCTAssertEqual(deliveredTarget, currentTarget)
        XCTAssertEqual(deliveredOriginalTarget, originalTarget)
    }

    func testAgentDefaultOutputLogsTargetsCorrectionActivationAndOutputKind() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleAgentDefaultOutputSelected\([\s\S]*?\n    private func handleDictationStateChange"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("agent_default_output_started"))
        XCTAssertTrue(method.contains("agent_default_output_completed"))
        XCTAssertTrue(method.contains("originalTarget="))
        XCTAssertTrue(method.contains("currentTarget="))
        XCTAssertTrue(method.contains("activatedOriginalTarget="))
        XCTAssertTrue(method.contains("enteredCorrection="))
        XCTAssertTrue(method.contains("outputKind="))
        XCTAssertTrue(method.contains("fallbackReason="))
    }

    @MainActor
    func testAgentDefaultOutputFallsBackToUtteranceWhenCorrectionIsEmpty() async {
        var deliveredText: String?
        let operation = AgentDefaultOutputOperation(
            process: { text, _ in TextProcessingResult(rawText: text, finalText: "  \n") },
            activate: { _ in true },
            currentTarget: { nil },
            deliver: { text, _, _ in deliveredText = text; return .injected },
            isCancelled: { false }
        )

        let result = await operation.run(utterance: "保留原文", originalTarget: nil)

        XCTAssertEqual(result?.finalText, "保留原文")
        XCTAssertEqual(deliveredText, "保留原文")
    }

    func testCancelShortcutConsumesPendingCorrectionBeforeIdlePassThrough() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let cancelCase = try XCTUnwrap(
            source.range(
                of: #"case \.cancel:[\s\S]*?\n        }\n    }\n\n    private func shouldStartEphemeralWorkflow"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )
        let pendingCheck = try XCTUnwrap(cancelCase.range(of: "pendingCorrectionFallback.hasPending"))
        let idleGuard = try XCTUnwrap(cancelCase.range(of: "dictationOrchestrator.state.isIdle"))

        XCTAssertLessThan(pendingCheck.lowerBound, idleGuard.lowerBound)
    }

    func testEphemeralOCRWorkflowsCanStartWhileDictationIsIdle() {
        XCTAssertTrue(
            HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
                .screenshotOCR,
                dictationState: .idle
            )
        )
        XCTAssertTrue(
            HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
                .clipboardImageOCR,
                dictationState: .idle
            )
        )
        XCTAssertTrue(
            HotKeyWorkflowRoutingPolicy.shouldPresentEphemeralWorkflowHUD(
                .clipboardImageOCR,
                dictationState: .idle
            )
        )
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "AppDelegateEventRoutingTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }

    private static func agentDefaultOutputMethod() throws -> String {
        let sourceURL = try repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        return try XCTUnwrap(
            source.range(
                of: #"private func handleAgentDefaultOutputSelected\([\s\S]*?\n    private func handleDictationStateChange"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )
    }
}
