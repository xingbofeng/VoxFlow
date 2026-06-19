import Foundation
import VoxFlowAudio
import VoxFlowProviderAliyunDashScope

final class AliyunDashScopeRealtimeASREngine: ASREngine, ASRRuntimeMetadataProviding, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private let lock = NSLock()
    private let client: any AliyunDashScopeRealtimeASRStreamingClient
    private let configurationProvider: @Sendable () throws -> AliyunDashScopeRealtimeASRConfiguration
    private var generation: UUID?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var streamingTask: Task<Void, Never>?
    private var sampleRate: Int?
    private var committedText = ""
    private var latestText = ""
    private var runtimeMetadata = ASRRuntimeMetadataSnapshot()

    init(
        client: any AliyunDashScopeRealtimeASRStreamingClient = AliyunDashScopeRealtimeASRClient(),
        configurationProvider: @escaping @Sendable () throws -> AliyunDashScopeRealtimeASRConfiguration
    ) {
        self.client = client
        self.configurationProvider = configurationProvider
    }

    var isAvailable: Bool {
        (try? configurationProvider().isComplete) == true
    }

    var asrRuntimeMetadataSnapshot: ASRRuntimeMetadataSnapshot {
        lock.withLock { runtimeMetadata }
    }

    func configure(locale: Locale) {}

    func start() throws {
        let configuration = try configurationProvider()
        guard configuration.isComplete else {
            throw AliyunDashScopeRealtimeASRError.missingCredential
        }
        let generation = UUID()
        let stream = AsyncStream<Data> { continuation in
            lock.withLock {
                audioContinuation = continuation
            }
        }
        lock.withLock {
            streamingTask?.cancel()
            committedText = ""
            latestText = ""
            sampleRate = nil
            self.generation = generation
            runtimeMetadata = ASRRuntimeMetadataSnapshot(sessionID: "aliyun-dashscope-asr-\(generation.uuidString)")
        }
        streamingTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            do {
                try await client.transcribe(configuration: configuration, audioChunks: stream) { [weak self] message in
                    self?.handle(message, generation: generation)
                }
                guard isCurrent(generation), !Task.isCancelled else { return }
                lock.withLock {
                    runtimeMetadata.finalLatencyMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                }
            } catch {
                guard isCurrent(generation), !Task.isCancelled else { return }
                lock.withLock {
                    runtimeMetadata.errorCode = String(describing: type(of: error))
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(generation) else { return }
                    self.onError?(error)
                }
            }
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        let encoded: Data
        do {
            encoded = try encode(frame)
        } catch {
            let currentGeneration = lock.withLock { generation }
            guard let currentGeneration else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(currentGeneration) else { return }
                self.onError?(error)
            }
            return
        }
        lock.withLock { audioContinuation }?.yield(encoded)
    }

    func endAudio() {
        lock.withLock {
            audioContinuation?.finish()
            audioContinuation = nil
        }
    }

    func stop() {
        cancel()
    }

    func cancel() {
        lock.withLock {
            generation = nil
            audioContinuation?.finish()
            audioContinuation = nil
            streamingTask?.cancel()
            streamingTask = nil
            committedText = ""
            latestText = ""
            sampleRate = nil
        }
    }

    private func encode(_ frame: AudioFrame) throws -> Data {
        try lock.withLock {
            if let sampleRate, sampleRate != frame.sampleRate {
                throw AliyunDashScopeRealtimeASRError.inconsistentSampleRate
            }
            sampleRate = frame.sampleRate
            guard frame.sampleRate == 16_000 else {
                throw AliyunDashScopeRealtimeASRError.unsupportedSampleRate(frame.sampleRate)
            }
            runtimeMetadata.audioDurationMs = Int(
                Double(frame.startSample + UInt64(frame.samples.count)) / Double(frame.sampleRate) * 1_000
            )
            return Self.pcm16Data(samples: frame.samples)
        }
    }

    private func handle(_ message: AliyunDashScopeRealtimeASRMessage, generation: UUID) {
        let emission = lock.withLock { () -> (String, Bool)? in
            guard self.generation == generation else { return nil }
            if message.event == .taskFinished {
                return latestText.isEmpty ? nil : (latestText, true)
            }
            guard message.event == .resultGenerated, !message.isHeartbeat else { return nil }
            let text = message.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                latestText = Self.combinedTranscript(prefix: committedText, text: text)
                if message.isFinalResult {
                    committedText = latestText
                }
            }
            return text.isEmpty ? nil : (latestText, false)
        }
        guard let emission else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.onTranscription?(emission.0, emission.1)
        }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        lock.withLock { self.generation == generation }
    }

    private static func combinedTranscript(prefix: String, text: String) -> String {
        guard !prefix.isEmpty else { return text }
        guard !text.hasPrefix(prefix) else { return text }
        return prefix + text
    }

    private static func pcm16Data(samples: ContiguousArray<Float>) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = min(1, max(-1, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}
