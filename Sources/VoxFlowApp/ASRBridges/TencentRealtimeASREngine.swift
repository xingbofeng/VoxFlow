import Foundation
import VoxFlowAudio
import VoxFlowProviderTencentCloud

final class TencentRealtimeASREngine: ASREngine, ASRRuntimeMetadataProviding, @unchecked Sendable {
    private static let audioChunkBufferLimit = 96

    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private let lock = NSLock()
    private let client: any TencentRealtimeASRStreamingClient
    private let configurationProvider: @Sendable () throws -> TencentRealtimeASRConfiguration
    private var generation: UUID?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var streamingTask: Task<Void, Never>?
    private var sampleRate: Int?
    private var stableSegments: [Int: String] = [:]
    private var latestText = ""
    private var runtimeMetadata = ASRRuntimeMetadataSnapshot()

    init(
        client: any TencentRealtimeASRStreamingClient = TencentRealtimeASRClient(),
        configurationProvider: @escaping @Sendable () throws -> TencentRealtimeASRConfiguration
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
        AppLogger.audio.debug(
            "TencentRealtimeASREngine start attempt sessionID=\(UUID().uuidString) localeComplete=\(configuration.isComplete)"
        )
        guard configuration.isComplete else {
            AppLogger.audio.warning("TencentRealtimeASREngine start blocked: configuration incomplete")
            throw TencentRealtimeASRError.missingCredential
        }
        let generation = UUID()
        AppLogger.audio.debug("TencentRealtimeASREngine start generation=\(generation.uuidString)")
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(Self.audioChunkBufferLimit)) { continuation in
            lock.withLock {
                audioContinuation = continuation
            }
        }
        lock.withLock {
            streamingTask?.cancel()
            stableSegments.removeAll(keepingCapacity: true)
            latestText = ""
            sampleRate = nil
            self.generation = generation
            runtimeMetadata = ASRRuntimeMetadataSnapshot(sessionID: "tencent-asr-\(generation.uuidString)")
        }
        streamingTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            do {
                try await client.transcribe(configuration: configuration, audioChunks: stream) { [weak self] message in
                    self?.handle(message, generation: generation)
                }
                guard isCurrent(generation), !Task.isCancelled else { return }
                AppLogger.audio.info("TencentRealtimeASREngine completed generation=\(generation.uuidString)")
                lock.withLock {
                    runtimeMetadata.finalLatencyMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                }
            } catch {
                AppLogger.audio.warning(
                    "TencentRealtimeASREngine transcribe failed generation=\(generation.uuidString) reason=\(error.localizedDescription)"
                )
                guard isCurrent(generation), !Task.isCancelled else { return }
                lock.withLock {
                    runtimeMetadata.errorCode = String(describing: type(of: error))
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(generation) else { return }
                    AppLogger.audio.warning("TencentRealtimeASREngine onError generation=\(generation.uuidString)")
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
            AppLogger.audio.warning("TencentRealtimeASREngine encode failed: \(error.localizedDescription)")
            let currentGeneration = lock.withLock { generation }
            guard let currentGeneration else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(currentGeneration) else { return }
                self.onError?(error)
            }
            return
        }
        let yieldResult = lock.withLock { audioContinuation }?.yield(encoded)
        if let yieldResult, case .dropped = yieldResult {
            lock.withLock {
                runtimeMetadata.droppedFrameCount = (runtimeMetadata.droppedFrameCount ?? 0) + 1
            }
            AppLogger.audio.debug("TencentRealtimeASREngine dropped frame")
        }
        if lock.withLock({ audioContinuation == nil }) {
            AppLogger.audio.debug("TencentRealtimeASREngine append ignored: stream not started")
            return
        }
        AppLogger.audio.debug("TencentRealtimeASREngine appended frame sampleRate=\(frame.sampleRate)")
    }

    func endAudio() {
        AppLogger.audio.debug(
            "TencentRealtimeASREngine endAudio generation=\(lock.withLock { generation?.uuidString ?? "nil" })"
        )
        lock.withLock {
            audioContinuation?.finish()
            audioContinuation = nil
        }
    }

    func stop() {
        AppLogger.audio.debug("TencentRealtimeASREngine stop generation=\(generation?.uuidString ?? "nil")")
        cancel()
    }

    func cancel() {
        AppLogger.audio.debug(
            "TencentRealtimeASREngine cancel generation=\(generation?.uuidString ?? "nil") segments=\(stableSegments.count)"
        )
        lock.withLock {
            generation = nil
            audioContinuation?.finish()
            audioContinuation = nil
            streamingTask?.cancel()
            streamingTask = nil
            stableSegments.removeAll(keepingCapacity: false)
            latestText = ""
            sampleRate = nil
        }
    }

    private func encode(_ frame: AudioFrame) throws -> Data {
        try lock.withLock {
            if let sampleRate, sampleRate != frame.sampleRate {
                throw TencentRealtimeASRError.inconsistentSampleRate
            }
            sampleRate = frame.sampleRate
            guard frame.sampleRate == 16_000 else {
                throw TencentRealtimeASRError.unsupportedSampleRate(frame.sampleRate)
            }
            runtimeMetadata.audioDurationMs = Int(
                Double(frame.startSample + UInt64(frame.samples.count)) / Double(frame.sampleRate) * 1_000
            )
            return Self.pcm16Data(samples: frame.samples)
        }
    }

    private func handle(_ message: TencentRealtimeASRMessage, generation: UUID) {
        let emission = lock.withLock { () -> (String, Bool)? in
            guard self.generation == generation else { return nil }
            AppLogger.audio.debug("TencentRealtimeASREngine handle message final=\(message.isFinal) stable=\(message.isStable)")
            let text = message.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                if message.isStable, let index = message.index {
                    stableSegments[index] = text
                    latestText = stableSegments.keys.sorted().compactMap { stableSegments[$0] }.joined()
                } else {
                    latestText = Self.combinedTranscript(
                        stablePrefix: stableSegments.keys.sorted().compactMap { stableSegments[$0] }.joined(),
                        liveText: text
                    )
                }
            }
            if message.isFinal {
                return latestText.isEmpty ? nil : (latestText, true)
            }
            return text.isEmpty ? nil : (latestText, false)
        }
        guard let emission else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            AppLogger.audio.debug(
                "TencentRealtimeASREngine emit textLen=\(emission.0.count) final=\(emission.1) generation=\(generation.uuidString)"
            )
            self.onTranscription?(emission.0, emission.1)
        }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        lock.withLock { self.generation == generation }
    }

    private static func combinedTranscript(stablePrefix: String, liveText: String) -> String {
        guard !stablePrefix.isEmpty else { return liveText }
        guard !liveText.hasPrefix(stablePrefix) else { return liveText }
        return stablePrefix + liveText
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
