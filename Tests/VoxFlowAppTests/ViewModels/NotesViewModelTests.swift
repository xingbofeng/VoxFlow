import XCTest
@testable import VoxFlowApp

@MainActor
final class NotesViewModelTests: XCTestCase {
    func testCreateUpdateDeleteAndSearchNotes() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = NotesViewModel(environment: environment)

        let note = try viewModel.createNote(
            title: "会议纪要",
            bodyMarkdown: "今天讨论 VoiceInput",
            tags: ["meeting", "work"]
        )
        try viewModel.updateNote(
            id: note.id,
            title: "会议纪要 updated",
            bodyMarkdown: "更新后的 Markdown",
            tags: ["work"]
        )
        viewModel.search("updated")

        XCTAssertEqual(viewModel.notes.map(\.title), ["会议纪要 updated"])
        XCTAssertEqual(viewModel.notes.first?.tags, ["work"])

        try viewModel.deleteNote(id: note.id)
        XCTAssertEqual(viewModel.notes, [])
    }

    func testSaveFromHistoryAndFileTranscription() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = environment.clock.now
        try environment.historyRepository.save(
            DictationHistoryEntry(
                id: "history",
                rawText: "raw",
                finalText: "历史文本",
                language: "zh-CN",
                asrProviderID: nil,
                llmProviderID: nil,
                styleID: nil,
                durationMS: 100,
                charCount: 4,
                cpm: 100,
                targetAppBundleID: nil,
                targetAppName: "Notes",
                processingWarningsJSON: nil,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        try environment.transcriptionJobRepository.save(
            TranscriptionJobRecord(
                id: "job",
                sourceFilePath: "/tmp/audio.m4a",
                sourceFileName: "audio.m4a",
                status: TranscriptionJobStatus.completed.rawValue,
                progress: 1,
                rawText: "文件 raw",
                finalText: "文件文本",
                asrProviderID: nil,
                styleID: nil,
                errorMessage: nil,
                durationMS: 1_000,
                createdAt: now,
                updatedAt: now,
                completedAt: now
            )
        )
        let viewModel = NotesViewModel(environment: environment)

        let historyNote = try viewModel.saveFromHistoryEntry(id: "history")
        let fileNote = try viewModel.saveFromTranscriptionJob(id: "job")

        XCTAssertEqual(historyNote.sourceType, "history")
        XCTAssertEqual(historyNote.bodyMarkdown, "历史文本")
        XCTAssertEqual(fileNote.sourceType, "fileTranscription")
        XCTAssertTrue(fileNote.bodyMarkdown.contains("文件文本"))
    }

    func testExportMarkdown() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = NotesViewModel(environment: environment)
        let note = try viewModel.createNote(
            title: "Draft",
            bodyMarkdown: "**hello**",
            tags: ["draft"]
        )

        let markdown = try viewModel.exportMarkdown(noteID: note.id)

        XCTAssertEqual(markdown, "# Draft\n\n**hello**")
        XCTAssertEqual(viewModel.lastActionMessage, "已生成 Markdown 导出内容")
    }

    func testOpenNoteLoadsAndPreviewsSavedNote() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = environment.clock.now
        let note = NoteRecord(
            id: "saved-note",
            title: "Saved",
            bodyMarkdown: "Saved body",
            sourceType: "fileTranscription",
            sourceID: "job",
            tags: ["file-transcription"],
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try environment.noteRepository.save(note)
        let viewModel = NotesViewModel(environment: environment)

        viewModel.openNote(id: note.id)

        XCTAssertEqual(viewModel.previewedNote?.id, note.id)
        XCTAssertEqual(viewModel.selectedNoteID, note.id)
        XCTAssertEqual(viewModel.detailMode, .reading)
    }

    func testPreviewNoteDoesNotOverwriteCurrentDraft() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = NotesViewModel(environment: environment)
        let note = try viewModel.createNote(
            title: "已保存笔记",
            bodyMarkdown: "## 标题\n\n**正文**",
            tags: []
        )
        viewModel.newDraft()
        viewModel.draftBodyMarkdown = "正在编辑的草稿"

        viewModel.previewNote(id: note.id)

        XCTAssertEqual(viewModel.previewedNote?.id, note.id)
        XCTAssertEqual(viewModel.previewedNote?.bodyMarkdown, "## 标题\n\n**正文**")
        XCTAssertEqual(viewModel.draftBodyMarkdown, "正在编辑的草稿")
    }

    func testRecordingStreamsTextAndSavesFinalNote() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let recorder = NotesTranscriberStub()
        let outputService = CapturingNotesOutputService()
        let viewModel = NotesViewModel(
            environment: environment,
            transcriber: recorder,
            notesOutputService: outputService
        )

        await viewModel.startRecording()
        recorder.emit(text: "正在记录", isFinal: false)

        XCTAssertEqual(viewModel.recordingState, .recording)
        XCTAssertEqual(viewModel.draftBodyMarkdown, "正在记录")
        XCTAssertEqual(viewModel.characterCount, 4)
        XCTAssertEqual(outputService.deliveredTexts, [])

        viewModel.finishRecording()
        XCTAssertEqual(viewModel.recordingState, .finishing)
        XCTAssertEqual(recorder.finishCallCount, 1)

        recorder.emit(text: "正在记录完成", isFinal: true)

        XCTAssertEqual(outputService.deliveredTexts, ["正在记录完成"])
        XCTAssertEqual(viewModel.recordingState, .idle)
        XCTAssertEqual(viewModel.notes.first?.bodyMarkdown, "正在记录完成")
        XCTAssertEqual(viewModel.selectedNoteID, viewModel.notes.first?.id)
    }

    func testRecordingAgainUpdatesCurrentQuickCaptureNoteInsteadOfCreatingDuplicate() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let recorder = NotesTranscriberStub()
        let outputService = CapturingNotesOutputService()
        let viewModel = NotesViewModel(
            environment: environment,
            transcriber: recorder,
            notesOutputService: outputService
        )

        await viewModel.startRecording()
        recorder.emit(text: "第一次记录", isFinal: true)
        let firstNoteID = try XCTUnwrap(viewModel.selectedNoteID)

        await viewModel.startRecording(replacing: NSRange(location: ("第一次记录" as NSString).length, length: 0))
        recorder.emit(text: " 继续追加", isFinal: true)

        XCTAssertEqual(viewModel.notes.count, 1)
        XCTAssertEqual(viewModel.selectedNoteID, firstNoteID)
        XCTAssertEqual(viewModel.notes.first?.id, firstNoteID)
        XCTAssertEqual(viewModel.notes.first?.bodyMarkdown, "第一次记录 继续追加")
    }

    func testRecordingStateChangesBeforeTranscriberStartCompletes() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let recorder = SlowStartingNotesTranscriberStub()
        let viewModel = NotesViewModel(environment: environment, transcriber: recorder)

        let task = Task {
            await viewModel.startRecording()
        }
        await recorder.waitUntilStartCalled()

        XCTAssertEqual(viewModel.recordingState, .recording)

        recorder.completeStart()
        await task.value
    }

    func testRecordingFinalOutputFailureKeepsDraftAndDoesNotSaveNote() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let recorder = NotesTranscriberStub()
        let outputService = CapturingNotesOutputService(
            result: .injectionFailed(reason: "Notes editor unavailable"),
            appliesText: false
        )
        let viewModel = NotesViewModel(
            environment: environment,
            transcriber: recorder,
            notesOutputService: outputService
        )

        await viewModel.startRecording()
        recorder.emit(text: "最终文本", isFinal: true)

        XCTAssertEqual(outputService.deliveredTexts, ["最终文本"])
        XCTAssertEqual(viewModel.recordingState, .idle)
        XCTAssertEqual(viewModel.draftBodyMarkdown, "最终文本")
        XCTAssertEqual(viewModel.notes, [])
        XCTAssertEqual(viewModel.lastError, "Notes editor unavailable")
    }

    func testRecordingReplacesCurrentEditorSelectionWithoutDiscardingDraft() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let recorder = NotesTranscriberStub()
        let outputService = CapturingNotesOutputService()
        let viewModel = NotesViewModel(
            environment: environment,
            transcriber: recorder,
            notesOutputService: outputService
        )
        viewModel.draftBodyMarkdown = "开头 old text 结尾"
        let selection = (viewModel.draftBodyMarkdown as NSString).range(of: "old text")

        await viewModel.startRecording(replacing: selection)
        recorder.emit(text: "新的内容", isFinal: false)

        XCTAssertEqual(viewModel.draftBodyMarkdown, "开头 新的内容 结尾")

        recorder.emit(text: "新的中英文 content", isFinal: true)

        XCTAssertEqual(outputService.deliveredTexts, ["开头 新的中英文 content 结尾"])
        XCTAssertEqual(viewModel.draftBodyMarkdown, "开头 新的中英文 content 结尾")
        XCTAssertEqual(viewModel.notes.first?.bodyMarkdown, "开头 新的中英文 content 结尾")
    }

    func testRecordingMovesEditorSelectionAfterFinalInsertedText() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let recorder = NotesTranscriberStub()
        let viewModel = NotesViewModel(environment: environment, transcriber: recorder)
        viewModel.draftBodyMarkdown = "开头 old text 结尾"
        let selection = (viewModel.draftBodyMarkdown as NSString).range(of: "old text")

        await viewModel.startRecording(replacing: selection)
        recorder.emit(text: "新的内容", isFinal: false)

        XCTAssertNil(viewModel.editorSelectionRequest)

        recorder.emit(text: "新的中英文 content", isFinal: true)

        XCTAssertEqual(
            viewModel.editorSelectionRequest?.range,
            NSRange(location: selection.location + ("新的中英文 content" as NSString).length, length: 0)
        )
    }

    func testContinuingDictationAppendsFinalTextToCurrentPreviewedNote() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let recorder = NotesTranscriberStub()
        let outputService = CapturingNotesOutputService()
        let now = environment.clock.now
        try environment.noteRepository.save(
            NoteRecord(
                id: "note-1",
                title: "原笔记",
                bodyMarkdown: "已有正文",
                sourceType: "manual",
                sourceID: nil,
                tags: ["work"],
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        let viewModel = NotesViewModel(
            environment: environment,
            transcriber: recorder,
            notesOutputService: outputService
        )
        viewModel.load()
        viewModel.previewNote(id: "note-1")
        viewModel.enterContinuingDictation()

        await viewModel.startRecording()
        recorder.emit(text: "追加内容", isFinal: true)

        let updated = try XCTUnwrap(try environment.noteRepository.note(id: "note-1"))
        XCTAssertEqual(updated.bodyMarkdown, "已有正文\n\n追加内容")
        XCTAssertEqual(updated.title, "原笔记")
        XCTAssertEqual(updated.tags, ["work"])
        XCTAssertEqual(viewModel.previewedNote?.bodyMarkdown, "已有正文\n\n追加内容")
        XCTAssertEqual(viewModel.detailMode, .reading)
        XCTAssertNil(viewModel.continuingNoteID)
        XCTAssertEqual(viewModel.notes.count, 1)
        XCTAssertEqual(outputService.deliveredTexts, ["已有正文\n\n追加内容"])
    }

    func testRecordingClampsInvalidSelectionToEndOfDraft() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let recorder = NotesTranscriberStub()
        let outputService = CapturingNotesOutputService()
        let viewModel = NotesViewModel(
            environment: environment,
            transcriber: recorder,
            notesOutputService: outputService
        )
        viewModel.draftBodyMarkdown = "已有"

        await viewModel.startRecording(replacing: NSRange(location: 999, length: 20))
        recorder.emit(text: "追加", isFinal: false)

        XCTAssertEqual(viewModel.draftBodyMarkdown, "已有追加")
        XCTAssertEqual(outputService.deliveredTexts, [])
    }

    func testRecordingFailureReturnsToIdleAndShowsError() async {
        let environment = try! AppEnvironment(container: DependencyContainer.inMemory())
        let recorder = NotesTranscriberStub()
        recorder.startError = NotesTranscriberStubError.permissionDenied
        let viewModel = NotesViewModel(environment: environment, transcriber: recorder)

        await viewModel.startRecording()

        XCTAssertEqual(viewModel.recordingState, .idle)
        XCTAssertEqual(viewModel.lastError, "没有录音权限")
    }
}

@MainActor
private final class NotesTranscriberStub: NotesTranscribing {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var startError: Error?
    private(set) var finishCallCount = 0

    func start() async throws {
        if let startError {
            throw startError
        }
    }

    func finish() {
        finishCallCount += 1
    }

    func cancel() {}

    func emit(text: String, isFinal: Bool) {
        onTranscription?(text, isFinal)
    }
}

@MainActor
private final class CapturingNotesOutputService: NotesOutputDelivering {
    private let result: OutputResult
    private let appliesText: Bool
    private(set) var deliveredTexts: [String] = []

    init(
        result: OutputResult = .injected,
        appliesText: Bool = true
    ) {
        self.result = result
        self.appliesText = appliesText
    }

    func deliverToInAppTextTarget(
        text: String,
        target: InAppTextOutputTarget
    ) -> OutputResult {
        deliveredTexts.append(text)
        if appliesText {
            target.write(text)
        }
        return result
    }
}

private enum NotesTranscriberStubError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "没有录音权限"
    }
}

@MainActor
private final class SlowStartingNotesTranscriberStub: NotesTranscribing {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    private var startCalled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var startContinuation: CheckedContinuation<Void, Never>?

    func start() async throws {
        startCalled = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func waitUntilStartCalled() async {
        if startCalled { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func completeStart() {
        startContinuation?.resume()
        startContinuation = nil
    }

    func finish() {}
    func cancel() {}
}
