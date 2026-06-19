import Foundation
import VoxFlowASRCore
import VoxFlowAudio

final class OmnilingualASRSession: VoxFlowASRCore.ASRSession, @unchecked Sendable {
    let sessionID: VoxFlowASRCore.ASRSessionID
    var events: AsyncStream<VoxFlowASRCore.ASREvent> { eventStream.stream }

    private let modelURL: URL
    private let languageCode: String
    private let transcriberFactory: any OmnilingualTranscriberMaking
    private let eventStream = VoxFlowASRCore.ASREventStream()
    private let lock = NSLock()
    private var currentRevision: UInt64 = 0
    private var processedFrameCount: UInt64 = 0
    private var processedSampleCount: UInt64 = 0
    private var sampleRate: Int = 16_000
    private var audioSamples: [Float] = []
    private var hasStartedSpeech = false
    private var isClosed = false
    private var transcriberTask: Task<any OmnilingualTranscribing, Error>?

    var revision: UInt64 {
        lock.withLock { currentRevision }
    }

    init(
        sessionID: VoxFlowASRCore.ASRSessionID,
        modelURL: URL,
        languageCode: String,
        transcriberFactory: any OmnilingualTranscriberMaking
    ) {
        self.sessionID = sessionID
        self.modelURL = modelURL
        self.languageCode = languageCode
        self.transcriberFactory = transcriberFactory
    }

    func start() async throws {
        eventStream.yield(.preparing(sessionID: sessionID, revision: revision))
        let factory = transcriberFactory
        let modelURL = modelURL
        transcriberTask = Task {
            try await factory.makeTranscriber(directoryURL: modelURL)
        }
        _ = try await transcriberTask?.value
        eventStream.yield(.ready(sessionID: sessionID, revision: nextRevision()))
    }

    func accept(_ frame: AudioFrame) async throws {
        let shouldEmitSpeechStarted = lock.withLock { () -> Bool in
            guard !isClosed else { return false }
            processedFrameCount += 1
            processedSampleCount += UInt64(frame.samples.count)
            sampleRate = frame.sampleRate
            audioSamples.append(contentsOf: frame.samples)
            let shouldEmit = !hasStartedSpeech && Self.containsAudibleSamples(frame.samples)
            if shouldEmit { hasStartedSpeech = true }
            return shouldEmit
        }
        if shouldEmitSpeechStarted {
            eventStream.yield(.speechStarted(sessionID: sessionID, revision: nextRevision(), sequenceNumber: frame.sequenceNumber))
        }
    }

    func finish() async throws {
        guard !isClosedForCallback else { return }
        let samples = lock.withLock { audioSamples }
        do {
            guard Self.containsAudibleSamples(samples) else {
                emitEmptyTranscriptFailure()
                throw OmnilingualProviderError.emptyTranscript
            }
            guard let transcriberTask else {
                throw OmnilingualProviderError.modelNotInstalled
            }
            let transcriber = try await transcriberTask.value
            let text = try await transcriber.transcribe(
                audio: samples,
                sampleRate: sampleRate,
                languageCode: languageCode
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                emitEmptyTranscriptFailure()
                throw OmnilingualProviderError.emptyTranscript
            }
            emitFinal(text)
        } catch {
            emitFailure(error)
            throw error
        }
    }

    func cancel() async {
        transcriberTask?.cancel()
        guard close() else { return }
        eventStream.yield(.failure(
            sessionID: sessionID,
            revision: nextRevision(),
            error: VoxFlowASRCore.ASRError(category: .cancelled, message: "Omnilingual session was cancelled.")
        ))
        eventStream.finish()
    }

    private var isClosedForCallback: Bool {
        lock.withLock { isClosed }
    }

    private func emitEmptyTranscriptFailure() {
        emitFailure(VoxFlowASRCore.ASRError(
            category: .emptyTranscript,
            message: OmnilingualProviderError.emptyTranscript.localizedDescription
        ))
    }

    private func emitFinal(_ text: String) {
        guard close() else { return }
        eventStream.yield(.final(sessionID: sessionID, revision: nextRevision(), text: text))
        eventStream.yield(.metrics(sessionID: sessionID, revision: nextRevision(), metrics: metrics()))
        eventStream.finish()
    }

    private func emitFailure(_ error: Error) {
        emitFailure(OmnilingualASRProvider.asrError(for: error))
    }

    private func emitFailure(_ asrError: VoxFlowASRCore.ASRError) {
        guard close() else { return }
        eventStream.yield(.failure(sessionID: sessionID, revision: nextRevision(), error: asrError))
        eventStream.finish()
    }

    private func close() -> Bool {
        lock.withLock {
            guard !isClosed else { return false }
            isClosed = true
            return true
        }
    }

    private func nextRevision() -> UInt64 {
        lock.withLock {
            currentRevision += 1
            return currentRevision
        }
    }

    private func metrics() -> VoxFlowASRCore.ASRMetrics {
        lock.withLock {
            let duration: Duration = sampleRate > 0
                ? .milliseconds(Int64((processedSampleCount * 1_000) / UInt64(sampleRate)))
                : .zero
            return VoxFlowASRCore.ASRMetrics(
                audioDuration: duration,
                processedFrameCount: processedFrameCount,
                droppedFrameCount: 0
            )
        }
    }

    private static func containsAudibleSamples<S: Sequence>(_ samples: S) -> Bool where S.Element == Float {
        samples.contains { abs($0) > 0.0005 }
    }
}
