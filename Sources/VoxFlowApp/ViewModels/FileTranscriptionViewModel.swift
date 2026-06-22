@preconcurrency import AVFoundation
import Combine
import Foundation

enum TranscriptionJobStatus: String {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

enum FileTranscriptionExportFormat {
    case txt
    case markdown
    case srt
}

struct TranscriptionSegment: Equatable, Sendable {
    let startMS: Int
    let endMS: Int
    let text: String
}

struct FileTranscriptionResult: Equatable, Sendable {
    let text: String
    let durationMS: Int
    let segments: [TranscriptionSegment]
}

protocol FileTranscriptionWorking: Sendable {
    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> FileTranscriptionResult
}

struct ASRFileTranscriptionWorker: FileTranscriptionWorking, @unchecked Sendable {
    private let locale: Locale
    private let effectiveEngineType: () -> ASREngineType
    private let makeEngine: (ASREngineType) -> ASREngine

    init(
        asrManager: ASRManager = ASRManager(),
        locale: Locale = RecognitionLanguage.default.locale,
        effectiveEngineType: (() -> ASREngineType)? = nil,
        makeEngine: ((ASREngineType) -> ASREngine)? = nil,
        finalResultTimeoutNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.locale = locale
        self.finalResultTimeoutNanoseconds = finalResultTimeoutNanoseconds
        self.effectiveEngineType = effectiveEngineType ?? { asrManager.effectiveSelectedEngineType }
        self.makeEngine = makeEngine ?? { asrManager.makeEngine(type: $0) }
    }

    private let finalResultTimeoutNanoseconds: UInt64

    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> FileTranscriptionResult {
        guard RecognitionLanguage.supportsIdentifier(locale.identifier) else {
            throw FileTranscriptionError.unsupportedRecognitionLanguage(locale.identifier)
        }

        let engine = makeEngine(Self.engineType(forProviderID: asrProviderID) ?? effectiveEngineType())
        let finalText = FinalTextContinuation()
        engine.onTranscription = { text, isFinal in
            if isFinal {
                finalText.resume(.success(text))
            }
        }
        engine.onError = { error in
            finalText.resume(.failure(error))
        }

        do {
            engine.configure(locale: locale)
            try engine.start()
            let cancellation = CancellableASREngineBox(engine)
            let audioFrameForwarder = ASREngineAudioFrameForwarder()
            audioFrameForwarder.attach(engine)
            defer { audioFrameForwarder.detach() }
            let audioFile = try AVAudioFile(forReading: fileURL)
            let durationMS = Int((Double(audioFile.length) / audioFile.processingFormat.sampleRate) * 1_000)
            try feed(audioFile: audioFile, to: audioFrameForwarder, progress: progress)
            audioFrameForwarder.finish()
            engine.endAudio()
            let text = try await withTaskCancellationHandler {
                try await finalText.wait(timeoutNanoseconds: finalResultTimeoutNanoseconds)
            } onCancel: {
                cancellation.cancel()
                finalText.resume(.failure(CancellationError()))
            }
            progress(1)
            return FileTranscriptionResult(
                text: text,
                durationMS: durationMS,
                segments: [TranscriptionSegment(startMS: 0, endMS: max(durationMS, 1), text: text)]
            )
        } catch {
            engine.cancel()
            throw error
        }
    }

    private func feed(
        audioFile: AVAudioFile,
        to audioFrameForwarder: any ASREngineAudioFrameForwarding,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let totalFrames = max(audioFile.length, 1)
        let chunkSize: AVAudioFrameCount = 4_096
        while audioFile.framePosition < audioFile.length {
            if Task.isCancelled {
                throw CancellationError()
            }
            let remaining = AVAudioFrameCount(audioFile.length - audioFile.framePosition)
            let framesToRead = min(chunkSize, remaining)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: framesToRead
            ) else {
                throw FileTranscriptionError.invalidAudioBuffer
            }
            try audioFile.read(into: buffer, frameCount: framesToRead)
            audioFrameForwarder.appendAudioBuffer(buffer)
            progress(Double(audioFile.framePosition) / Double(totalFrames))
        }
    }

    private static func engineType(forProviderID providerID: String?) -> ASREngineType? {
        switch providerID {
        case ASRProviderID.appleSpeech:
            return .apple
        case ASRProviderID.funASR:
            return .funASR
        case ASRProviderID.whisper:
            return .whisper
        case ASRProviderID.qwen3:
            return .qwen3
        case ASRProviderID.senseVoice:
            return .senseVoice
        case ASRProviderID.paraformer:
            return .paraformer
        case ASRProviderID.nvidiaNemotron:
            return .nvidiaNemotron
        case ASRProviderID.parakeetStreaming:
            return .parakeetStreaming
        case ASRProviderID.omnilingualASR:
            return .omnilingualASR
        case ASRProviderID.groqWhisper:
            return .groqWhisper
        case ASRProviderID.tencentCloudASR:
            return .tencentCloud
        case ASRProviderID.qwenCloudASR:
            return .aliyunDashScope
        default:
            return nil
        }
    }
}

private final class FinalTextContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?

    func wait(timeoutNanoseconds: UInt64) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.wait()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                let error = FileTranscriptionError.finalResultTimedOut
                self.resume(.failure(error))
                throw error
            }

            guard let text = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return text
        }
    }

    private func wait() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resume(_ result: Result<String, Error>) {
        lock.lock()
        if self.result != nil {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return }
        switch result {
        case .success(let text):
            continuation.resume(returning: text)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private final class CancellableASREngineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: ASREngine?

    init(_ engine: ASREngine) {
        self.engine = engine
    }

    func cancel() {
        lock.lock()
        let engine = engine
        lock.unlock()
        engine?.cancel()
    }
}

@MainActor
final class FileTranscriptionViewModel: ObservableObject {
    @Published private(set) var jobs: [TranscriptionJobRecord] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastExport: String?
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var lastActionTone = ActionFeedbackTone.success

    var worker: any FileTranscriptionWorking

    private let environment: any AppServiceProviding
    private let currentASRProviderID: () -> String
    private let clipboardWriter: ClipboardWriting
    private var segmentsByJobID: [String: [TranscriptionSegment]] = [:]
    private var runningTasks: [String: RunningFileTranscriptionTask] = [:]

    static let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "mp4", "mov"]

    init(
        environment: any AppServiceProviding,
        worker: (any FileTranscriptionWorking)? = nil,
        currentLanguage: @escaping () -> RecognitionLanguage = { LanguageManager.shared.currentLanguage },
        currentASRProviderID: @escaping () -> String = { ASREngineType.apple.providerID },
        clipboardWriter: ClipboardWriting = GeneralPasteboardWriter()
    ) {
        self.environment = environment
        self.currentASRProviderID = currentASRProviderID
        self.worker = worker ?? ASRFileTranscriptionWorker(locale: currentLanguage().locale)
        self.clipboardWriter = clipboardWriter
        do {
            try load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func load() throws {
        var restored: [TranscriptionJobRecord] = []
        for job in try environment.transcriptionJobRepository.list() {
            if job.status == TranscriptionJobStatus.running.rawValue {
                let interrupted = job.markingInterrupted(updatedAt: environment.clock.now)
                try environment.transcriptionJobRepository.save(interrupted)
                restored.append(interrupted)
            } else {
                restored.append(job)
            }
        }
        jobs = restored
    }

    @discardableResult
    func enqueueFiles(_ fileURLs: [URL]) throws -> [TranscriptionJobRecord] {
        var added: [TranscriptionJobRecord] = []
        for fileURL in fileURLs {
            try validate(fileURL)
            let now = environment.clock.now
            let job = TranscriptionJobRecord(
                id: UUID().uuidString,
                sourceFilePath: fileURL.path,
                sourceFileName: fileURL.lastPathComponent,
                status: TranscriptionJobStatus.queued.rawValue,
                progress: 0,
                rawText: nil,
                finalText: nil,
                asrProviderID: currentASRProviderID(),
                styleID: nil,
                errorMessage: nil,
                durationMS: 0,
                createdAt: now,
                updatedAt: now,
                completedAt: nil
            )
            try environment.transcriptionJobRepository.save(job)
            jobs.append(job)
            added.append(job)
        }
        lastError = nil
        lastActionMessage = "已添加 \(added.count) 个转写任务"
        return added
    }

    func start(jobID: String) {
        startRegisteredRun(jobID: jobID, resetBeforeRun: false)
    }

    @discardableResult
    private func startRegisteredRun(
        jobID: String,
        resetBeforeRun: Bool
    ) -> Task<Void, Never>? {
        guard runningTasks[jobID] == nil else { return nil }
        let runID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(jobID: jobID, runID: runID, resetBeforeRun: resetBeforeRun)
            await MainActor.run {
                if self.runningTasks[jobID]?.runID == runID {
                    self.runningTasks[jobID] = nil
                }
            }
        }
        runningTasks[jobID] = RunningFileTranscriptionTask(runID: runID, task: task)
        return task
    }

    func run(jobID: String) async {
        guard let task = startRegisteredRun(jobID: jobID, resetBeforeRun: false) else {
            return
        }
        await task.value
    }

    private func run(
        jobID: String,
        runID: UUID?,
        resetBeforeRun: Bool
    ) async {
        guard var job = job(id: jobID) else { return }
        do {
            if resetBeforeRun {
                job = job.resettingForRetry(updatedAt: environment.clock.now)
                try saveIfCurrent(job, runID: runID)
            }
            guard isCurrentRun(jobID: jobID, runID: runID) else { return }
            job = job.with(
                status: .running,
                progress: 0,
                errorMessage: nil,
                updatedAt: environment.clock.now
            )
            try save(
                job
            )
            let result = try await worker.transcribe(
                fileURL: URL(fileURLWithPath: job.sourceFilePath),
                asrProviderID: job.asrProviderID
            ) { [weak self] progress in
                Task { @MainActor in
                    try? self?.updateProgress(jobID: jobID, runID: runID, progress: progress)
                }
            }
            guard isCurrentRun(jobID: jobID, runID: runID), !Task.isCancelled else {
                return
            }
            segmentsByJobID[jobID] = result.segments
            try save(
                job.with(
                    status: .completed,
                    progress: 1,
                    rawText: result.text,
                    finalText: result.text,
                    errorMessage: nil,
                    durationMS: result.durationMS,
                    completedAt: environment.clock.now,
                    updatedAt: environment.clock.now
                )
            )
            lastError = nil
            lastActionMessage = "转写已完成"
            lastActionTone = .success
        } catch is CancellationError {
            guard isCurrentRun(jobID: jobID, runID: runID) else { return }
            try? save(
                job.with(
                    status: .cancelled,
                    progress: 0,
                    errorMessage: nil,
                    updatedAt: environment.clock.now
                )
            )
        } catch {
            guard isCurrentRun(jobID: jobID, runID: runID) else { return }
            try? save(
                job.with(
                    status: .failed,
                    progress: 0,
                    errorMessage: error.localizedDescription,
                    updatedAt: environment.clock.now
                )
            )
            lastError = error.localizedDescription
        }
    }

    func cancel(jobID: String) {
        runningTasks[jobID]?.task.cancel()
        runningTasks[jobID] = nil
        if let job = job(id: jobID) {
            try? save(
                job.with(
                    status: .cancelled,
                    progress: 0,
                    updatedAt: environment.clock.now
                )
            )
        }
    }

    func delete(jobID: String) {
        cancel(jobID: jobID)
        segmentsByJobID.removeValue(forKey: jobID)
        do {
            try environment.transcriptionJobRepository.delete(id: jobID)
            jobs.removeAll { $0.id == jobID }
            lastError = nil
            lastActionMessage = "已删除转写任务"
            lastActionTone = .destructive
        } catch {
            lastError = error.localizedDescription
            lastActionTone = .destructive
        }
    }

    func retry(jobID: String) async {
        guard let task = startRegisteredRun(jobID: jobID, resetBeforeRun: true) else {
            return
        }
        await task.value
    }

    func export(jobID: String, format: FileTranscriptionExportFormat) throws -> String {
        guard let job = job(id: jobID), let text = job.finalText else {
            throw FileTranscriptionError.resultUnavailable
        }
        let output: String
        switch format {
        case .txt:
            output = text
        case .markdown:
            output = "# \(job.sourceFileName)\n\n\(text)"
        case .srt:
            output = srt(for: job, text: text)
        }
        lastExport = output
        lastError = nil
        lastActionMessage = "已生成 \(format.title) 导出内容"
        return output
    }

    @discardableResult
    func saveAsNote(jobID: String) throws -> NoteRecord {
        guard let job = job(id: jobID), let text = job.finalText else {
            throw FileTranscriptionError.resultUnavailable
        }
        let now = environment.clock.now
        let note = NoteRecord(
            id: UUID().uuidString,
            title: job.sourceFileName,
            bodyMarkdown: "# \(job.sourceFileName)\n\n\(text)",
            sourceType: "fileTranscription",
            sourceID: job.id,
            tags: ["file-transcription"],
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try environment.noteRepository.save(note)
        lastError = nil
        lastActionMessage = "已保存为笔记"
        return note
    }

    func report(error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    func statusTitle(for job: TranscriptionJobRecord) -> String {
        switch TranscriptionJobStatus(rawValue: job.status) {
        case .queued:
            return "等待开始"
        case .running:
            return "转写中"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
        case nil:
            return job.status
        }
    }

    func primaryActionTitle(for job: TranscriptionJobRecord) -> String {
        job.status == TranscriptionJobStatus.queued.rawValue ? "开始" : "重试"
    }

    func copyResult(jobID: String) throws {
        guard let text = job(id: jobID)?.finalText, !text.isEmpty else {
            throw FileTranscriptionError.resultUnavailable
        }
        clipboardWriter.copy(text)
        lastError = nil
        lastActionMessage = "已复制转写结果"
        lastActionTone = .success
    }

    private func validate(_ fileURL: URL) throws {
        let fileExtension = fileURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(fileExtension) else {
            throw FileTranscriptionError.unsupportedFormat(fileExtension)
        }
    }

    private func updateProgress(jobID: String, runID: UUID?, progress: Double) throws {
        guard isCurrentRun(jobID: jobID, runID: runID) else { return }
        guard let job = job(id: jobID),
              job.status == TranscriptionJobStatus.running.rawValue else {
            return
        }
        try save(
            job.with(
                status: .running,
                progress: max(0, min(1, progress)),
                updatedAt: environment.clock.now
            )
        )
    }

    private func save(_ job: TranscriptionJobRecord) throws {
        try environment.transcriptionJobRepository.save(job)
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
    }

    private func saveIfCurrent(_ job: TranscriptionJobRecord, runID: UUID?) throws {
        guard isCurrentRun(jobID: job.id, runID: runID) else { return }
        try save(job)
    }

    private func isCurrentRun(jobID: String, runID: UUID?) -> Bool {
        guard let runID else { return true }
        return runningTasks[jobID]?.runID == runID
    }

    private func job(id: String) -> TranscriptionJobRecord? {
        jobs.first { $0.id == id }
    }

    private func srt(for job: TranscriptionJobRecord, text: String) -> String {
        let storedSegments = segmentsByJobID[job.id]
        let segments = storedSegments?.isEmpty == false
            ? storedSegments!
            : [TranscriptionSegment(startMS: 0, endMS: max(job.durationMS, 1), text: text)]
        return segments.enumerated().map { index, segment in
            """
            \(index + 1)
            \(Self.srtTimestamp(segment.startMS)) --> \(Self.srtTimestamp(segment.endMS))
            \(segment.text)
            """
        }
        .joined(separator: "\n\n")
    }

    private static func srtTimestamp(_ milliseconds: Int) -> String {
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let seconds = (milliseconds % 60_000) / 1_000
        let ms = milliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, ms)
    }
}

private struct RunningFileTranscriptionTask {
    let runID: UUID
    let task: Task<Void, Never>
}

private extension FileTranscriptionExportFormat {
    var title: String {
        switch self {
        case .txt: return "TXT"
        case .markdown: return "Markdown"
        case .srt: return "SRT"
        }
    }
}

enum FileTranscriptionError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case unsupportedRecognitionLanguage(String)
    case resultUnavailable
    case invalidAudioBuffer
    case finalResultTimedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "不支持的文件格式：\(format)"
        case .unsupportedRecognitionLanguage(let identifier):
            return "当前文件转写语言不受支持：\(identifier)。"
        case .resultUnavailable:
            return "转写结果不可用。"
        case .invalidAudioBuffer:
            return "无法读取音频缓冲区。"
        case .finalResultTimedOut:
            return "等待最终转写结果超时。"
        }
    }
}

private extension TranscriptionJobRecord {
    func markingInterrupted(updatedAt: Date) -> TranscriptionJobRecord {
        TranscriptionJobRecord(
            id: id,
            sourceFilePath: sourceFilePath,
            sourceFileName: sourceFileName,
            status: TranscriptionJobStatus.failed.rawValue,
            progress: 0,
            rawText: rawText,
            finalText: finalText,
            asrProviderID: asrProviderID,
            styleID: styleID,
            errorMessage: "上次转写被中断，请重试。",
            durationMS: durationMS,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: nil
        )
    }

    func resettingForRetry(updatedAt: Date) -> TranscriptionJobRecord {
        TranscriptionJobRecord(
            id: id,
            sourceFilePath: sourceFilePath,
            sourceFileName: sourceFileName,
            status: TranscriptionJobStatus.queued.rawValue,
            progress: 0,
            rawText: nil,
            finalText: nil,
            asrProviderID: asrProviderID,
            styleID: styleID,
            errorMessage: nil,
            durationMS: 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: nil
        )
    }

    func with(
        status: TranscriptionJobStatus,
        progress: Double? = nil,
        rawText: String? = nil,
        finalText: String? = nil,
        errorMessage: String? = nil,
        durationMS: Int? = nil,
        completedAt: Date? = nil,
        updatedAt: Date
    ) -> TranscriptionJobRecord {
        TranscriptionJobRecord(
            id: id,
            sourceFilePath: sourceFilePath,
            sourceFileName: sourceFileName,
            status: status.rawValue,
            progress: progress ?? self.progress,
            rawText: rawText ?? self.rawText,
            finalText: finalText ?? self.finalText,
            asrProviderID: asrProviderID,
            styleID: styleID,
            errorMessage: errorMessage,
            durationMS: durationMS ?? self.durationMS,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }
}
