import AVFoundation
import XCTest
@testable import VoxFlowApp

@MainActor
final class FileTranscriptionPipelineViewModelTests: XCTestCase {
    // MARK: - VoxFlowFileTranscriptionPipeline

    func testPipelineSplitsLongAudioIntoMultipleWindows() async throws {
        let fileURL = try makeWAVFile(durationMS: 65_000)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let worker = SegmentAwareStubWorker(perSegmentText: { index in "段\(index + 1)" })
        let pipeline = VoxFlowFileTranscriptionPipeline(
            makeSegmentWorker: { _ in worker }
        )

        let updates = SegmentUpdateCollector()
        let result = try await pipeline.transcribe(
            fileURL: fileURL,
            asrProviderID: ASRProviderID.funASR,
            locale: Locale(identifier: "zh-Hans"),
            existingSegments: [],
            onSegment: { updates.append($0) },
            progress: { _, _, _ in }
        )

        // 65s 音频按 30s 窗口 + 1.5s overlap 切分应得到 3 段（0-30, 28.5-58.5, 57-65）。
        XCTAssertEqual(worker.callCount, 3)
        XCTAssertTrue(result.text.contains("段1"))
        XCTAssertTrue(result.text.contains("段2"))
        XCTAssertTrue(result.text.contains("段3"))
        let completed = updates.updates.filter { $0.status == .completed }
        XCTAssertEqual(completed.count, 3)
    }

    func testPipelineNativeFileTriesNativeThenFallsBackToSegmented() async throws {
        let fileURL = try makeWAVFile(durationMS: 5_000)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let nativeTranscriber = FailingNativeFileTranscriber()
        let segmentWorker = SegmentAwareStubWorker(perSegmentText: { _ in "分段结果" })
        let pipeline = VoxFlowFileTranscriptionPipeline(
            makeSegmentWorker: { _ in segmentWorker },
            nativeFileTranscriber: nativeTranscriber
        )

        let result = try await pipeline.transcribe(
            fileURL: fileURL,
            asrProviderID: ASRProviderID.groqWhisper,
            locale: Locale(identifier: "en-US"),
            existingSegments: [],
            onSegment: { _ in },
            progress: { _, _, _ in }
        )

        XCTAssertTrue(nativeTranscriber.called)
        XCTAssertEqual(result.text, "分段结果")
    }

    func testPipelineRetriesEmptyResultSegmentsThenMarksFailed() async throws {
        let fileURL = try makeWAVFile(durationMS: 35_000)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let worker = SegmentAwareStubWorker(perSegmentText: { _ in "" })
        let pipeline = VoxFlowFileTranscriptionPipeline(
            makeSegmentWorker: { _ in worker },
            maxRetryCount: 1
        )

        let updates = SegmentUpdateCollector()
        do {
            _ = try await pipeline.transcribe(
                fileURL: fileURL,
                asrProviderID: ASRProviderID.funASR,
                locale: Locale(identifier: "zh-Hans"),
                existingSegments: [],
                onSegment: { updates.append($0) },
                progress: { _, _, _ in }
            )
            XCTFail("Expected pipeline to throw when all segments fail")
        } catch {
            // expected: 所有段失败时抛出 resultUnavailable
        }

        let failed = updates.updates.filter { $0.status == .failed }
        XCTAssertFalse(failed.isEmpty)
        XCTAssertEqual(failed.first?.fallbackReason, .emptyResult)
    }

    func testPipelineResumeSkipsCompletedSegments() async throws {
        let fileURL = try makeWAVFile(durationMS: 65_000)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let worker = SegmentAwareStubWorker(perSegmentText: { index in "新段\(index + 1)" })
        let pipeline = VoxFlowFileTranscriptionPipeline(
            makeSegmentWorker: { _ in worker }
        )

        let now = Date()
        let existingSegments = [
            TranscriptionSegmentRecord(
                id: "job-1-seg-0",
                jobID: "job-1",
                index: 0,
                startMS: 0,
                endMS: 30_000,
                status: TranscriptionSegmentStatus.completed.rawValue,
                rawText: "已段1",
                finalText: "已段1",
                promptContext: nil,
                fallbackReason: nil,
                retryCount: 0,
                providerID: nil,
                providerMode: nil,
                errorMessage: nil,
                durationMS: 30_000,
                createdAt: now,
                updatedAt: now,
                completedAt: now
            )
        ]

        let updates = SegmentUpdateCollector()
        let result = try await pipeline.transcribe(
            fileURL: fileURL,
            asrProviderID: ASRProviderID.funASR,
            locale: Locale(identifier: "zh-Hans"),
            existingSegments: existingSegments,
            onSegment: { updates.append($0) },
            progress: { _, _, _ in }
        )

        // 第一段直接复用，不应调用 worker。
        XCTAssertEqual(worker.callCount, 2)
        XCTAssertTrue(result.text.contains("已段1"))
        XCTAssertTrue(result.text.contains("新段2"))
        let completed = updates.updates.filter { $0.status == .completed }
        XCTAssertEqual(completed.count, 3)
    }

    func testPipelinePassesPreviousSegmentTextAsPromptContext() async throws {
        let fileURL = try makeWAVFile(durationMS: 65_000)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let worker = SegmentAwareStubWorker(perSegmentText: { index in "段\(index + 1)" })
        let pipeline = VoxFlowFileTranscriptionPipeline(
            makeSegmentWorker: { _ in worker }
        )

        _ = try await pipeline.transcribe(
            fileURL: fileURL,
            asrProviderID: ASRProviderID.funASR,
            locale: Locale(identifier: "zh-Hans"),
            existingSegments: [],
            onSegment: { _ in },
            progress: { _, _, _ in }
        )

        XCTAssertNil(worker.capturedPrompts.first ?? nil)
        XCTAssertTrue(worker.capturedPrompts.dropFirst().contains { prompt in
            prompt?.contains("段1") == true
        })
    }

    // MARK: - ViewModel with pipeline + segments

    func testViewModelPersistsSegmentsAndPartiallyFailedStatus() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let fileURL = try makeWAVFile(durationMS: 65_000)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // 第一段成功，第二段失败（空结果），第三段成功。
        let worker = SegmentAwareStubWorker(perSegmentText: { index in
            index == 1 ? "" : "段\(index + 1)"
        })
        let pipeline = VoxFlowFileTranscriptionPipeline(
            makeSegmentWorker: { _ in worker },
            maxRetryCount: 0
        )
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            pipeline: pipeline
        )
        let job = try viewModel.enqueueFiles([fileURL]).first!

        await viewModel.run(jobID: job.id)

        let saved = try XCTUnwrap(try environment.transcriptionJobRepository.job(id: job.id))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.partiallyFailed.rawValue)
        XCTAssertGreaterThan(saved.segmentCount, 0)
        XCTAssertGreaterThan(saved.segmentCompleted, 0)
        XCTAssertNotNil(saved.partialFailureSummary)

        let segments = try environment.transcriptionSegmentRepository.segments(forJob: job.id)
        XCTAssertFalse(segments.isEmpty)
        let failedSegments = segments.filter {
            $0.status == TranscriptionSegmentStatus.failed.rawValue
        }
        XCTAssertFalse(failedSegments.isEmpty)
    }

    func testViewModelDeleteRemovesJobAndAllSegments() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let fileURL = try makeWAVFile(durationMS: 35_000)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let worker = SegmentAwareStubWorker(perSegmentText: { index in "段\(index + 1)" })
        let pipeline = VoxFlowFileTranscriptionPipeline(makeSegmentWorker: { _ in worker })
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            pipeline: pipeline
        )
        let job = try viewModel.enqueueFiles([fileURL]).first!
        await viewModel.run(jobID: job.id)

        let segmentsBefore = try environment.transcriptionSegmentRepository.segments(forJob: job.id)
        XCTAssertFalse(segmentsBefore.isEmpty)

        viewModel.delete(jobID: job.id)

        XCTAssertNil(try environment.transcriptionJobRepository.job(id: job.id))
        XCTAssertTrue(try environment.transcriptionSegmentRepository.segments(forJob: job.id).isEmpty)
    }

    func testViewModelLoadMarksRunningJobInterruptedAndMarksRunningSegmentsInterrupted() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date()
        let job = TranscriptionJobRecord(
            id: "running-job",
            sourceFilePath: "/tmp/audio.m4a",
            sourceFileName: "audio.m4a",
            status: TranscriptionJobStatus.running.rawValue,
            progress: 0.3,
            rawText: nil,
            finalText: nil,
            asrProviderID: nil,
            styleID: nil,
            errorMessage: nil,
            durationMS: 0,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
        try environment.transcriptionJobRepository.save(job)
        try environment.transcriptionSegmentRepository.save(
            TranscriptionSegmentRecord(
                id: "running-job-seg-0",
                jobID: "running-job",
                index: 0,
                startMS: 0,
                endMS: 30_000,
                status: TranscriptionSegmentStatus.running.rawValue,
                createdAt: now,
                updatedAt: now
            )
        )

        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker()
        )

        let restoredJob = try XCTUnwrap(viewModel.jobs.first { $0.id == "running-job" })
        XCTAssertEqual(restoredJob.status, TranscriptionJobStatus.interrupted.rawValue)
        let segments = try environment.transcriptionSegmentRepository.segments(forJob: "running-job")
        XCTAssertEqual(segments.first?.status, TranscriptionSegmentStatus.interrupted.rawValue)
    }

    // MARK: - Helpers

    private func makeWAVFile(durationMS: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowPipeline-\(UUID().uuidString).wav")
        let sampleRate: Double = 16_000
        let totalFrames = AVAudioFrameCount(Double(durationMS) / 1_000 * sampleRate)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let chunkSize: AVAudioFrameCount = 4_096
        var remaining = totalFrames
        while remaining > 0 {
            let frames = min(chunkSize, remaining)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            try file.write(from: buffer)
            remaining -= frames
        }
        return url
    }
}

// MARK: - Test helpers

private final class SegmentAwareStubWorker: PromptAwareFileTranscriptionWorking, @unchecked Sendable {
    private let perSegmentText: (Int) -> String
    private let lock = NSLock()
    private(set) var callCount = 0
    private var prompts: [String?] = []

    init(perSegmentText: @escaping (Int) -> String) {
        self.perSegmentText = perSegmentText
    }

    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> FileTranscriptionResult {
        try await transcribe(fileURL: fileURL, asrProviderID: asrProviderID, prompt: nil, progress: progress)
    }

    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        prompt: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> FileTranscriptionResult {
        let index: Int = lock.withLock {
            prompts.append(prompt)
            let value = callCount
            callCount += 1
            return value
        }
        progress(1)
        let text = perSegmentText(index)
        return FileTranscriptionResult(
            text: text,
            durationMS: 30_000,
            segments: [TranscriptionSegment(startMS: 0, endMS: 30_000, text: text)]
        )
    }

    var capturedPrompts: [String?] {
        lock.withLock { prompts }
    }
}

private final class SegmentUpdateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [PipelineSegmentUpdate] = []

    func append(_ update: PipelineSegmentUpdate) {
        lock.withLock { collected.append(update) }
    }

    var updates: [PipelineSegmentUpdate] {
        lock.withLock { collected }
    }
}

private final class FailingNativeFileTranscriber: NativeFileTranscribing, @unchecked Sendable {
    private(set) var called = false

    func transcribeFile(
        _ fileURL: URL,
        asrProviderID: String,
        locale: Locale,
        prompt: String?
    ) async throws -> FileTranscriptionResult {
        called = true
        throw FileTranscriptionError.finalResultTimedOut
    }
}

private struct StubFileTranscriptionWorker: FileTranscriptionWorking {
    var result = FileTranscriptionResult(text: "", durationMS: 0, segments: [])

    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> FileTranscriptionResult {
        progress(1)
        return result
    }
}
