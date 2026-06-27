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

    func testScreenshotOCRResultPresentationPolicyShowsCompleteAsThumbnailBeforeExpansion() {
        XCTAssertEqual(
            ScreenshotOCRResultPresentationPolicy.route(
                for: ScreenshotOCRResult(originalText: "text", captureCompletionKind: .complete)
            ),
            .thumbnail(initialTab: .originalImage)
        )
        XCTAssertEqual(
            ScreenshotOCRResultPresentationPolicy.route(
                for: ScreenshotOCRResult(originalText: "text", captureCompletionKind: .textRecognition)
            ),
            .expanded(initialTab: .ocr, autoDismiss: false)
        )
        XCTAssertEqual(
            ScreenshotOCRResultPresentationPolicy.route(
                for: ScreenshotOCRResult(originalText: "text", captureCompletionKind: .scrollingScreenshot)
            ),
            .thumbnail(initialTab: .originalImage)
        )
    }

    func testSelectionActionOnlyStartsWhileIdleAndNeverPresentsEphemeralHUD() {
        for shortcut in [
            HotKeyWorkflowShortcut.selectionAction,
            .selectionTranslate,
            .selectionSummarize,
            .selectionAgent,
        ] {
            XCTAssertTrue(
                HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
                    shortcut,
                    dictationState: .idle
                )
            )
        }

        for state in [DictationState.recording, .waitingForFinal, .processing, .injecting] {
            for shortcut in [
                HotKeyWorkflowShortcut.selectionAction,
                .selectionTranslate,
                .selectionSummarize,
                .selectionAgent,
            ] {
                XCTAssertFalse(
                    HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
                        shortcut,
                        dictationState: state
                    )
                )
            }
        }

        for state in [DictationState.idle, .recording, .waitingForFinal, .processing, .injecting] {
            for shortcut in [
                HotKeyWorkflowShortcut.selectionAction,
                .selectionTranslate,
                .selectionSummarize,
                .selectionAgent,
            ] {
                XCTAssertFalse(
                    HotKeyWorkflowRoutingPolicy.shouldPresentEphemeralWorkflowHUD(
                        shortcut,
                        dictationState: state
                    )
                )
            }
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

    func testScreenshotOCRGatesUpdatePromptDismissalBeforeCapture() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleScreenshotOCRShortcut\([\s\S]*?\n    private func saveScreenshotRecord"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("NSWorkspace.shared.frontmostApplication?.processIdentifier"))
        XCTAssertTrue(method.contains("NSRunningApplication.current.processIdentifier"))
        let policy = try XCTUnwrap(
            method.range(of: "AppPresentationPolicy.shouldDismissVoxFlowOverlaysBeforeScreenshotCapture")
        )
        let dismiss = try XCTUnwrap(method.range(of: "updateCheckCoordinator.dismissActivePromptAsNextTime()"))
        let capture = try XCTUnwrap(method.range(of: "screenshotOCRService.captureAndRecognize()"))
        XCTAssertLessThan(policy.lowerBound, dismiss.lowerBound)
        XCTAssertLessThan(
            dismiss.lowerBound,
            capture.lowerBound,
            "When VoxFlow is not frontmost, the update prompt must be dismissed before screenshot capture so Command+Shift+A does not capture the update modal."
        )
    }

    func testScreenshotOCRGatesHomeDetailOverlayDismissalBeforeCapture() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleScreenshotOCRShortcut\([\s\S]*?\n    private func saveScreenshotRecord"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        let policy = try XCTUnwrap(
            method.range(of: "AppPresentationPolicy.shouldDismissVoxFlowOverlaysBeforeScreenshotCapture")
        )
        let dismiss = try XCTUnwrap(method.range(of: "windowCoordinator.dismissHomeDetailOverlay()"))
        let capture = try XCTUnwrap(method.range(of: "screenshotOCRService.captureAndRecognize()"))
        XCTAssertLessThan(policy.lowerBound, dismiss.lowerBound)
        XCTAssertLessThan(
            dismiss.lowerBound,
            capture.lowerBound,
            "When VoxFlow is not frontmost, the home detail overlay must be dismissed before screenshot capture so Command+Shift+A does not capture the home modal."
        )
    }

    func testScreenshotOCRResultPanelUsesPolicySoCompleteCanShowThumbnailBeforeExpansion() throws {
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
        XCTAssertTrue(method.contains("screenshotOCRResultPanelController.presentThumbnail("))
        XCTAssertTrue(method.contains("ScreenshotOCRResultPresentationPolicy.route(for: result)"))
        XCTAssertTrue(method.contains("case let .expanded(initialTab, autoDismiss):"))
        XCTAssertTrue(method.contains("case let .thumbnail(initialTab):"))
        XCTAssertTrue(method.contains("initialTab: initialTab"))
        XCTAssertTrue(method.contains("autoDismiss: autoDismiss"))
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

    func testScreenRecordingSelectionUsesRuntimeCoordinatorAndRefreshesMultimediaHistory() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let startMethod = try XCTUnwrap(
            source.range(
                of: #"private func handleScreenRecordingSelection\([\s\S]*?\n    private func stopActiveScreenRecording"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )
        let stopMethod = try XCTUnwrap(
            source.range(
                of: #"private func stopActiveScreenRecording\([\s\S]*?\n    private func handleScreenshotOCRShortcut"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(source.contains("private var screenRecordingCoordinator: ScreenRecordingCoordinator"))
        XCTAssertTrue(source.contains("private var screenRecordingHUDPanel: ScreenRecordingHUDPanel?"))
        XCTAssertTrue(startMethod.contains("ScreenRecordingRequest("))
        XCTAssertTrue(startMethod.contains("screenRecordingCoordinator.start("))
        XCTAssertTrue(startMethod.contains("screenRecordingHUDPanel"))
        XCTAssertTrue(startMethod.contains("overlayControls.excludedWindowIDs()"))
        XCTAssertFalse(startMethod.contains("ScreenCaptureWindowExclusion.currentProcessWindowIDs()"))
        XCTAssertTrue(stopMethod.contains("try await screenRecordingCoordinator.stop()"))
        XCTAssertTrue(stopMethod.contains("windowCoordinator.refreshScreenshotRecords()"))
        XCTAssertTrue(stopMethod.contains("appEnvironment.notifyHistoryDidChange()"))
        XCTAssertTrue(stopMethod.contains("showTemporaryMessage(\"录屏已保存\""))
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

    func testSelectionActionWorkflowShortcutShowsActionCardAndConsumesShortcut() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let selectionActionCase = try XCTUnwrap(
            source.range(
                of: #"case \.selectionAction:[\s\S]*?\n        case \.cancel:"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(selectionActionCase.contains("shouldStartEphemeralWorkflow(shortcut)"))
        XCTAssertTrue(selectionActionCase.contains("showSelectionActionCard()"))
        XCTAssertTrue(selectionActionCase.contains("return true"))
        XCTAssertFalse(selectionActionCase.contains("selection_action_not_ready"))
    }

    func testDirectSelectionActionWorkflowShortcutsInvokeSelectedActionAndConsumeShortcut() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for (caseName, nextCaseName, actionName) in [
            ("selectionTranslate", "selectionSummarize", "translate"),
            ("selectionSummarize", "selectionAgent", "summarize"),
            ("selectionAgent", "cancel", "agent"),
        ] {
            let shortcutCase = try XCTUnwrap(
                source.range(
                    of: #"case \.\#(caseName):[\s\S]*?\n        case \.\#(nextCaseName):"#,
                    options: .regularExpression
                ).map { String(source[$0]) }
            )

            XCTAssertTrue(shortcutCase.contains("shouldStartEphemeralWorkflow(shortcut)"))
            XCTAssertTrue(shortcutCase.contains("performSelectionAction(.\(actionName))"))
            XCTAssertTrue(shortcutCase.contains("return true"))
        }
    }

    func testSelectionActionCardDoesNotOpenWhenSelectedTextAcquisitionFails() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func showSelectionActionCard\(\) \{[\s\S]*?\n    private func handleSelectionActionSelected"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("provider.snapshotResult()"))
        XCTAssertTrue(method.contains("let anchor = snapshot.selectionBounds ?? mouseAnchor"))
        XCTAssertTrue(method.contains("case .success(let snapshot):"))
        XCTAssertTrue(method.contains("overlayController.showSelectionActions("))
        XCTAssertTrue(method.contains("SelectionActionCardPresentation(selectedText: snapshot.text)"))
        XCTAssertTrue(method.contains("anchor: anchor"))
        XCTAssertTrue(method.contains("case .failure(let failure):"))
        XCTAssertTrue(method.contains("hudFeatureController.showTemporaryMessage(failure.userMessage, duration: 1.8)"))
    }

    func testSelectionActionRestoresLastExternalTargetBeforeReadingSelection() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func showSelectionActionCard\(\) \{[\s\S]*?\n    private func handleSelectionActionSelected"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        let restoreRange = try XCTUnwrap(method.range(of: "await restoreLastExternalSelectionTargetIfNeeded()"))
        let providerRange = try XCTUnwrap(method.range(of: "let provider = SelectionTextProvider"))
        XCTAssertLessThan(
            restoreRange.lowerBound,
            providerRange.lowerBound,
            "Status bar menu actions should restore the previously focused external app before reading selection."
        )
    }

    func testSelectionActionEntrypointsUseUserInitiatedSelectionConfiguration() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for methodPattern in [
            #"private func performSelectionAction\([\s\S]*?\n    private func showPalette"#,
            #"private func showSelectionActionCard\(\) \{[\s\S]*?\n    private func startSelectionTargetTracking"#,
        ] {
            let method = try XCTUnwrap(
                source.range(of: methodPattern, options: .regularExpression).map { String(source[$0]) }
            )

            XCTAssertTrue(method.contains("configuration: .userInitiated("))
            XCTAssertTrue(method.contains("frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier"))
        }
    }

    func testSelectionActionCardCallbackUsesDispatcherAndAgentHandler() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("overlayController.onSelectionActionSelected"))
        XCTAssertTrue(source.contains("handleSelectionActionSelected(action: action, selectedText: selectedText)"))

        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleSelectionActionSelected\([\s\S]*?\n    private func shouldStartEphemeralWorkflow"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("SelectionActionDispatcher().route"))
        XCTAssertTrue(method.contains("case let .textTransform"))
        XCTAssertTrue(method.contains("case let .agentContext"))
        XCTAssertTrue(method.contains("selectionResultPanelController.present"))
        XCTAssertTrue(method.contains("agentDispatchHandler?.start"))
        XCTAssertTrue(method.contains("agentDispatchHandler?.finish"))
        XCTAssertTrue(method.contains("selectionHistoryRecorder.record"))
        XCTAssertTrue(method.contains("kind: .selectionAgent"))
        XCTAssertFalse(method.contains("正在翻译选中文本"))
        XCTAssertFalse(method.contains("正在总结选中文本"))
    }

    func testLateTranscriptionUpdatesAfterRecordingRenderAsLoading() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("let shouldShowLoading = isRefining || self.dictationOrchestrator.state != .recording"))
        XCTAssertTrue(source.contains("self.hudFeatureController.updateTranscription(text, isRefining: shouldShowLoading)"))
    }

    func testSelectionAgentContextRestoresExternalTargetBeforeStartingAgentDispatch() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleSelectionActionSelected\([\s\S]*?\n    private func shouldStartEphemeralWorkflow"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )
        let agentBranch = try XCTUnwrap(
            method.range(
                of: #"case let \.agentContext\(text\):[\s\S]*?\n        \}"#,
                options: .regularExpression
            ).map { String(method[$0]) }
        )

        let restoreRange = try XCTUnwrap(agentBranch.range(of: "await restoreLastExternalSelectionTargetIfNeeded()"))
        let startRange = try XCTUnwrap(agentBranch.range(of: "agentDispatchHandler?.start"))
        XCTAssertLessThan(
            restoreRange.lowerBound,
            startRange.lowerBound,
            "Clicking the selection action card can focus VoxFlow, so Agent dispatch must restore the original external target before capturing fallback output."
        )
    }

    func testPerformWorkflowShortcutHandlesSelectionAskAI() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let method = try XCTUnwrap(
            source.range(
                of: #"private func performWorkflowShortcut\(_ shortcut: HotKeyWorkflowShortcut\) -> Bool \{[\s\S]*?\n    private func performSelectionAction"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("case .selectionAskAI:"))
        XCTAssertTrue(method.contains("performSelectionAction(.askAI)"))
    }

    func testHandleSelectionActionSelectedRoutesAskAIContextToAIChat() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleSelectionActionSelected\([\s\S]*?\n    private func shouldStartEphemeralWorkflow"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("case let .askAIContext(text):"))
        XCTAssertTrue(method.contains("handleSelectionAskAI(prompt: text)"))
        // Make sure askAI does NOT route to agentContext
        XCTAssertTrue(method.contains("case let .askAIContext(text):"))
    }

    func testHandleSelectionAskAIOpensAIChatPanelHUD() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let method = try XCTUnwrap(
            source.range(
                of: #"private func handleSelectionAskAI\(prompt: String\) \{[\s\S]*?\n    private func "#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(method.contains("aiChatPanelController.present(viewModel: aiChatViewModel, prompt: prompt)"))
    }

    func testRecordingSubtitleCoordinatorIsWiredToHUDDetailAndEditor() throws {
        let root = try Self.repositoryRoot()
        let appDelegate = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let appEnvironment = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppEnvironment.swift"),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/ViewModels/ScreenshotRecordViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appDelegate.contains("private lazy var recordingSubtitleCoordinator: RecordingSubtitleCoordinator"))
        XCTAssertTrue(appDelegate.contains("RecordingSubtitleDraftStore(paths: paths)"))
        XCTAssertTrue(appDelegate.contains("LiveSystemRecordingSubtitleTranscriber("))
        XCTAssertTrue(appDelegate.contains("LiveRecordingSubtitleBurner()"))
        XCTAssertTrue(appDelegate.contains("appEnvironment.subtitleCoordinator = recordingSubtitleCoordinator"))
        XCTAssertTrue(appDelegate.contains("ScreenRecordingResultPanelController("))
        XCTAssertTrue(appDelegate.contains("coordinator: recordingSubtitleCoordinator"))
        XCTAssertTrue(appDelegate.contains("RecordingSubtitleEditorWindowController("))
        XCTAssertTrue(appDelegate.contains("onDraftReady: { [weak self] id in"))
        XCTAssertTrue(appDelegate.contains("self?.openSubtitleEditor(recordID: id)"))
        XCTAssertTrue(appDelegate.contains("subtitleEditorWindowController.present("))
        XCTAssertTrue(appDelegate.contains("recordID: recordID,"))
        XCTAssertTrue(appDelegate.contains("preferredScreen: screenRecordingResultPanelController.presentationScreen ?? NSApp.keyWindow?.screen"))
        XCTAssertTrue(appDelegate.contains("\"录屏保存失败：\\(error.localizedDescription)\""))
        XCTAssertTrue(appEnvironment.contains("var subtitleCoordinator: RecordingSubtitleCoordinator?"))
        XCTAssertTrue(viewModel.contains("coordinator.addSubtitle(recordID: id)"))
        XCTAssertTrue(viewModel.contains("coordinator.openEditor(recordID: id)"))
        XCTAssertTrue(viewModel.contains("coordinator.startBurn(recordID: id)"))
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
