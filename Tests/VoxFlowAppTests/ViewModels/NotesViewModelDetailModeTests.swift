import XCTest
@testable import VoxFlowApp

@MainActor
final class NotesViewModelDetailModeTests: XCTestCase {
    func testPreviewNoteOpensInReadingMode() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date()
        try environment.noteRepository.save(
            NoteRecord(
                id: "note-1",
                title: "历史笔记",
                bodyMarkdown: "正文",
                sourceType: "manual",
                sourceID: nil,
                tags: ["work"],
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        let viewModel = NotesViewModel(environment: environment)
        viewModel.load()

        viewModel.previewNote(id: "note-1")

        XCTAssertEqual(viewModel.detailMode, .reading)
        XCTAssertEqual(viewModel.previewedNote?.id, "note-1")
        XCTAssertEqual(viewModel.selectedNoteID, "note-1")
        // 阅读态不覆盖 draft；进入编辑态时才用 previewedNote 初始化 draft。
        XCTAssertEqual(viewModel.previewedNote?.title, "历史笔记")
        XCTAssertEqual(viewModel.previewedNote?.bodyMarkdown, "正文")
    }

    func testNewDraftEntersEditingMode() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = NotesViewModel(environment: environment)

        viewModel.newDraft()

        XCTAssertEqual(viewModel.detailMode, .editing)
        XCTAssertNil(viewModel.selectedNoteID)
        XCTAssertEqual(viewModel.draftTitle, "")
        XCTAssertEqual(viewModel.draftBodyMarkdown, "")
    }

    func testEnterEditingFromReadingThenCancelRestoresDraft() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date()
        try environment.noteRepository.save(
            NoteRecord(
                id: "note-1",
                title: "原标题",
                bodyMarkdown: "原正文",
                sourceType: "manual",
                sourceID: nil,
                tags: [],
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        let viewModel = NotesViewModel(environment: environment)
        viewModel.load()
        viewModel.previewNote(id: "note-1")

        viewModel.enterEditing()
        XCTAssertEqual(viewModel.detailMode, .editing)

        viewModel.draftTitle = "改坏的标题"
        viewModel.draftBodyMarkdown = "改坏的正文"
        viewModel.cancelEditing()

        XCTAssertEqual(viewModel.detailMode, .reading)
        XCTAssertEqual(viewModel.draftTitle, "原标题")
        XCTAssertEqual(viewModel.draftBodyMarkdown, "原正文")
    }

    func testEnterContinuingDictationSetsContinuingNoteID() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date()
        try environment.noteRepository.save(
            NoteRecord(
                id: "note-1",
                title: "笔记",
                bodyMarkdown: "正文",
                sourceType: "manual",
                sourceID: nil,
                tags: [],
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        let viewModel = NotesViewModel(environment: environment)
        viewModel.load()
        viewModel.previewNote(id: "note-1")

        viewModel.enterContinuingDictation()

        XCTAssertEqual(viewModel.detailMode, .continuingDictation)
        XCTAssertEqual(viewModel.continuingNoteID, "note-1")
    }

    func testExitContinuingDictationReturnsToReading() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date()
        try environment.noteRepository.save(
            NoteRecord(
                id: "note-1",
                title: "笔记",
                bodyMarkdown: "正文",
                sourceType: "manual",
                sourceID: nil,
                tags: [],
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        let viewModel = NotesViewModel(environment: environment)
        viewModel.load()
        viewModel.previewNote(id: "note-1")
        viewModel.enterContinuingDictation()

        viewModel.exitContinuingDictation()

        XCTAssertEqual(viewModel.detailMode, .reading)
        XCTAssertNil(viewModel.continuingNoteID)
    }

    func testSaveDraftReturnsToReadingModeAndUpdatesPreview() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date()
        try environment.noteRepository.save(
            NoteRecord(
                id: "note-1",
                title: "原标题",
                bodyMarkdown: "原正文",
                sourceType: "manual",
                sourceID: nil,
                tags: [],
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        let viewModel = NotesViewModel(environment: environment)
        viewModel.load()
        viewModel.previewNote(id: "note-1")
        viewModel.enterEditing()
        viewModel.draftTitle = "新标题"
        viewModel.draftBodyMarkdown = "新正文"

        try viewModel.saveDraft()

        XCTAssertEqual(viewModel.detailMode, .reading)
        XCTAssertEqual(viewModel.previewedNote?.title, "新标题")
        XCTAssertEqual(viewModel.previewedNote?.bodyMarkdown, "新正文")
    }

    func testSourceLabelDistinguishesFileTranscriptionAndManual() {
        let now = Date()
        let fileNote = NoteRecord(
            id: "file",
            title: "文件笔记",
            bodyMarkdown: "",
            sourceType: "fileTranscription",
            sourceID: "job-1",
            tags: [],
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        let manualNote = NoteRecord(
            id: "manual",
            title: "手动笔记",
            bodyMarkdown: "",
            sourceType: "manual",
            sourceID: nil,
            tags: [],
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )

        let fileLabel = NotesDetailPresentation.sourceLabel(for: fileNote)
        let manualLabel = NotesDetailPresentation.sourceLabel(for: manualNote)
        XCTAssertNotEqual(fileLabel, manualLabel)
        XCTAssertFalse(fileLabel.isEmpty)
        XCTAssertFalse(manualLabel.isEmpty)
    }

    func testDismissPreviewResetsDetailMode() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date()
        try environment.noteRepository.save(
            NoteRecord(
                id: "note-1",
                title: "笔记",
                bodyMarkdown: "正文",
                sourceType: "manual",
                sourceID: nil,
                tags: [],
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        let viewModel = NotesViewModel(environment: environment)
        viewModel.load()
        viewModel.previewNote(id: "note-1")
        viewModel.enterContinuingDictation()

        viewModel.dismissPreview()

        XCTAssertEqual(viewModel.detailMode, .reading)
        XCTAssertNil(viewModel.continuingNoteID)
        XCTAssertNil(viewModel.previewedNote)
    }
}
