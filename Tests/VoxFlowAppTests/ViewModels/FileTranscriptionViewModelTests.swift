import AVFoundation
import XCTest
import VoxFlowAudio
@testable import VoxFlowApp

@MainActor
final class FileTranscriptionViewModelTests: XCTestCase {
    func testASRFileTranscriptionWorkerConfiguresEngineWithExplicitLocale() async throws {
        let fileURL = try makeSilentWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let engine = CapturingFileTranscriptionASREngine(finalText: "done")
        let worker = ASRFileTranscriptionWorker(
            locale: Locale(identifier: "en-US"),
            effectiveEngineType: { .apple },
            makeEngine: { engineType in
                XCTAssertEqual(engineType, .apple)
                return engine
            }
        )

        let result = try await worker.transcribe(fileURL: fileURL, asrProviderID: nil) { _ in }

        XCTAssertEqual(engine.configuredLocaleIdentifiers, ["en-US"])
        XCTAssertEqual(result.text, "done")
    }

    func testASRFileTranscriptionWorkerConfiguresEngineWithJapaneseLocale() async throws {
        let fileURL = try makeSilentWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let engine = CapturingFileTranscriptionASREngine(finalText: "done")
        let worker = ASRFileTranscriptionWorker(
            locale: Locale(identifier: "ja-JP"),
            effectiveEngineType: { .apple },
            makeEngine: { _ in engine }
        )

        let result = try await worker.transcribe(fileURL: fileURL, asrProviderID: nil) { _ in }

        XCTAssertEqual(engine.configuredLocaleIdentifiers, ["ja-JP"])
        XCTAssertEqual(result.text, "done")
        XCTAssertTrue(engine.didStart)
    }

    func testASRFileTranscriptionWorkerUsesRecordedProviderID() async throws {
        let fileURL = try makeSilentWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let engine = CapturingFileTranscriptionASREngine(finalText: "done")
        let worker = ASRFileTranscriptionWorker(
            locale: Locale(identifier: "en-US"),
            effectiveEngineType: { .apple },
            makeEngine: { engineType in
                XCTAssertEqual(engineType, .tencentCloud)
                return engine
            }
        )

        let result = try await worker.transcribe(
            fileURL: fileURL,
            asrProviderID: ASRProviderID.tencentCloudASR
        ) { _ in }

        XCTAssertEqual(result.text, "done")
    }

    func testFinalWaitRespondsToTaskCancellation() async throws {
        let fileURL = try makeSilentWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let engine = NeverFinalFileTranscriptionASREngine()
        let worker = ASRFileTranscriptionWorker(
            locale: Locale(identifier: "en-US"),
            effectiveEngineType: { .apple },
            makeEngine: { _ in engine },
            finalResultTimeoutNanoseconds: 5_000_000_000
        )

        let task = Task<FileTranscriptionResult, Error> {
            try await worker.transcribe(fileURL: fileURL, asrProviderID: String?.none) { _ in }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            let _: FileTranscriptionResult = try await value(task, timeoutNanoseconds: 500_000_000)
            XCTFail("Expected cancellation to fail the transcription")
        } catch is CancellationError {
            XCTAssertTrue(engine.didCancel)
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testFinalWaitTimesOutWhenEngineNeverProducesFinalText() async throws {
        let fileURL = try makeSilentWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let engine = NeverFinalFileTranscriptionASREngine()
        let worker = ASRFileTranscriptionWorker(
            locale: Locale(identifier: "en-US"),
            effectiveEngineType: { .apple },
            makeEngine: { _ in engine },
            finalResultTimeoutNanoseconds: 50_000_000
        )

        do {
            _ = try await worker.transcribe(fileURL: fileURL, asrProviderID: String?.none) { _ in }
            XCTFail("Expected final wait timeout")
        } catch FileTranscriptionError.finalResultTimedOut {
            XCTAssertTrue(engine.didCancel)
        } catch {
            XCTFail("Expected finalResultTimedOut, got \(error)")
        }
    }

    func testRejectsUnsupportedFormat() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker()
        )
        let file = URL(fileURLWithPath: "/tmp/readme.txt")

        XCTAssertThrowsError(try viewModel.enqueueFiles([file]))
        XCTAssertEqual(viewModel.jobs, [])
    }

    func testEnqueueStoresCurrentASRProviderID() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker(),
            currentASRProviderID: { ASRProviderID.tencentCloudASR }
        )

        let job = try XCTUnwrap(try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first)

        XCTAssertEqual(job.asrProviderID, ASRProviderID.tencentCloudASR)
        XCTAssertEqual(
            try environment.transcriptionJobRepository.job(id: job.id)?.asrProviderID,
            ASRProviderID.tencentCloudASR
        )
    }

    func testQueueRunsJobAndPersistsProgress() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let worker = StubFileTranscriptionWorker(
            result: FileTranscriptionResult(
                text: "转写完成",
                durationMS: 2_000,
                segments: [TranscriptionSegment(startMS: 0, endMS: 2_000, text: "转写完成")]
            )
        )
        let viewModel = FileTranscriptionViewModel(environment: environment, worker: worker)
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.m4a")]).first!

        await viewModel.run(jobID: job.id)

        let saved = try XCTUnwrap(try environment.transcriptionJobRepository.job(id: job.id))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.completed.rawValue)
        XCTAssertEqual(saved.progress, 1)
        XCTAssertEqual(saved.finalText, "转写完成")
        XCTAssertEqual(viewModel.jobs.first?.status, TranscriptionJobStatus.completed.rawValue)
        XCTAssertEqual(viewModel.statusTitle(for: saved), "已完成")
    }

    func testCancelAndRetryFailedJob() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let worker = StubFileTranscriptionWorker(error: CancellationError())
        let viewModel = FileTranscriptionViewModel(environment: environment, worker: worker)
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!

        await viewModel.run(jobID: job.id)
        XCTAssertEqual(viewModel.jobs.first?.status, TranscriptionJobStatus.cancelled.rawValue)

        viewModel.worker = StubFileTranscriptionWorker(
            result: FileTranscriptionResult(text: "retry ok", durationMS: 1_000, segments: [])
        )
        await viewModel.retry(jobID: job.id)

        XCTAssertEqual(viewModel.jobs.first?.status, TranscriptionJobStatus.completed.rawValue)
        XCTAssertEqual(viewModel.jobs.first?.finalText, "retry ok")
    }

    func testRetryFailureDoesNotShowPreviousResult() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker(
                result: FileTranscriptionResult(
                    text: "old result",
                    durationMS: 3_000,
                    segments: []
                )
            )
        )
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!
        await viewModel.run(jobID: job.id)
        XCTAssertEqual(viewModel.jobs.first?.finalText, "old result")

        viewModel.worker = StubFileTranscriptionWorker(error: FileTranscriptionTestError.retryFailed)
        await viewModel.retry(jobID: job.id)

        let saved = try XCTUnwrap(try environment.transcriptionJobRepository.job(id: job.id))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.failed.rawValue)
        XCTAssertNil(saved.rawText)
        XCTAssertNil(saved.finalText)
        XCTAssertEqual(saved.durationMS, 0)
        XCTAssertNil(saved.completedAt)
        XCTAssertNil(viewModel.jobs.first?.finalText)
        XCTAssertThrowsError(try viewModel.copyResult(jobID: job.id))
    }

    func testInitializesWithPersistedJobsAndRecoversRunningJobsAsFailed() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let queued = makeJob(id: "queued", status: .queued, createdAt: now.addingTimeInterval(-30))
        let failed = makeJob(id: "failed", status: .failed, createdAt: now.addingTimeInterval(-20))
        let completed = makeJob(id: "completed", status: .completed, createdAt: now.addingTimeInterval(-10))
        let running = makeJob(id: "running", status: .running, createdAt: now)
        try [queued, failed, completed, running].forEach {
            try environment.transcriptionJobRepository.save($0)
        }

        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker()
        )

        XCTAssertEqual(Set(viewModel.jobs.map(\.id)), ["queued", "failed", "completed", "running"])
        let restoredRunning = try XCTUnwrap(viewModel.jobs.first { $0.id == "running" })
        XCTAssertEqual(restoredRunning.status, TranscriptionJobStatus.failed.rawValue)
        XCTAssertEqual(restoredRunning.progress, 0)
        XCTAssertEqual(restoredRunning.errorMessage, "上次转写被中断，请重试。")
        XCTAssertEqual(
            try environment.transcriptionJobRepository.job(id: "running")?.status,
            TranscriptionJobStatus.failed.rawValue
        )
    }

    func testCancelledRunCannotOverwriteJobAsCompleted() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let worker = ControllableFileTranscriptionWorker(
            result: FileTranscriptionResult(
                text: "late final",
                durationMS: 1_000,
                segments: []
            )
        )
        let viewModel = FileTranscriptionViewModel(environment: environment, worker: worker)
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!

        viewModel.start(jobID: job.id)
        await worker.waitUntilStarted()
        viewModel.cancel(jobID: job.id)
        worker.finish()
        try await Task.sleep(nanoseconds: 50_000_000)

        let saved = try XCTUnwrap(try environment.transcriptionJobRepository.job(id: job.id))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.cancelled.rawValue)
        XCTAssertNil(saved.rawText)
        XCTAssertNil(saved.finalText)
        XCTAssertNil(viewModel.jobs.first?.finalText)
    }

    func testRetryCanBeCancelled() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker(error: FileTranscriptionTestError.retryFailed)
        )
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!
        await viewModel.run(jobID: job.id)
        XCTAssertEqual(viewModel.jobs.first?.status, TranscriptionJobStatus.failed.rawValue)

        let retryWorker = ControllableFileTranscriptionWorker(
            result: FileTranscriptionResult(text: "late retry", durationMS: 1_000, segments: [])
        )
        viewModel.worker = retryWorker
        let retryTask = Task {
            await viewModel.retry(jobID: job.id)
        }
        await retryWorker.waitUntilStarted()
        viewModel.cancel(jobID: job.id)
        retryWorker.finish()
        await retryTask.value

        let saved = try XCTUnwrap(try environment.transcriptionJobRepository.job(id: job.id))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.cancelled.rawValue)
        XCTAssertNil(saved.finalText)
    }

    func testCancelledRunProgressCannotOverwriteRetryProgress() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let firstWorker = ManualProgressFileTranscriptionWorker(
            result: FileTranscriptionResult(text: "old", durationMS: 1_000, segments: [])
        )
        let secondWorker = ManualProgressFileTranscriptionWorker(
            result: FileTranscriptionResult(text: "new", durationMS: 1_000, segments: [])
        )
        let viewModel = FileTranscriptionViewModel(environment: environment, worker: firstWorker)
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!

        viewModel.start(jobID: job.id)
        await firstWorker.waitUntilStarted()
        viewModel.cancel(jobID: job.id)

        viewModel.worker = secondWorker
        let retryTask = Task {
            await viewModel.retry(jobID: job.id)
        }
        await secondWorker.waitUntilStarted()

        firstWorker.emitProgress(0.7)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.jobs.first?.status, TranscriptionJobStatus.running.rawValue)
        XCTAssertEqual(viewModel.jobs.first?.progress, 0)

        secondWorker.finish()
        await retryTask.value
        firstWorker.finish()
    }

    func testExportsTxtMarkdownSRTAndSavesNote() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let worker = StubFileTranscriptionWorker(
            result: FileTranscriptionResult(
                text: "第一句\n第二句",
                durationMS: 3_000,
                segments: [
                    TranscriptionSegment(startMS: 0, endMS: 1_500, text: "第一句"),
                    TranscriptionSegment(startMS: 1_500, endMS: 3_000, text: "第二句"),
                ]
            )
        )
        let viewModel = FileTranscriptionViewModel(environment: environment, worker: worker)
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/story.mp3")]).first!
        await viewModel.run(jobID: job.id)

        let txt = try viewModel.export(jobID: job.id, format: .txt)
        let md = try viewModel.export(jobID: job.id, format: .markdown)
        let srt = try viewModel.export(jobID: job.id, format: .srt)
        let note = try viewModel.saveAsNote(jobID: job.id)

        XCTAssertEqual(txt, "第一句\n第二句")
        XCTAssertTrue(md.contains("# story.mp3"))
        XCTAssertTrue(srt.contains("00:00:01,500 --> 00:00:03,000"))
        XCTAssertEqual(note.sourceType, "fileTranscription")
        XCTAssertEqual(try environment.noteRepository.list().first?.sourceID, job.id)
        XCTAssertEqual(viewModel.lastActionMessage, "已保存为笔记")
    }

    func testStatusTitlesAreLocalized() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker()
        )

        XCTAssertEqual(viewModel.statusTitle(for: makeJob(status: .queued)), "等待开始")
        XCTAssertEqual(viewModel.statusTitle(for: makeJob(status: .running)), "转写中")
        XCTAssertEqual(viewModel.statusTitle(for: makeJob(status: .completed)), "已完成")
        XCTAssertEqual(viewModel.statusTitle(for: makeJob(status: .failed)), "失败")
        XCTAssertEqual(viewModel.statusTitle(for: makeJob(status: .cancelled)), "已取消")
    }

    func testCompletedJobPrimaryActionIsRetry() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker()
        )

        XCTAssertEqual(viewModel.primaryActionTitle(for: makeJob(status: .queued)), "开始")
        XCTAssertEqual(viewModel.primaryActionTitle(for: makeJob(status: .completed)), "重试")
    }

    func testCopyResultWritesCompletedTextToClipboard() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let clipboard = CapturingFileClipboardWriter()
        let worker = StubFileTranscriptionWorker(
            result: FileTranscriptionResult(text: "直接复制结果", durationMS: 1_000, segments: [])
        )
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: worker,
            clipboardWriter: clipboard
        )
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/copy.m4a")]).first!
        await viewModel.run(jobID: job.id)

        try viewModel.copyResult(jobID: job.id)

        XCTAssertEqual(clipboard.copiedTexts, ["直接复制结果"])
        XCTAssertEqual(viewModel.lastActionMessage, "已复制转写结果")
        XCTAssertEqual(viewModel.lastActionTone, .success)
    }

    private func makeJob(status: TranscriptionJobStatus) -> TranscriptionJobRecord {
        makeJob(id: UUID().uuidString, status: status, createdAt: Date())
    }

    private func makeJob(
        id: String,
        status: TranscriptionJobStatus,
        createdAt: Date
    ) -> TranscriptionJobRecord {
        TranscriptionJobRecord(
            id: id,
            sourceFilePath: "/tmp/audio.m4a",
            sourceFileName: "audio.m4a",
            status: status.rawValue,
            progress: 0,
            rawText: nil,
            finalText: status == .completed ? "完成" : nil,
            asrProviderID: nil,
            styleID: nil,
            errorMessage: nil,
            durationMS: 0,
            createdAt: createdAt,
            updatedAt: createdAt,
            completedAt: nil
        )
    }

    private func makeSilentWAVFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowFileTranscription-\(UUID().uuidString).wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        try file.write(from: buffer)
        return url
    }

    private func value<T>(
        _ task: Task<T, Error>,
        timeoutNanoseconds: UInt64
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await task.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw FileTranscriptionTestError.timedOutWaitingForTask
            }
            guard let result = try await group.next() else {
                throw FileTranscriptionTestError.timedOutWaitingForTask
            }
            group.cancelAll()
            return result
        }
    }
}

private final class CapturingFileTranscriptionASREngine: ASREngine {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    let isAvailable = true
    private let finalText: String
    private(set) var configuredLocaleIdentifiers: [String] = []
    private(set) var didStart = false

    init(finalText: String) {
        self.finalText = finalText
    }

    func configure(locale: Locale) {
        configuredLocaleIdentifiers.append(locale.identifier)
    }

    func start() throws {
        didStart = true
    }
    func appendAudioFrame(_ frame: AudioFrame) {}
    func endAudio() {
        onTranscription?(finalText, true)
    }
    func stop() {}
    func cancel() {}
}

private final class NeverFinalFileTranscriptionASREngine: ASREngine {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    let isAvailable = true
    private(set) var didStart = false
    private(set) var didCancel = false

    func configure(locale: Locale) {}
    func start() throws {
        didStart = true
    }
    func appendAudioFrame(_ frame: AudioFrame) {}
    func endAudio() {}
    func stop() {}
    func cancel() {
        didCancel = true
    }
}

private final class CapturingFileClipboardWriter: ClipboardWriting {
    private(set) var copiedTexts: [String] = []

    func copy(_ text: String) {
        copiedTexts.append(text)
    }
}

private struct StubFileTranscriptionWorker: FileTranscriptionWorking {
    var result = FileTranscriptionResult(text: "", durationMS: 0, segments: [])
    var error: Error?

    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> FileTranscriptionResult {
        progress(0.5)
        if let error {
            throw error
        }
        progress(1)
        return result
    }
}

private final class ControllableFileTranscriptionWorker: FileTranscriptionWorking, @unchecked Sendable {
    private let result: FileTranscriptionResult
    private let lock = NSLock()
    private var started = false
    private var released = false
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(result: FileTranscriptionResult) {
        self.result = result
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if started {
                lock.unlock()
                continuation.resume()
                return
            }
            startedContinuations.append(continuation)
            lock.unlock()
        }
    }

    func finish() {
        lock.lock()
        released = true
        let continuation = releaseContinuation
        releaseContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> FileTranscriptionResult {
        progress(0.5)
        signalStarted()
        await waitForFinish()
        progress(1)
        return result
    }

    private func signalStarted() {
        lock.lock()
        started = true
        let continuations = startedContinuations
        startedContinuations.removeAll()
        lock.unlock()
        continuations.forEach { $0.resume() }
    }

    private func waitForFinish() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
                return
            }
            releaseContinuation = continuation
            lock.unlock()
        }
    }
}

private final class ManualProgressFileTranscriptionWorker: FileTranscriptionWorking, @unchecked Sendable {
    private let result: FileTranscriptionResult
    private let lock = NSLock()
    private var started = false
    private var released = false
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(result: FileTranscriptionResult) {
        self.result = result
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if started {
                lock.unlock()
                continuation.resume()
                return
            }
            startedContinuations.append(continuation)
            lock.unlock()
        }
    }

    func emitProgress(_ progress: Double) {
        lock.lock()
        let handler = progressHandler
        lock.unlock()
        handler?(progress)
    }

    func finish() {
        lock.lock()
        released = true
        let continuation = releaseContinuation
        releaseContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> FileTranscriptionResult {
        lock.withLock {
            progressHandler = progress
        }
        signalStarted()
        await waitForFinish()
        return result
    }

    private func signalStarted() {
        lock.lock()
        started = true
        let continuations = startedContinuations
        startedContinuations.removeAll()
        lock.unlock()
        continuations.forEach { $0.resume() }
    }

    private func waitForFinish() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
                return
            }
            releaseContinuation = continuation
            lock.unlock()
        }
    }
}

private enum FileTranscriptionTestError: LocalizedError {
    case retryFailed
    case timedOutWaitingForTask

    var errorDescription: String? {
        switch self {
        case .retryFailed:
            return "retry failed"
        case .timedOutWaitingForTask:
            return "timed out waiting for task"
        }
    }
}
