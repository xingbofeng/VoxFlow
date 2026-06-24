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
