import AVFoundation
import VoxFlowASRCore
import VoxFlowAudio
import VoxFlowModelStore
import XCTest
@testable import VoxFlowApp

final class Qwen3LiveSmokeTests: XCTestCase {
    func testDownloadedQwen3ProductionEntryReportsEmptyTranscriptForSyntheticSilence() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["VOICEINPUT_TEST_QWEN3_LIVE"] == "1",
            "Set VOICEINPUT_TEST_QWEN3_LIVE=1 to run the local Qwen3 model smoke test."
        )

        let modelPath = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_QWEN3_MODEL_PATH"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/VoxFlow/Models/qwen3-asr-0.6b-mlx-4bit")
                .path

        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        let suiteName = "test.Qwen3LiveSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        manager.markQwen3ModelReady(at: modelPath, size: .size0_6B)
        let engine = manager.makeEngine(type: .qwen3)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
        }

        XCTAssertTrue(engine is ASRCoreBackedASREngine, "Qwen live smoke must exercise the provider-backed production entry.")
        XCTAssertTrue(engine.isAvailable, "Qwen3 model is not available at \(modelPath)")

        let completed = expectation(description: "Qwen3 reports empty transcript for synthetic silence")
        var receivedText: String?
        var receivedError: Error?
        engine.onTranscription = { text, isFinal in
            if isFinal {
                receivedText = text
                completed.fulfill()
            }
        }
        engine.onError = { error in
            receivedError = error
            completed.fulfill()
        }

        do {
            try engine.start()
        } catch {
            if error.localizedDescription.contains("macOS 15") {
                throw XCTSkip("Qwen3-ASR requires macOS 15 or newer.")
            }
            throw error
        }

        engine.appendAudioFrame(Self.makeSilentFrame(seconds: 2))
        engine.endAudio()

        wait(for: [completed], timeout: 120)
        XCTAssertNil(receivedText)
        guard case let ASRCoreBackedASREngineError.failure(asrError)? = receivedError else {
            XCTFail("Expected Qwen3 silence to report an ASR failure, got \(String(describing: receivedError))")
            return
        }
        XCTAssertEqual(asrError.category, .emptyTranscript)
    }

    private static func makeSilentFrame(seconds: Double) -> AudioFrame {
        let sampleRate = 16_000.0
        let sampleCount = Int(sampleRate * seconds)
        return makeTestAudioFrame(
            samples: Array(repeating: 0, count: sampleCount),
            sampleRate: Int(sampleRate)
        )
    }
}
