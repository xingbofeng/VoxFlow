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
}
