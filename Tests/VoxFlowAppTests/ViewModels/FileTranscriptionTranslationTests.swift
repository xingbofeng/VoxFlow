import XCTest
@testable import VoxFlowApp

@MainActor
final class FileTranscriptionTranslationTests: XCTestCase {
    func testTranslateFullTextPersistsTranslationAndKeepsOriginalTranscript() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let coordinator = StubAppleTranslationCoordinator(result: "你好")
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker(
                result: FileTranscriptionResult(text: "Hello", durationMS: 1_000, segments: [])
            ),
            translationCoordinator: coordinator
        )
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!
        await viewModel.run(jobID: job.id)

        await viewModel.translateFullText(jobID: job.id)

        let saved = try XCTUnwrap(try environment.transcriptionJobRepository.job(id: job.id))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.completed.rawValue)
        XCTAssertEqual(saved.finalText, "Hello")
        XCTAssertEqual(saved.translatedText, "你好")
        XCTAssertEqual(saved.translationStatus, TranslationStatus.completed.rawValue)
        XCTAssertEqual(saved.translationProvider, "appleSystem")
        XCTAssertNotNil(saved.translationTargetLanguage)
    }

    func testTranslateFullTextFailureDoesNotChangeTranscriptionStatus() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let coordinator = StubAppleTranslationCoordinator(error: AppleSystemTranslationError.cancelled)
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker(
                result: FileTranscriptionResult(text: "Hello", durationMS: 1_000, segments: [])
            ),
            translationCoordinator: coordinator
        )
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!
        await viewModel.run(jobID: job.id)

        await viewModel.translateFullText(jobID: job.id)

        let saved = try XCTUnwrap(try environment.transcriptionJobRepository.job(id: job.id))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.completed.rawValue)
        XCTAssertEqual(saved.finalText, "Hello")
        XCTAssertNil(saved.translatedText)
        XCTAssertEqual(saved.translationStatus, TranslationStatus.failed.rawValue)
        XCTAssertNotNil(saved.translationError)
    }

    func testExportTranslatedTXTAndMarkdownRequireTranslation() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker(
                result: FileTranscriptionResult(text: "Hello", durationMS: 1_000, segments: [])
            )
        )
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!
        await viewModel.run(jobID: job.id)

        XCTAssertThrowsError(try viewModel.export(jobID: job.id, format: .translatedTXT)) { error in
            XCTAssertEqual(error as? FileTranscriptionError, .translationUnavailable)
        }
        XCTAssertThrowsError(try viewModel.export(jobID: job.id, format: .translatedMarkdown)) { error in
            XCTAssertEqual(error as? FileTranscriptionError, .translationUnavailable)
        }
        XCTAssertThrowsError(try viewModel.export(jobID: job.id, format: .bilingualMarkdown)) { error in
            XCTAssertEqual(error as? FileTranscriptionError, .translationUnavailable)
        }
    }

    func testExportBilingualMarkdownContainsBothOriginalAndTranslated() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let coordinator = StubAppleTranslationCoordinator(result: "你好")
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker(
                result: FileTranscriptionResult(text: "Hello", durationMS: 1_000, segments: [])
            ),
            translationCoordinator: coordinator
        )
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!
        await viewModel.run(jobID: job.id)
        await viewModel.translateFullText(jobID: job.id)

        let bilingual = try viewModel.export(jobID: job.id, format: .bilingualMarkdown)
        XCTAssertTrue(bilingual.contains("Hello"))
        XCTAssertTrue(bilingual.contains("你好"))

        let translatedTXT = try viewModel.export(jobID: job.id, format: .translatedTXT)
        XCTAssertEqual(translatedTXT, "你好")
    }

    func testSaveAsNoteCreatesNoteWithFileTranscriptionSource() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = FileTranscriptionViewModel(
            environment: environment,
            worker: StubFileTranscriptionWorker(
                result: FileTranscriptionResult(text: "转写文本", durationMS: 1_000, segments: [])
            )
        )
        let job = try viewModel.enqueueFiles([URL(fileURLWithPath: "/tmp/audio.wav")]).first!
        await viewModel.run(jobID: job.id)

        let note = try viewModel.saveAsNote(jobID: job.id)
        XCTAssertEqual(note.sourceType, "fileTranscription")
        XCTAssertEqual(note.sourceID, job.id)
        XCTAssertTrue(note.bodyMarkdown.contains("转写文本"))
    }
}

// MARK: - Stubs

private final class StubAppleTranslationCoordinator: AppleTranslationCoordinating, @unchecked Sendable {
    let isAvailable: Bool = true
    private let result: String?
    private let error: Error?

    init(result: String? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func translate(_ text: String) async throws -> String {
        if let error {
            throw error
        }
        return result ?? ""
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
