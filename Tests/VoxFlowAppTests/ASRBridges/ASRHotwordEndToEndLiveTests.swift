import AVFoundation
import VoxFlowASRCore
import VoxFlowAudio
import VoxFlowProviderNVIDIA
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class ASRHotwordEndToEndLiveTests: XCTestCase {
    func testNemotronHotwordsFlowFromRepositoryToRealASR() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["VOICEINPUT_TEST_ASR_HOTWORD_E2E"] == "1",
            "Set VOICEINPUT_TEST_ASR_HOTWORD_E2E=1 to run the real hotword-to-ASR live test."
        )
        let modelPath = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_NVIDIA_NEMOTRON_MODEL_PATH"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/VoxFlow/Models/nemotron-streaming-asr-0.6b-speech-swift")
                .path
        let wavePath = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_ASR_HOTWORD_WAVE_PATH"]
            ?? Self.repositoryRoot()
                .appendingPathComponent("TestResources/ASRSmoke/Audio/zh_short.wav")
                .path
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try seedHotwords(in: environment.correctionTargetRepository)
        let promptProvider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository
        )

        let prompt = try XCTUnwrap(
            promptProvider.prompt(
                for: .nvidiaNemotron,
                bundleIdentifier: "com.mitchellh.ghostty"
            )
        )
        XCTAssertEqual(prompt, "随声写, 语音输入, 码上写, 流式识别")
        XCTAssertFalse(prompt.contains("不要出现"))
        XCTAssertFalse(prompt.contains("OtherAppOnly"))

        let provider = NVIDIANemotronASRProvider.live(
            descriptor: NVIDIANemotronProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: modelPath, isDirectory: true)
        )
        let engine = ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: ASRLanguageCapability(bcp47Tag: "zh-CN")
        )
        let completed = expectation(description: "Nemotron emits final transcript with repository hotword prompt")
        var finalText = ""
        var receivedError: Error?
        engine.configureTermPrompt(prompt)
        engine.onTranscription = { text, isFinal in
            if isFinal {
                finalText = text
                completed.fulfill()
            }
        }
        engine.onError = { error in
            receivedError = error
            completed.fulfill()
        }

        try engine.start()
        for frame in try Self.loadFrames(from: URL(fileURLWithPath: wavePath)) {
            engine.appendAudioFrame(frame)
        }
        engine.endAudio()

        wait(for: [completed], timeout: 60)
        XCTAssertNil(receivedError)
        XCTAssertFalse(finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(finalText.contains("语音输入"))
        print("ASR_HOTWORD_E2E provider=nvidia prompt=\(prompt) finalText=\(finalText)")
    }

    private func seedHotwords(in repository: any CorrectionTargetRepository) throws {
        var appScoped = hotword(
            "随声写",
            hitCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1),
            scope: .application(bundleIdentifier: "com.mitchellh.ghostty")
        )
        appScoped.source = .manual
        let highHit = hotword("语音输入", hitCount: 99, updatedAt: Date(timeIntervalSince1970: 4))
        let midHit = hotword("码上写", hitCount: 50, updatedAt: Date(timeIntervalSince1970: 3))
        let lowHit = hotword("流式识别", hitCount: 20, updatedAt: Date(timeIntervalSince1970: 2))
        let otherApp = hotword(
            "OtherAppOnly",
            hitCount: 100,
            updatedAt: Date(timeIntervalSince1970: 5),
            scope: .application(bundleIdentifier: "com.cursor.Cursor")
        )
        var suspended = hotword("不要出现", hitCount: 1, updatedAt: Date(timeIntervalSince1970: 6))
        suspended.lifecycle = .suspended

        for target in [appScoped, highHit, midHit, lowHit, otherApp, suspended] {
            try repository.save(target)
        }
    }

    private func hotword(
        _ text: String,
        hitCount: Int,
        updatedAt: Date,
        scope: RuleScope = .global
    ) -> CorrectionTargetTerm {
        var term = CorrectionTargetTerm(
            text: text,
            scope: scope,
            lifecycle: .active,
            source: .manual,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
        term.hitCount = hitCount
        term.lastHitAt = updatedAt
        return term
    }

    private static func loadFrames(
        from url: URL,
        frameSampleCount: Int = 1_600
    ) throws -> [AudioFrame] {
        let audioFile = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: AVAudioFrameCount(audioFile.length)
            )
        )
        try audioFile.read(into: buffer)
        let samples = try XCTUnwrap(AudioPreprocessor.resampleTo16kHz(buffer))
        return stride(from: 0, to: samples.count, by: frameSampleCount).enumerated().map { index, offset in
            let end = min(offset + frameSampleCount, samples.count)
            return AudioFrame(
                sequenceNumber: UInt64(index + 1),
                startSample: UInt64(offset),
                samples: ContiguousArray(samples[offset..<end]),
                sampleRate: 16_000,
                capturedAt: .now
            )
        }
    }

    private static func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
