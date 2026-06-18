import XCTest
@testable import VoxFlowApp

final class AppDelegateEventRoutingTests: XCTestCase {
    func testEscapeKeyRoutingMatchesMacEscapeKeyCode() {
        XCTAssertTrue(EscapeEventRouting.isEscapeKey(53))
        XCTAssertFalse(EscapeEventRouting.isEscapeKey(36))
    }

    func testAppDelegateVoiceEnhancementDefaultStaysDisabled() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift")
        let source = try String(contentsOf: sourceURL)

        let disabledDefaultPattern = #"SettingsKey\.audioVoiceEnhancementEnabled,\s*defaultValue:\s*false"#
        XCTAssertNotNil(
            source.range(of: disabledDefaultPattern, options: .regularExpression),
            "AppDelegate must not enable nonlinear voice enhancement unless the user explicitly opts in."
        )
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
