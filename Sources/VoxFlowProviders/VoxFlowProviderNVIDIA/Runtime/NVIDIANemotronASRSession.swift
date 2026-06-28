import Foundation
import VoxFlowASRCore
import VoxFlowAudio

final class NVIDIANemotronASRSession: VoxFlowASRCore.ASRSession, @unchecked Sendable {
    let sessionID: VoxFlowASRCore.ASRSessionID
    var events: AsyncStream<VoxFlowASRCore.ASREvent> { eventStream.stream }

    private let modelURL: URL
    private let languageCode: String
    private let transcriberFactory: any NVIDIANemotronTranscriberMaking
    private let eventStream = VoxFlowASRCore.ASREventStream()
    private let lock = NSLock()
    private var currentRevision: UInt64 = 0
    private var processedFrameCount: UInt64 = 0
    private var processedSampleCount: UInt64 = 0
    private var sampleRate: Int = 16_000
    private var hasStartedSpeech = false
    private var isClosed = false
    private var transcriberTask: Task<any NVIDIANemotronTranscribing, Error>?
    private var wordBoostingPhrases: [String] = []

    var revision: UInt64 {
        lock.withLock { currentRevision }
    }

    init(
        sessionID: VoxFlowASRCore.ASRSessionID,
        modelURL: URL,
        languageCode: String,
        transcriberFactory: any NVIDIANemotronTranscriberMaking
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
        let languageCode = languageCode
        let wordBoostingPhrases = lock.withLock { self.wordBoostingPhrases }
        do {
            let transcriber = try await factory.makeTranscriber(directoryURL: modelURL)
            await transcriber.setPartialHandler { [weak self] text in
                self?.emitPartial(text)
            }
            await transcriber.setWordBoostingPhrases(wordBoostingPhrases)
            await transcriber.setLanguage(languageCode)
            self.transcriberTask = Task { transcriber }
            eventStream.yield(.ready(sessionID: sessionID, revision: nextRevision()))
        } catch {
            emitFailure(error)
            throw error
        }
    }

    func configurePrompt(_ prompt: String?) async throws {
        let phrases = Self.wordBoostingPhrases(from: prompt)
        lock.withLock {
            wordBoostingPhrases = phrases
        }
    }

    func accept(_ frame: AudioFrame) async throws {
        let shouldEmitSpeechStarted = lock.withLock { () -> Bool in
            guard !isClosed else { return false }
            processedFrameCount += 1
            processedSampleCount += UInt64(frame.samples.count)
            sampleRate = frame.sampleRate
            guard !hasStartedSpeech, !frame.samples.isEmpty else { return false }
            hasStartedSpeech = true
            return true
        }

        if shouldEmitSpeechStarted {
            eventStream.yield(
                .speechStarted(
                    sessionID: sessionID,
                    revision: nextRevision(),
                    sequenceNumber: frame.sequenceNumber
                )
            )
        }

        guard Self.containsAudibleSamples(frame.samples),
              let transcriberTask else { return }
        do {
            let transcriber = try await transcriberTask.value
            let partial = try await transcriber.accept(audio: Array(frame.samples))
            emitPartial(partial)
        } catch {
            emitFailure(error)
            throw error
        }
    }

    func finish() async throws {
        guard !isClosedForCallback else { return }
        do {
            guard let transcriberTask else {
                throw NVIDIANemotronProviderError.modelNotInstalled
            }
            let transcriber = try await transcriberTask.value
            let text = try await transcriber.finish()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                emitEmptyTranscriptFailure()
                throw NVIDIANemotronProviderError.emptyTranscript
            }
            emitFinal(text)
        } catch {
            emitFailure(error)
            throw error
        }
    }

    func cancel() async {
        transcriberTask?.cancel()
        if let transcriber = try? await transcriberTask?.value {
            await transcriber.cancel()
        }
        guard close() else { return }
        eventStream.yield(
            .failure(
                sessionID: sessionID,
                revision: nextRevision(),
                error: VoxFlowASRCore.ASRError(
                    category: .cancelled,
                    message: "NVIDIA Nemotron session was cancelled."
                )
            )
        )
        eventStream.finish()
    }

    private var isClosedForCallback: Bool {
        lock.withLock { isClosed }
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
                message: NVIDIANemotronProviderError.emptyTranscript.localizedDescription
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
        emitFailure(NVIDIANemotronASRProvider.asrError(for: error))
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

    private static func containsAudibleSamples(_ samples: ContiguousArray<Float>) -> Bool {
        samples.contains { abs($0) > 0.0005 }
    }

    private static func wordBoostingPhrases(from prompt: String?) -> [String] {
        let separators = CharacterSet(charactersIn: ",，\n")
        let phrases = (prompt ?? "")
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(phrases.prefix(100))
    }
}
