import Foundation
import VoxFlowASRCore
import VoxFlowAudio

final class ParaformerASRSession: VoxFlowASRCore.ASRSession, @unchecked Sendable {
    let sessionID: VoxFlowASRCore.ASRSessionID
    var events: AsyncStream<VoxFlowASRCore.ASREvent> { eventStream.stream }

    private let modelURL: URL
    private let transcriberFactory: any ParaformerTranscriberMaking
    private let eventStream = VoxFlowASRCore.ASREventStream()
    private let lock = NSLock()
    private var currentRevision: UInt64 = 0
    private var processedFrameCount: UInt64 = 0
    private var processedSampleCount: UInt64 = 0
    private var sampleRate: Int = 16_000
    private var audioSamples: [Float] = []
    private var hasStartedSpeech = false
    private var isClosed = false
    private var transcriberTask: Task<any ParaformerTranscribing, Error>?
    private var partialTask: Task<Void, Never>?
    private var lastPartialSampleCount = 0

    var revision: UInt64 {
        lock.withLock { currentRevision }
    }

    init(
        sessionID: VoxFlowASRCore.ASRSessionID,
        modelURL: URL,
        transcriberFactory: any ParaformerTranscriberMaking
    ) {
        self.sessionID = sessionID
        self.modelURL = modelURL
        self.transcriberFactory = transcriberFactory
    }

    func start() async throws {
        eventStream.yield(.preparing(sessionID: sessionID, revision: revision))
        let factory = transcriberFactory
        let modelURL = modelURL
        transcriberTask = Task {
            try await factory.makeTranscriber(directoryURL: modelURL)
        }
        eventStream.yield(.ready(sessionID: sessionID, revision: nextRevision()))
    }

    func accept(_ frame: AudioFrame) async throws {
        let acceptance = lock.withLock { () -> (Bool, [Float]?) in
            guard !isClosed else { return (false, nil) }
            processedFrameCount += 1
            processedSampleCount += UInt64(frame.samples.count)
            sampleRate = frame.sampleRate
            audioSamples.append(contentsOf: frame.samples)
            let shouldEmitSpeechStarted = !hasStartedSpeech && !frame.samples.isEmpty
            if shouldEmitSpeechStarted {
                hasStartedSpeech = true
            }
            guard partialTask == nil,
                  audioSamples.count - lastPartialSampleCount >= max(frame.sampleRate, 1) else {
                return (shouldEmitSpeechStarted, nil)
            }
            lastPartialSampleCount = audioSamples.count
            return (shouldEmitSpeechStarted, Array(audioSamples))
        }

        if acceptance.0 {
            eventStream.yield(
                .speechStarted(
                    sessionID: sessionID,
                    revision: nextRevision(),
                    sequenceNumber: frame.sequenceNumber
                )
            )
        }
        if let partialSamples = acceptance.1 {
            schedulePartialTranscription(samples: partialSamples)
        }
    }

    func finish() async throws {
        guard !isClosedForCallback else { return }
        await cancelPartialTask()
        let samples = lock.withLock { audioSamples }
        do {
            guard Self.containsAudibleSamples(samples) else {
                emitEmptyTranscriptFailure()
                throw ParaformerProviderError.emptyTranscript
            }
            guard let transcriberTask else {
                throw ParaformerProviderError.modelNotInstalled
            }
            let transcriber = try await transcriberTask.value
            let text = try await transcriber.transcribe(audio: samples)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                emitEmptyTranscriptFailure()
                throw ParaformerProviderError.emptyTranscript
            }
            emitFinal(text)
        } catch {
            emitFailure(error)
            throw error
        }
    }

    func cancel() async {
        transcriberTask?.cancel()
        await cancelPartialTask()
        guard close() else { return }
        eventStream.yield(
            .failure(
                sessionID: sessionID,
                revision: nextRevision(),
                error: VoxFlowASRCore.ASRError(
                    category: .cancelled,
                    message: "Paraformer session was cancelled."
                )
            )
        )
        eventStream.finish()
    }

    private var isClosedForCallback: Bool {
        lock.withLock { isClosed }
    }

    private func schedulePartialTranscription(samples: [Float]) {
        guard Self.containsAudibleSamples(samples) else { return }
        partialTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.lock.withLock {
                    self.partialTask = nil
                }
            }
            do {
                guard let transcriberTask = self.transcriberTask else { return }
                let transcriber = try await transcriberTask.value
                let text = try await transcriber.transcribe(audio: samples)
                self.emitPartial(text)
            } catch is CancellationError {
            } catch {
            }
        }
    }

    private func cancelPartialTask() async {
        let task = lock.withLock { () -> Task<Void, Never>? in
            let task = partialTask
            partialTask = nil
            return task
        }
        task?.cancel()
        await task?.value
    }

    private func emitPartial(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isClosedForCallback else { return }
        eventStream.yield(
            .partial(
                sessionID: sessionID,
                transcript: VoxFlowASRCore.PartialTranscript(
                    stablePrefix: "",
                    unstableSuffix: trimmed,
                    revision: nextRevision(),
                    audioDuration: metrics().audioDuration
                )
            )
        )
    }

    private func emitEmptyTranscriptFailure() {
        emitFailure(
            VoxFlowASRCore.ASRError(
                category: .emptyTranscript,
                message: ParaformerProviderError.emptyTranscript.localizedDescription
            )
        )
    }

    private func emitFinal(_ text: String) {
        guard close() else { return }
        eventStream.yield(.final(sessionID: sessionID, revision: nextRevision(), text: text))
        eventStream.yield(.metrics(sessionID: sessionID, revision: nextRevision(), metrics: metrics()))
        eventStream.finish()
    }

    private func emitFailure(_ error: Error) {
        emitFailure(ParaformerASRProvider.asrError(for: error))
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

    private static func containsAudibleSamples(_ samples: [Float]) -> Bool {
        samples.contains { abs($0) > 0.0005 }
    }
}
