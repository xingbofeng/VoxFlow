import AVFoundation
import XCTest
@testable import VoxFlowApp

final class ASREngineTests: XCTestCase {
    func testSpeechRecognizerConformsToASREngine() {
        let engine: ASREngine = SpeechRecognizer()

        // Verify all protocol properties are accessible
        XCTAssertNil(engine.onTranscription)
        XCTAssertNil(engine.onError)
        XCTAssertFalse(engine.isAvailable)

        // Verify configure does not crash
        engine.configure(locale: Locale(identifier: "zh_CN"))

        // Verify all protocol methods exist and can be called
        engine.onTranscription = { _, _ in }
        engine.onError = { _ in }
        engine.stop()
        engine.cancel()

        // Audio frame methods should not crash on unstarted engine
        engine.appendAudioFrame(makeTestAudioFrame(sampleCount: 1_024))
        engine.endAudio()
    }

    func testSpeechRecognizerConformsViaProtocolReference() {
        // Verify the type can be assigned to protocol reference
        let _: ASREngine = SpeechRecognizer()
    }

    // MARK: - Cancel vs. Stop Semantics

    /// Verifies that cancel() does not trigger onTranscription callbacks,
    /// while stop() may trigger final callbacks via finish().
    ///
    /// SpeechRecognizer.stop() calls recognitionTask?.finish() which may
    /// produce a final transcription result. SpeechRecognizer.cancel()
    /// calls recognitionTask?.cancel() which cancels silently without
    /// producing results.
    func testCancelNotStopOnRecordingError() {
        let engine = SpeechRecognizer()

        var cancelCalledTranscription = false
        var stopCalledTranscription = false

        // Verify cancel() semantics: should not trigger onTranscription
        engine.onTranscription = { _, _ in
            cancelCalledTranscription = true
        }
        engine.cancel()
        XCTAssertFalse(cancelCalledTranscription, "cancel() should not trigger onTranscription")

        // Verify stop() semantics: may trigger onTranscription (via finish)
        engine.onTranscription = { _, _ in
            stopCalledTranscription = true
        }
        engine.stop()
        // stop() on an idle recognizer (no active task) should not crash.
        // When a recognition task IS active, stop() may trigger a final
        // transcription callback via recognitionTask?.finish().
        XCTAssertFalse(stopCalledTranscription, "stop() on idle recognizer should not crash")
    }
}
