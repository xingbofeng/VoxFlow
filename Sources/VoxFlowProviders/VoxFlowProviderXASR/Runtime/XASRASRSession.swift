import Foundation
import VoxFlowASRCore
import VoxFlowAudio

final class XASRASRSession: ASRSession, @unchecked Sendable {
    let sessionID: ASRSessionID
    var revision: UInt64 { lock.withLock { currentRevision } }
    var events: AsyncStream<ASREvent> { eventStream.stream }
    private let eventStream = ASREventStream()
    private let modelURL: URL
    private let streamFactory: any XASRStreamMaking
    private let lock = NSLock()
    private enum State { case created, preparing, accepting, finishing, closed }
    private var state: State = .created
    private var currentRevision: UInt64 = 0
    private var loading: Task<any XASRStreaming, Error>?
    private var stream: (any XASRStreaming)?
    private var nextSequence: UInt64?
    private var nextStartSample: UInt64?
    private var processedSamples: UInt64 = 0
    private var processedFrames: UInt64 = 0
    private var droppedFrames: UInt64 = 0
    private var speechStarted = false
    private var lastPartial = ""
    init(sessionID: ASRSessionID, modelURL: URL, streamFactory: any XASRStreamMaking) {
        self.sessionID = sessionID; self.modelURL = modelURL; self.streamFactory = streamFactory
    }
    func start() async throws {
        let task = try lock.withLock { () throws -> Task<any XASRStreaming, Error> in
            guard state == .created else { throw XASRProviderError.invalidSessionState }
            state = .preparing
            eventStream.yield(.preparing(sessionID: sessionID, revision: bumpRevision()))
            let factory = streamFactory, directory = modelURL
            let task = Task { try await factory.makeStream(directoryURL: directory) }
            loading = task
            return task
        }
        do {
            let created = try await task.value
            let installed = lock.withLock {
                loading = nil
                guard state == .preparing else { return false }
                stream = created
                state = .accepting
                eventStream.yield(.ready(sessionID: sessionID, revision: bumpRevision()))
                return true
            }
            if !installed { await created.cancel() }
        } catch {
            await fail(error)
            throw error
        }
    }

    func accept(_ frame: AudioFrame) async throws {
        do {
            let active = try lock.withLock { () throws -> (any XASRStreaming)? in
                guard state == .accepting else {
                    if state == .closed || state == .finishing { return nil }
                    throw XASRProviderError.invalidSessionState
                }
                guard frame.sampleRate == XASRModel.sampleRate else { throw XASRRuntimeError.invalidAudio }
                if let nextSequence, frame.sequenceNumber != nextSequence {
                    droppedFrames += 1; throw XASRProviderError.audioDropped
                }
                if let nextStartSample, frame.startSample != nextStartSample {
                    droppedFrames += 1; throw XASRProviderError.audioDropped
                }
                nextSequence = frame.sequenceNumber &+ 1
                nextStartSample = frame.startSample + UInt64(frame.samples.count)
                guard !frame.samples.isEmpty else { return nil }
                processedFrames += 1
                processedSamples += UInt64(frame.samples.count)
                if !speechStarted, frame.samples.contains(where: { abs($0) > 0.0005 }) {
                    speechStarted = true
                    eventStream.yield(.speechStarted(sessionID: sessionID, revision: bumpRevision(), sequenceNumber: frame.sequenceNumber))
                }
                return stream
            }
            guard let active else { return }
            let result = XASRTextFormatter.format(try await active.accept(samples: Array(frame.samples), sampleRate: frame.sampleRate))
            lock.withLock {
                guard state == .accepting, !result.isEmpty, result != lastPartial else { return }
                lastPartial = result
                eventStream.yield(.partial(sessionID: sessionID, transcript: PartialTranscript(
                    stablePrefix: "", unstableSuffix: result, revision: bumpRevision(), audioDuration: audioDuration
                )))
            }
        } catch {
            await fail(error)
            throw error
        }
    }

    func finish() async throws {
        let active = lock.withLock { () -> (any XASRStreaming)? in
            guard state == .accepting else { return nil }
            state = .finishing
            return stream
        }
        guard let active else { return }
        do {
            let result = XASRTextFormatter.format(try await active.finish())
            guard !result.isEmpty else { throw XASRProviderError.emptyTranscript }
            lock.withLock {
                guard state == .finishing else { return }
                state = .closed
                stream = nil
                eventStream.yield(.final(sessionID: sessionID, revision: bumpRevision(), text: result))
                emitMetrics()
                eventStream.finish()
            }
        } catch {
            await fail(error)
            throw error
        }
    }

    func cancel() async {
        let cleanup = lock.withLock { () -> (Task<any XASRStreaming, Error>?, (any XASRStreaming)?) in
            guard state != .closed else { return (nil, nil) }
            state = .closed
            let cleanup = (loading, stream)
            loading = nil; stream = nil
            emitMetrics()
            eventStream.yield(.failure(sessionID: sessionID, revision: bumpRevision(), error: .init(category: .cancelled, message: "X-ASR session cancelled.")))
            eventStream.finish()
            return cleanup
        }
        cleanup.0?.cancel()
        await cleanup.1?.cancel()
    }

    private func fail(_ error: Error) async {
        let cleanup = lock.withLock { () -> (Task<any XASRStreaming, Error>?, (any XASRStreaming)?) in
            guard state != .closed else { return (nil, nil) }
            state = .closed
            let cleanup = (loading, stream)
            loading = nil; stream = nil
            emitMetrics()
            eventStream.yield(.failure(sessionID: sessionID, revision: bumpRevision(), error: XASRASRProvider.asrError(for: error)))
            eventStream.finish()
            return cleanup
        }
        cleanup.0?.cancel()
        await cleanup.1?.cancel()
    }

    // All helpers below are called with the session lock held; yielding and
    // the terminal state change are atomic with respect to late callbacks.
    private func bumpRevision() -> UInt64 { currentRevision &+= 1; return currentRevision }
    private var audioDuration: Duration { .nanoseconds(Int64(processedSamples) * 1_000_000_000 / Int64(XASRModel.sampleRate)) }
    private func emitMetrics() {
        eventStream.yield(.metrics(sessionID: sessionID, revision: bumpRevision(), metrics: .init(audioDuration: audioDuration, processedFrameCount: processedFrames, droppedFrameCount: droppedFrames)))
    }
}

enum XASRTextFormatter {
    static func format(_ text: String) -> String {
        let cjk = "\\u3400-\\u4dbf\\u4e00-\\u9fff\\uf900-\\ufaff"
        let punctuation = NSRegularExpression.escapedPattern(for: "，。！？；：、（）《》〈〉【】「」『』“”‘’")
        let patterns = [
            "(?<=[\(cjk)])\\s+(?=[\(cjk)])",
            "(?<=[\(cjk)])\\s+(?=[\(punctuation)])",
            "(?<=[\(punctuation)])\\s+(?=[\(cjk)\(punctuation)])",
            "\\s+(?=[,.!?;:%)\\]}])",
        ]
        return patterns.reduce(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            $0.replacingOccurrences(of: $1, with: "", options: .regularExpression)
        }
    }
}
