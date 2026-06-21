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
    private var audioWriter: StreamingWAVFileWriter?
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
        let fileURL = temporaryDirectory.appendingPathComponent(
            "VoxFlow-Cloud-ASR-\(UUID().uuidString).wav",
            isDirectory: false
        )
        let writer = try StreamingWAVFileWriter(fileURL: fileURL)
        lock.withLock {
            transcriptionTask?.cancel()
            transcriptionTask = nil
            audioWriter?.cancelAndDelete()
            audioWriter = writer
            generation = UUID()
            runtimeMetadata = ASRRuntimeMetadataSnapshot(sessionID: sessionID)
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        do {
            try lock.withLock {
                guard generation != nil else { return }
                try audioWriter?.append(frame)
                runtimeMetadata.audioDurationMs = audioWriter?.durationMS
            }
        } catch {
            let currentGeneration = lock.withLock { generation }
            guard let currentGeneration else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(currentGeneration) else { return }
                self.onError?(error)
            }
        }
    }

    func endAudio() {
        let snapshot: (generation: UUID, fileURL: URL, durationMS: Int, locale: Locale)?
        do {
            snapshot = try lock.withLock { () -> (UUID, URL, Int, Locale)? in
                guard let generation, let writer = audioWriter else { return nil }
                let finished = try writer.finish()
                audioWriter = nil
                return (generation, finished.fileURL, finished.durationMS, locale)
            }
        } catch {
            let currentGeneration = lock.withLock { generation }
            guard let currentGeneration else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(currentGeneration) else { return }
                self.onError?(error)
            }
            return
        }
        guard let (generation, fileURL, durationMS, locale) = snapshot else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: fileURL) }

            do {
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
                    runtimeMetadata.audioDurationMs = durationMS
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
            audioWriter?.cancelAndDelete()
            audioWriter = nil
            transcriptionTask?.cancel()
            transcriptionTask = nil
        }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        lock.withLock { self.generation == generation }
    }
}

private final class StreamingWAVFileWriter {
    struct FinishedAudio {
        let fileURL: URL
        let durationMS: Int
    }

    let fileURL: URL
    private let handle: FileHandle
    private var sampleRate: Int?
    private var pcmByteCount = 0
    private var sampleCount = 0
    private var isFinished = false

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try FileHandle(forWritingTo: fileURL)
        try writePlaceholderHeader()
    }

    var durationMS: Int? {
        guard let sampleRate, sampleRate > 0 else { return nil }
        return Int(Double(sampleCount) / Double(sampleRate) * 1_000)
    }

    func append(_ frame: AudioFrame) throws {
        guard !isFinished else { return }
        if let sampleRate, sampleRate != frame.sampleRate {
            throw BufferedCloudASREngineError.inconsistentSampleRate
        }
        if sampleRate == nil {
            sampleRate = frame.sampleRate
        }
        guard frame.sampleRate > 0 else {
            throw BufferedCloudASREngineError.inconsistentSampleRate
        }
        var pcm = Data(capacity: frame.samples.count * MemoryLayout<Int16>.size)
        for sample in frame.samples {
            let clamped = min(1, max(-1, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        try handle.write(contentsOf: pcm)
        pcmByteCount += pcm.count
        sampleCount += frame.samples.count
    }

    func finish() throws -> FinishedAudio {
        guard !isFinished else {
            return FinishedAudio(fileURL: fileURL, durationMS: durationMS ?? 0)
        }
        guard let sampleRate, pcmByteCount > 0 else {
            throw BufferedCloudASREngineError.noAudio
        }
        try rewriteHeader(sampleRate: sampleRate)
        try handle.close()
        isFinished = true
        return FinishedAudio(fileURL: fileURL, durationMS: durationMS ?? 0)
    }

    func cancelAndDelete() {
        try? handle.close()
        try? FileManager.default.removeItem(at: fileURL)
        isFinished = true
    }

    private func writePlaceholderHeader() throws {
        try handle.write(contentsOf: Data(repeating: 0, count: 44))
    }

    private func rewriteHeader(sampleRate: Int) throws {
        try handle.seek(toOffset: 0)
        let sampleRate = UInt32(sampleRate)
        let byteRate = sampleRate * 2
        var header = Data(capacity: 44)
        header.appendASCII("RIFF")
        header.appendLittleEndian(UInt32(36 + pcmByteCount))
        header.appendASCII("WAVE")
        header.appendASCII("fmt ")
        header.appendLittleEndian(UInt32(16))
        header.appendLittleEndian(UInt16(1))
        header.appendLittleEndian(UInt16(1))
        header.appendLittleEndian(sampleRate)
        header.appendLittleEndian(byteRate)
        header.appendLittleEndian(UInt16(2))
        header.appendLittleEndian(UInt16(16))
        header.appendASCII("data")
        header.appendLittleEndian(UInt32(pcmByteCount))
        try handle.write(contentsOf: header)
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
