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
        TranscriptionJobRecord(
            id: UUID().uuidString,
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
            createdAt: Date(),
            updatedAt: Date(),
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
