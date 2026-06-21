import Foundation
import VoxFlowAudio
import VoxFlowProviderCloudCore
import VoxFlowProviderGroq
import XCTest
@testable import VoxFlowApp

final class BufferedCloudASREngineTests: XCTestCase {
    func testRecordingWritesTemporaryWAVAndCancelDeletesIt() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufferedCloudASREngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let engine = BufferedCloudASREngine(
            client: CapturingBufferedCloudClient(resultText: "unused"),
            configuration: configuration(),
            configurationAvailable: { true },
            temporaryDirectory: temporaryDirectory
        )

        try engine.start()
        engine.appendAudioFrame(
            AudioFrame(
                sequenceNumber: 0,
                startSample: 0,
                samples: [0, 0.5, -0.5],
                sampleRate: 16_000,
                capturedAt: ContinuousClock().now
            )
        )

        XCTAssertFalse(try temporaryWAVFiles(in: temporaryDirectory).isEmpty)
        engine.cancel()
        XCTAssertTrue(try temporaryWAVFiles(in: temporaryDirectory).isEmpty)
    }

    func testEndAudioEncodesWAVUploadsAndEmitsFinalResult() async throws {
        let client = CapturingBufferedCloudClient(resultText: "云端结果")
        let engine = BufferedCloudASREngine(
            client: client,
            configuration: configuration(),
            configurationAvailable: { true }
        )
        let callback = LockedBufferedCloudCallback()
        let completed = expectation(description: "final transcription")
        engine.onTranscription = { text, isFinal in
            callback.set(text: text, isFinal: isFinal)
            completed.fulfill()
        }
        engine.configure(locale: Locale(identifier: "zh_CN"))

        try engine.start()
        engine.appendAudioFrame(
            AudioFrame(
                sequenceNumber: 0,
                startSample: 0,
                samples: [0, 0.5, -0.5],
                sampleRate: 16_000,
                capturedAt: ContinuousClock().now
            )
        )
        engine.endAudio()
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(callback.text, "云端结果")
        XCTAssertTrue(callback.isFinal)
        XCTAssertEqual(client.locale?.language.languageCode?.identifier, "zh")
        XCTAssertEqual(String(decoding: client.audioData.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: client.audioData.dropFirst(8).prefix(4), as: UTF8.self), "WAVE")
        XCTAssertEqual(engine.asrRuntimeMetadataSnapshot.audioDurationMs, 0)
    }

    func testStartRejectsUnavailableConfiguration() {
        let engine = BufferedCloudASREngine(
            client: CapturingBufferedCloudClient(resultText: "unused"),
            configuration: configuration(),
            configurationAvailable: { false }
        )

        XCTAssertThrowsError(try engine.start()) { error in
            XCTAssertEqual(error as? BufferedCloudASREngineError, .providerNotConfigured)
        }
    }

    func testCancelDropsLateCloudResult() async throws {
        let client = SuspendedBufferedCloudClient()
        let engine = BufferedCloudASREngine(
            client: client,
            configuration: configuration(),
            configurationAvailable: { true }
        )
        let callback = LockedBufferedCloudCallback()
        engine.onTranscription = { text, isFinal in
            callback.set(text: text, isFinal: isFinal)
        }

        try engine.start()
        engine.appendAudioFrame(
            AudioFrame(
                sequenceNumber: 0,
                startSample: 0,
                samples: [0.1],
                sampleRate: 16_000,
                capturedAt: ContinuousClock().now
            )
        )
        engine.endAudio()
        await client.waitUntilStarted()
        engine.cancel()
        client.complete(text: "迟到结果")
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertNil(callback.text)
    }

    private func configuration() -> CloudASRProviderConfiguration {
        CloudASRProviderConfiguration(
            providerID: ASRProviderID.groqWhisper,
            displayName: "Groq",
            baseURL: GroqCloudASRClient.defaultBaseURL,
            model: GroqCloudASRClient.defaultModel,
            apiKeyRef: "groq-key",
            timeoutSeconds: 30
        )
    }

    private func temporaryWAVFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("VoxFlow-Cloud-ASR-") }
    }
}

private final class CapturingBufferedCloudClient: CloudASRProviderClient, @unchecked Sendable {
    let providerID = ASRProviderID.groqWhisper
    let displayName = "Groq"
    let capabilities: ASRProviderCapabilities = [.cloud, .fileTranscription]
    let resultText: String
    private(set) var audioData = Data()
    private(set) var locale: Locale?

    init(resultText: String) {
        self.resultText = resultText
    }

    func testConnection(configuration: CloudASRProviderConfiguration) async throws -> ASRProviderHealthResult {
        ASRProviderHealthResult(status: .ok, message: "OK", latencyMS: 1)
    }

    func transcribeFile(
        _ request: CloudASRFileRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CloudASRTranscriptionResult {
        audioData = try Data(contentsOf: request.fileURL)
        locale = request.locale
        return CloudASRTranscriptionResult(
            text: resultText,
            durationSeconds: nil,
            providerID: providerID,
            warnings: []
        )
    }
}

private final class SuspendedBufferedCloudClient: CloudASRProviderClient, @unchecked Sendable {
    let providerID = ASRProviderID.groqWhisper
    let displayName = "Groq"
    let capabilities: ASRProviderCapabilities = [.cloud, .fileTranscription]
    private let lock = NSLock()
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<String, Never>?

    func testConnection(configuration: CloudASRProviderConfiguration) async throws -> ASRProviderHealthResult {
        ASRProviderHealthResult(status: .ok, message: "OK", latencyMS: 1)
    }

    func transcribeFile(
        _ request: CloudASRFileRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CloudASRTranscriptionResult {
        let text = await withCheckedContinuation { continuation in
            let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                started = true
                completion = continuation
                let waiters = startWaiters
                startWaiters.removeAll()
                return waiters
            }
            waiters.forEach { $0.resume() }
        }
        return CloudASRTranscriptionResult(
            text: text,
            durationSeconds: nil,
            providerID: providerID,
            warnings: []
        )
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                guard !started else { return true }
                startWaiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func complete(text: String) {
        let continuation = lock.withLock { () -> CheckedContinuation<String, Never>? in
            defer { completion = nil }
            return completion
        }
        continuation?.resume(returning: text)
    }
}

private final class LockedBufferedCloudCallback: @unchecked Sendable {
    private let lock = NSLock()
    private var storedText: String?
    private var storedIsFinal = false

    var text: String? { lock.withLock { storedText } }
    var isFinal: Bool { lock.withLock { storedIsFinal } }

    func set(text: String, isFinal: Bool) {
        lock.withLock {
            storedText = text
            storedIsFinal = isFinal
        }
    }
}
