import Foundation
import VoxFlowAudio
import VoxFlowProviderCloudCore

enum BufferedCloudASREngineError: Error, LocalizedError, Equatable {
    case providerNotConfigured
    case noAudio
    case inconsistentSampleRate

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:
            return "云端语音识别尚未配置。"
        case .noAudio:
            return "没有可供识别的音频。"
        case .inconsistentSampleRate:
            return "录音采样率发生变化，无法提交云端识别。"
        }
    }
}

final class BufferedCloudASREngine: ASREngine, ASRRuntimeMetadataProviding, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private let lock = NSLock()
    private let client: any CloudASRProviderClient
    private let configuration: CloudASRProviderConfiguration
    private let configurationAvailable: @Sendable () -> Bool
    private let temporaryDirectory: URL
    private var locale = Locale(identifier: "zh_CN")
    private var frames: [AudioFrame] = []
    private var generation: UUID?
    private var transcriptionTask: Task<Void, Never>?
    private var runtimeMetadata = ASRRuntimeMetadataSnapshot()

    init(
        client: any CloudASRProviderClient,
        configuration: CloudASRProviderConfiguration,
        configurationAvailable: @escaping @Sendable () -> Bool,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.client = client
        self.configuration = configuration
        self.configurationAvailable = configurationAvailable
        self.temporaryDirectory = temporaryDirectory
    }

    var isAvailable: Bool {
        configurationAvailable()
    }

    var asrRuntimeMetadataSnapshot: ASRRuntimeMetadataSnapshot {
        lock.withLock { runtimeMetadata }
    }

    func configure(locale: Locale) {
        lock.withLock {
            self.locale = locale
        }
    }

    func start() throws {
        guard configurationAvailable() else {
            throw BufferedCloudASREngineError.providerNotConfigured
        }
        let sessionID = "cloud-asr-\(UUID().uuidString)"
        lock.withLock {
            transcriptionTask?.cancel()
            transcriptionTask = nil
            frames.removeAll(keepingCapacity: true)
            generation = UUID()
            runtimeMetadata = ASRRuntimeMetadataSnapshot(sessionID: sessionID)
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        lock.withLock {
            guard generation != nil else { return }
            frames.append(frame)
        }
    }

    func endAudio() {
        let snapshot = lock.withLock { () -> (UUID, [AudioFrame], Locale)? in
            guard let generation else { return nil }
            return (generation, frames, locale)
        }
        guard let (generation, frames, locale) = snapshot else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            let fileURL = temporaryDirectory.appendingPathComponent(
                "VoxFlow-Cloud-ASR-\(UUID().uuidString).wav",
                isDirectory: false
            )
            defer { try? FileManager.default.removeItem(at: fileURL) }

            do {
                let encoded = try PCM16WAVEncoder.encode(frames: frames)
                try encoded.data.write(to: fileURL, options: .atomic)
                let request = CloudASRFileRequest(
                    fileURL: fileURL,
                    locale: locale,
                    configuration: configuration
                )
                let startedAt = Date()
                let result = try await client.transcribeFile(request) { _ in }
                guard isCurrent(generation), !Task.isCancelled else { return }
                let latencyMS = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                lock.withLock {
                    runtimeMetadata.audioDurationMs = encoded.durationMS
                    runtimeMetadata.finalLatencyMs = latencyMS
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(generation) else { return }
                    self.onTranscription?(result.text, true)
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
        lock.withLock {
            guard self.generation == generation else {
                task.cancel()
                return
            }
            transcriptionTask = task
        }
    }

    func stop() {
        cancel()
    }

    func cancel() {
        lock.withLock {
            generation = nil
            frames.removeAll(keepingCapacity: false)
            transcriptionTask?.cancel()
            transcriptionTask = nil
        }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        lock.withLock { self.generation == generation }
    }
}

private enum PCM16WAVEncoder {
    struct EncodedAudio {
        let data: Data
        let durationMS: Int
    }

    static func encode(frames: [AudioFrame]) throws -> EncodedAudio {
        guard let first = frames.first, !frames.allSatisfy(\.samples.isEmpty) else {
            throw BufferedCloudASREngineError.noAudio
        }
        guard first.sampleRate > 0,
              frames.allSatisfy({ $0.sampleRate == first.sampleRate }) else {
            throw BufferedCloudASREngineError.inconsistentSampleRate
        }

        let samples = frames.flatMap(\.samples)
        var pcm = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = min(1, max(-1, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }

        let sampleRate = UInt32(first.sampleRate)
        let byteRate = sampleRate * 2
        var wav = Data(capacity: 44 + pcm.count)
        wav.appendASCII("RIFF")
        wav.appendLittleEndian(UInt32(36 + pcm.count))
        wav.appendASCII("WAVE")
        wav.appendASCII("fmt ")
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(sampleRate)
        wav.appendLittleEndian(byteRate)
        wav.appendLittleEndian(UInt16(2))
        wav.appendLittleEndian(UInt16(16))
        wav.appendASCII("data")
        wav.appendLittleEndian(UInt32(pcm.count))
        wav.append(pcm)

        return EncodedAudio(
            data: wav,
            durationMS: Int(Double(samples.count) / Double(first.sampleRate) * 1_000)
        )
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
