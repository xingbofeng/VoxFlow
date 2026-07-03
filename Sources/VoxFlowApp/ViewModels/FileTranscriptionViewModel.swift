@preconcurrency import AVFoundation
import Combine
import Foundation

enum TranscriptionJobStatus: String {
    case queued
    case running
    case completed
    case failed
    case cancelled
    case partiallyFailed
    case interrupted
}

enum FileTranscriptionExportFormat {
    case txt
    case markdown
    case srt
    case translatedTXT
    case translatedMarkdown
    case bilingualMarkdown
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

protocol PromptAwareFileTranscriptionWorking: FileTranscriptionWorking {
    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        prompt: String?,
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
        try await transcribe(
            fileURL: fileURL,
            asrProviderID: asrProviderID,
            prompt: nil,
            progress: progress
        )
    }
}

extension ASRFileTranscriptionWorker: PromptAwareFileTranscriptionWorking {
    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        prompt: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> FileTranscriptionResult {
        guard RecognitionLanguage.supportsIdentifier(locale.identifier) else {
            throw FileTranscriptionError.unsupportedRecognitionLanguage(locale.identifier)
        }

        let engine = makeEngine(Self.engineType(forProviderID: asrProviderID) ?? effectiveEngineType())
        (engine as? ASRTermPromptConfiguring)?.configureTermPrompt(prompt)
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
            let preparedAudio = try await FileTranscriptionAudioAssetPreparer.prepare(fileURL)
            defer { preparedAudio.cleanup() }
            let audioFile = try AVAudioFile(forReading: preparedAudio.url)
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
        case ASRProviderID.volcengineDoubao:
            return .volcengineDoubao
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
    @Published private(set) var lastSavedNoteID: String?
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var lastActionTone = ActionFeedbackTone.success

    /// 旧版单段 worker，保留用于既有测试 stub 注入。生产代码请通过 `pipeline` 注入。
    var worker: any FileTranscriptionWorking
    /// 自定义 pipeline（可选）。未设置时 ViewModel 会用 `FileTranscriptionWorkerPipeline` 包裹 `worker`。
    var pipeline: (any FileTranscriptionPipeline)?

    private let environment: any AppServiceProviding
    private let currentLanguageProvider: () -> RecognitionLanguage
    private let currentASRProviderID: () -> String
    private let clipboardWriter: ClipboardWriting
    private let translationCoordinator: AppleTranslationCoordinating?
    private var segmentsByJobID: [String: [TranscriptionSegment]] = [:]
    private var runningTasks: [String: RunningFileTranscriptionTask] = [:]

    static let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "mp4", "mov"]

    init(
        environment: any AppServiceProviding,
        worker: (any FileTranscriptionWorking)? = nil,
        pipeline: (any FileTranscriptionPipeline)? = nil,
        currentLanguage: @escaping () -> RecognitionLanguage = { LanguageManager.shared.currentLanguage },
        currentASRProviderID: @escaping () -> String = { ASREngineType.apple.providerID },
        clipboardWriter: ClipboardWriting = GeneralPasteboardWriter(),
        translationCoordinator: AppleTranslationCoordinating? = nil
    ) {
        self.environment = environment
        self.currentLanguageProvider = currentLanguage
        self.currentASRProviderID = currentASRProviderID
        self.worker = worker ?? ASRFileTranscriptionWorker(locale: currentLanguage().locale)
        self.pipeline = pipeline
        self.clipboardWriter = clipboardWriter
        self.translationCoordinator = translationCoordinator
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
                // 标记运行中段为 interrupted，保留已完成段以便续跑。
                try? environment.transcriptionSegmentRepository.markRunningSegmentsInterrupted(
                    jobID: job.id,
                    updatedAt: environment.clock.now
                )
                restored.append(interrupted)
            } else {
                restored.append(job)
            }
        }
        jobs = restored
    }

    @discardableResult
    func enqueueFiles(
        _ fileURLs: [URL],
        startImmediatelyWhenIdle: Bool = false
    ) throws -> [TranscriptionJobRecord] {
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
        lastActionMessage = L10n.format("transcribe.feedback.jobs_added", comment: "Added transcription jobs",
            added.count
        )
        if startImmediatelyWhenIdle,
           runningTasks.isEmpty,
           let firstJobID = added.first?.id {
            start(jobID: firstJobID)
        }
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
                // 清理旧段记录，retry 时重新切分。
                try? environment.transcriptionSegmentRepository.deleteAll(forJob: jobID)
            }
            guard isCurrentRun(jobID: jobID, runID: runID) else { return }
            job = job.with(
                status: .running,
                progress: 0,
                errorMessage: nil,
                updatedAt: environment.clock.now
            )
            try save(job)

            let existingSegments = (try? environment.transcriptionSegmentRepository.segments(forJob: jobID)) ?? []
            let activePipeline = pipeline ?? FileTranscriptionWorkerPipeline(worker: worker)
            let locale = currentLanguageProvider().locale

            // 段级状态聚合：用于决定 job 最终状态。
            let aggregation = PipelineSegmentAggregation()

            let result = try await activePipeline.transcribe(
                fileURL: URL(fileURLWithPath: job.sourceFilePath),
                asrProviderID: job.asrProviderID,
                locale: locale,
                existingSegments: existingSegments
            ) { [weak self] update in
                aggregation.record(update)
                Task { @MainActor in
                    self?.handleSegmentUpdate(
                        jobID: jobID,
                        runID: runID,
                        update: update
                    )
                }
            } progress: { [weak self] fraction, completed, total in
                Task { @MainActor in
                    self?.updateSegmentProgress(
                        jobID: jobID,
                        runID: runID,
                        fraction: fraction,
                        completed: completed,
                        total: total
                    )
                }
            }

            guard isCurrentRun(jobID: jobID, runID: runID), !Task.isCancelled else {
                return
            }
            segmentsByJobID[jobID] = result.segments

            let finalStatus: TranscriptionJobStatus = aggregation.failedCount > 0
                ? (aggregation.completedCount > 0 ? .partiallyFailed : .failed)
                : .completed
            let partialSummary = aggregation.partialFailureSummary()

            try save(
                job.with(
                    status: finalStatus,
                    progress: 1,
                    rawText: result.text,
                    finalText: result.text,
                    errorMessage: finalStatus == .completed ? nil : aggregation.failureErrorMessage(),
                    durationMS: result.durationMS,
                    completedAt: environment.clock.now,
                    updatedAt: environment.clock.now,
                    providerMode: aggregation.providerMode?.rawValue,
                    segmentCount: aggregation.totalCount,
                    segmentCompleted: aggregation.completedCount,
                    partialFailureSummary: partialSummary
                )
            )
            if finalStatus == .completed {
                lastError = nil
                lastActionMessage = L10n.localize("transcribe.feedback.completed", comment: "Transcription completed")
                lastActionTone = .success
            } else if finalStatus == .partiallyFailed {
                lastError = nil
                lastActionMessage = L10n.localize(
                    "transcribe.feedback.partially_completed",
                    comment: "Transcription partially completed"
                )
                lastActionTone = .informational
            }
        } catch is CancellationError {
            guard isCurrentRun(jobID: jobID, runID: runID) else { return }
            try? environment.transcriptionSegmentRepository.markRunningSegmentsInterrupted(
                jobID: jobID,
                updatedAt: environment.clock.now
            )
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

    private func handleSegmentUpdate(
        jobID: String,
        runID: UUID?,
        update: PipelineSegmentUpdate
    ) {
        guard isCurrentRun(jobID: jobID, runID: runID) else { return }
        let now = environment.clock.now
        let segment = TranscriptionSegmentRecord(
            id: "\(jobID)-seg-\(update.index)",
            jobID: jobID,
            index: update.index,
            startMS: update.startMS,
            endMS: update.endMS,
            status: update.status.rawValue,
            rawText: update.text,
            finalText: update.status == .completed ? update.text : nil,
            promptContext: nil,
            fallbackReason: update.fallbackReason?.rawValue,
            retryCount: update.retryCount,
            providerID: update.providerID,
            providerMode: update.providerMode.rawValue,
            errorMessage: update.error,
            durationMS: max(0, update.endMS - update.startMS),
            createdAt: now,
            updatedAt: now,
            completedAt: update.status == .completed ? now : nil
        )
        try? environment.transcriptionSegmentRepository.save(segment)
    }

    private func updateSegmentProgress(
        jobID: String,
        runID: UUID?,
        fraction: Double,
        completed: Int,
        total: Int
    ) {
        guard isCurrentRun(jobID: jobID, runID: runID) else { return }
        guard let job = job(id: jobID),
              job.status == TranscriptionJobStatus.running.rawValue else {
            return
        }
        try? environment.transcriptionJobRepository.updateSegmentsAndProgress(
            id: jobID,
            status: TranscriptionJobStatus.running.rawValue,
            progress: max(0, min(1, fraction)),
            segmentCount: total,
            segmentCompleted: completed,
            partialFailureSummary: nil,
            updatedAt: environment.clock.now
        )
        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[index] = TranscriptionJobRecord(
                id: job.id,
                sourceFilePath: job.sourceFilePath,
                sourceFileName: job.sourceFileName,
                status: job.status,
                progress: max(0, min(1, fraction)),
                rawText: job.rawText,
                finalText: job.finalText,
                asrProviderID: job.asrProviderID,
                styleID: job.styleID,
                errorMessage: job.errorMessage,
                durationMS: job.durationMS,
                createdAt: job.createdAt,
                updatedAt: environment.clock.now,
                completedAt: job.completedAt,
                providerMode: job.providerMode,
                segmentCount: total,
                segmentCompleted: completed,
                partialFailureSummary: job.partialFailureSummary,
                translatedText: job.translatedText,
                translationTargetLanguage: job.translationTargetLanguage,
                translationProvider: job.translationProvider,
                translationStatus: job.translationStatus,
                translationError: job.translationError,
                translationUpdatedAt: job.translationUpdatedAt
            )
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
            // job repository.delete 会级联清理 segments；这里显式清一遍兜底。
            try? environment.transcriptionSegmentRepository.deleteAll(forJob: jobID)
            try environment.transcriptionJobRepository.delete(id: jobID)
            jobs.removeAll { $0.id == jobID }
            lastError = nil
            lastActionMessage = L10n.localize("transcribe.feedback.deleted", comment: "Transcription job deleted")
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
        case .translatedTXT:
            guard let translated = job.translatedText, !translated.isEmpty else {
                throw FileTranscriptionError.translationUnavailable
            }
            output = translated
        case .translatedMarkdown:
            guard let translated = job.translatedText, !translated.isEmpty else {
                throw FileTranscriptionError.translationUnavailable
            }
            output = "# \(job.sourceFileName)\n\n\(translated)"
        case .bilingualMarkdown:
            guard let translated = job.translatedText, !translated.isEmpty else {
                throw FileTranscriptionError.translationUnavailable
            }
            output = bilingualMarkdown(for: job, original: text, translated: translated)
        }
        lastExport = output
        lastError = nil
        lastActionMessage = L10n.format("transcribe.feedback.exported_format", comment: "Exported format result",
            format.title
        )
        return output
    }

    /// 触发全文翻译后处理。目标语言默认当前 App 界面语言；翻译失败不改变转写任务状态。
    func translateFullText(jobID: String) async {
        guard let job = job(id: jobID), let text = job.finalText, !text.isEmpty else {
            lastError = L10n.localize(
                "transcribe.error.result_unavailable",
                comment: "Transcription result unavailable"
            )
            return
        }
        guard let coordinator = translationCoordinator else {
            lastError = L10n.localize(
                "transcribe.error.translation_unavailable",
                comment: "Translation service unavailable"
            )
            return
        }
        let targetLanguage = Self.currentInterfaceLanguageCode()
        let now = environment.clock.now
        do {
            try environment.transcriptionJobRepository.updateTranslation(
                id: jobID,
                translatedText: nil,
                targetLanguage: targetLanguage,
                provider: "appleSystem",
                status: .running,
                error: nil,
                updatedAt: now
            )
            updateJobInMemory(jobID: jobID) { record in
                TranscriptionJobRecord(
                    id: record.id,
                    sourceFilePath: record.sourceFilePath,
                    sourceFileName: record.sourceFileName,
                    status: record.status,
                    progress: record.progress,
                    rawText: record.rawText,
                    finalText: record.finalText,
                    asrProviderID: record.asrProviderID,
                    styleID: record.styleID,
                    errorMessage: record.errorMessage,
                    durationMS: record.durationMS,
                    createdAt: record.createdAt,
                    updatedAt: now,
                    completedAt: record.completedAt,
                    providerMode: record.providerMode,
                    segmentCount: record.segmentCount,
                    segmentCompleted: record.segmentCompleted,
                    partialFailureSummary: record.partialFailureSummary,
                    translatedText: record.translatedText,
                    translationTargetLanguage: targetLanguage,
                    translationProvider: "appleSystem",
                    translationStatus: TranslationStatus.running.rawValue,
                    translationError: nil,
                    translationUpdatedAt: now
                )
            }

            let translated = try await coordinator.translate(text)
            let completedAt = environment.clock.now
            try environment.transcriptionJobRepository.updateTranslation(
                id: jobID,
                translatedText: translated,
                targetLanguage: targetLanguage,
                provider: "appleSystem",
                status: .completed,
                error: nil,
                updatedAt: completedAt
            )
            updateJobInMemory(jobID: jobID) { record in
                TranscriptionJobRecord(
                    id: record.id,
                    sourceFilePath: record.sourceFilePath,
                    sourceFileName: record.sourceFileName,
                    status: record.status,
                    progress: record.progress,
                    rawText: record.rawText,
                    finalText: record.finalText,
                    asrProviderID: record.asrProviderID,
                    styleID: record.styleID,
                    errorMessage: record.errorMessage,
                    durationMS: record.durationMS,
                    createdAt: record.createdAt,
                    updatedAt: completedAt,
                    completedAt: record.completedAt,
                    providerMode: record.providerMode,
                    segmentCount: record.segmentCount,
                    segmentCompleted: record.segmentCompleted,
                    partialFailureSummary: record.partialFailureSummary,
                    translatedText: translated,
                    translationTargetLanguage: targetLanguage,
                    translationProvider: "appleSystem",
                    translationStatus: TranslationStatus.completed.rawValue,
                    translationError: nil,
                    translationUpdatedAt: completedAt
                )
            }
            lastError = nil
            lastActionMessage = L10n.localize(
                "transcribe.feedback.translation_completed",
                comment: "Translation completed"
            )
            lastActionTone = .success
        } catch {
            let failedAt = environment.clock.now
            try? environment.transcriptionJobRepository.updateTranslation(
                id: jobID,
                translatedText: nil,
                targetLanguage: targetLanguage,
                provider: "appleSystem",
                status: .failed,
                error: error.localizedDescription,
                updatedAt: failedAt
            )
            updateJobInMemory(jobID: jobID) { record in
                TranscriptionJobRecord(
                    id: record.id,
                    sourceFilePath: record.sourceFilePath,
                    sourceFileName: record.sourceFileName,
                    status: record.status,
                    progress: record.progress,
                    rawText: record.rawText,
                    finalText: record.finalText,
                    asrProviderID: record.asrProviderID,
                    styleID: record.styleID,
                    errorMessage: record.errorMessage,
                    durationMS: record.durationMS,
                    createdAt: record.createdAt,
                    updatedAt: failedAt,
                    completedAt: record.completedAt,
                    providerMode: record.providerMode,
                    segmentCount: record.segmentCount,
                    segmentCompleted: record.segmentCompleted,
                    partialFailureSummary: record.partialFailureSummary,
                    translatedText: record.translatedText,
                    translationTargetLanguage: targetLanguage,
                    translationProvider: "appleSystem",
                    translationStatus: TranslationStatus.failed.rawValue,
                    translationError: error.localizedDescription,
                    translationUpdatedAt: failedAt
                )
            }
            // 翻译失败不改变转写任务状态。
            lastError = error.localizedDescription
            lastActionMessage = L10n.localize(
                "transcribe.feedback.translation_failed",
                comment: "Translation failed"
            )
            lastActionTone = .destructive
        }
    }

    private func updateJobInMemory(jobID: String, transform: (TranscriptionJobRecord) -> TranscriptionJobRecord) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index] = transform(jobs[index])
    }

    private func bilingualMarkdown(for job: TranscriptionJobRecord, original: String, translated: String) -> String {
        let header = "# \(job.sourceFileName)"
        let originalSection = "## " + L10n.localize(
            "transcribe.export.original_section",
            comment: "Original text section header"
        )
        let translatedSection = "## " + L10n.localize(
            "transcribe.export.translated_section",
            comment: "Translated text section header"
        )
        return "\(header)\n\n\(originalSection)\n\n\(original)\n\n\(translatedSection)\n\n\(translated)\n"
    }

    private static func currentInterfaceLanguageCode() -> String {
        InterfaceLanguageManager.shared.currentLanguage.appleLanguagesValue
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
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
        lastSavedNoteID = note.id
        lastActionMessage = L10n.localize("transcribe.feedback.saved_as_note", comment: "Saved transcription as note")
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
            return L10n.localize("transcribe.status.waiting", comment: "Transcription waiting")
        case .running:
            return L10n.localize("transcribe.status.running", comment: "Transcription running")
        case .completed:
            return L10n.localize("transcribe.status.completed", comment: "Transcription completed")
        case .failed:
            return L10n.localize("transcribe.status.failed", comment: "Transcription failed")
        case .cancelled:
            return L10n.localize("transcribe.status.cancelled", comment: "Transcription cancelled")
        case .partiallyFailed:
            return L10n.localize("transcribe.status.partially_failed", comment: "Transcription partially failed")
        case .interrupted:
            return L10n.localize("transcribe.status.interrupted", comment: "Transcription interrupted")
        case nil:
            return job.status
        }
    }

    func primaryActionTitle(for job: TranscriptionJobRecord) -> String {
        job.status == TranscriptionJobStatus.queued.rawValue
            ? L10n.localize("transcribe.action.start", comment: "Start transcription task")
            : L10n.localize("transcribe.action.retry", comment: "Retry transcription task")
    }

    func copyResult(jobID: String) throws {
        guard let text = job(id: jobID)?.finalText, !text.isEmpty else {
            throw FileTranscriptionError.resultUnavailable
        }
        clipboardWriter.copy(text)
        lastError = nil
        lastActionMessage = L10n.localize("transcribe.feedback.copied", comment: "Copied transcription result")
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

/// 段级状态聚合器：在 pipeline 运行过程中累计段统计，用于决定 job 最终状态。
final class PipelineSegmentAggregation: @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()

    var totalCount: Int { lock.withLock { state.totalCount } }
    var completedCount: Int { lock.withLock { state.completedCount } }
    var failedCount: Int { lock.withLock { state.failedCount } }
    var providerMode: TranscriptionProviderMode? { lock.withLock { state.providerMode } }

    func record(_ update: PipelineSegmentUpdate) {
        lock.withLock {
            state.totalCount = max(state.totalCount, update.index + 1)
            if state.providerMode == nil {
                state.providerMode = update.providerMode
            }
            switch update.status {
            case .completed:
                state.completedCount += 1
            case .failed:
                state.failedCount += 1
                if !state.failedIndices.contains(update.index) {
                    state.failedIndices.append(update.index)
                }
                if let error = update.error, state.lastError == nil {
                    state.lastError = error
                }
            default:
                break
            }
        }
    }

    func partialFailureSummary() -> String? {
        let indices = lock.withLock { state.failedIndices }
        guard !indices.isEmpty else { return nil }
        let displayIndices = indices.sorted().prefix(5).map { String($0 + 1) }
        return L10n.format(
            "transcribe.diagnostic.failed_segments",
            comment: "Failed segment summary",
            displayIndices.joined(separator: ", ")
        )
    }

    func failureErrorMessage() -> String? {
        let snapshot = lock.withLock { state }
        if snapshot.failedIndices.isEmpty {
            return nil
        }
        return snapshot.lastError ?? L10n.localize(
            "transcribe.error.partial_failure",
            comment: "Some segments failed"
        )
    }

    private struct State {
        var totalCount: Int = 0
        var completedCount: Int = 0
        var failedCount: Int = 0
        var providerMode: TranscriptionProviderMode?
        var failedIndices: [Int] = []
        var lastError: String?
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
        case .translatedTXT: return L10n.localize(
            "transcribe.export.translated_txt",
            comment: "Translated TXT export title"
        )
        case .translatedMarkdown: return L10n.localize(
            "transcribe.export.translated_markdown",
            comment: "Translated Markdown export title"
        )
        case .bilingualMarkdown: return L10n.localize(
            "transcribe.export.bilingual_markdown",
            comment: "Bilingual Markdown export title"
        )
        }
    }
}

enum FileTranscriptionError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case unsupportedAudioContainer(String)
    case unsupportedRecognitionLanguage(String)
    case resultUnavailable
    case invalidAudioBuffer
    case finalResultTimedOut
    case translationUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return L10n.format("transcribe.error.unsupported_format", comment: "Unsupported file format",
                format
            )
        case .unsupportedAudioContainer(let fileName):
            return L10n.format(
                "transcribe.error.unsupported_audio_container",
                comment: "Unsupported or unreadable audio container",
                fileName
            )
        case .unsupportedRecognitionLanguage(let identifier):
            return L10n.format("transcribe.error.unsupported_language", comment: "Unsupported language for transcription",
                identifier
            )
        case .resultUnavailable:
            return L10n.localize("transcribe.error.result_unavailable", comment: "Transcription result unavailable")
        case .invalidAudioBuffer:
            return L10n.localize("transcribe.error.invalid_audio_buffer", comment: "Unable to read audio buffer")
        case .finalResultTimedOut:
            return L10n.localize("transcribe.error.final_timeout", comment: "Final transcription timeout")
        case .translationUnavailable:
            return L10n.localize("transcribe.error.translation_unavailable", comment: "Translation result unavailable")
        }
    }
}

private extension TranscriptionJobRecord {
    func markingInterrupted(updatedAt: Date) -> TranscriptionJobRecord {
        TranscriptionJobRecord(
            id: id,
            sourceFilePath: sourceFilePath,
            sourceFileName: sourceFileName,
            status: TranscriptionJobStatus.interrupted.rawValue,
            progress: 0,
            rawText: rawText,
            finalText: finalText,
            asrProviderID: asrProviderID,
            styleID: styleID,
            errorMessage: L10n.localize("transcribe.error.interrupted", comment: "Transcription interrupted"),
            durationMS: durationMS,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: nil,
            providerMode: providerMode,
            segmentCount: segmentCount,
            segmentCompleted: segmentCompleted,
            partialFailureSummary: partialFailureSummary,
            translatedText: translatedText,
            translationTargetLanguage: translationTargetLanguage,
            translationProvider: translationProvider,
            translationStatus: translationStatus,
            translationError: translationError,
            translationUpdatedAt: translationUpdatedAt
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
            completedAt: nil,
            providerMode: providerMode,
            segmentCount: 0,
            segmentCompleted: 0,
            partialFailureSummary: nil,
            translatedText: translatedText,
            translationTargetLanguage: translationTargetLanguage,
            translationProvider: translationProvider,
            translationStatus: translationStatus,
            translationError: translationError,
            translationUpdatedAt: translationUpdatedAt
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
        updatedAt: Date,
        providerMode: String? = nil,
        segmentCount: Int? = nil,
        segmentCompleted: Int? = nil,
        partialFailureSummary: String? = nil
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
            completedAt: completedAt,
            providerMode: providerMode ?? self.providerMode,
            segmentCount: segmentCount ?? self.segmentCount,
            segmentCompleted: segmentCompleted ?? self.segmentCompleted,
            partialFailureSummary: partialFailureSummary ?? self.partialFailureSummary,
            translatedText: translatedText,
            translationTargetLanguage: translationTargetLanguage,
            translationProvider: translationProvider,
            translationStatus: translationStatus,
            translationError: translationError,
            translationUpdatedAt: translationUpdatedAt
        )
    }
}
