import Combine
import Foundation
import VoxFlowTextInsertion

enum NotesRecordingState: Equatable {
    case idle
    case recording
    case finishing
}

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var notes: [NoteRecord] = []
    @Published var searchQuery = ""
    @Published var selectedNoteID: String?
    @Published var previewedNote: NoteRecord?
    @Published var draftTitle = ""
    @Published var draftBodyMarkdown = ""
    @Published var draftTagsText = ""
    @Published private(set) var lastExport: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var recordingState = NotesRecordingState.idle

    private let environment: any AppServiceProviding
    private let transcriber: NotesTranscribing
    private let notesOutputService: any NotesOutputDelivering
    private var recordingBaseBody = ""
    private var recordingSelection = NSRange(location: 0, length: 0)
    private var hasLoaded = false

    init(
        environment: any AppServiceProviding,
        transcriber: (any NotesTranscribing)? = nil,
        notesOutputService: (any NotesOutputDelivering)? = nil
    ) {
        self.environment = environment
        self.transcriber = transcriber ?? NotesRecordingService()
        let textOutputConfiguration = SettingsBackedTextOutputConfiguration(
            settingsRepository: environment.settingsRepository
        )
        self.notesOutputService = notesOutputService ?? DefaultOutputService(
            textInsertionCoordinator: TextInsertionCoordinator(
                fastPasteInserter: FastPasteTextInserter(
                    shouldRestoreClipboard: textOutputConfiguration.shouldRestoreClipboard
                ),
                simulatedTypingInserter: SimulatedTypingInserter()
            ),
            clipboardService: SystemClipboardService(),
            textInputMode: textOutputConfiguration.textInputMode
        )
        configureTranscriber()
        load()
    }

    var characterCount: Int {
        draftBodyMarkdown.count
    }

    func startRecording(replacing selection: NSRange? = nil) async {
        guard recordingState == .idle else { return }
        lastActionMessage = nil
        recordingBaseBody = draftBodyMarkdown
        recordingSelection = Self.clampedSelection(
            selection ?? NSRange(
                location: (draftBodyMarkdown as NSString).length,
                length: 0
            ),
            in: draftBodyMarkdown
        )
        do {
            try await transcriber.start()
            recordingState = .recording
        } catch {
            recordingState = .idle
            report(error: error)
        }
    }

    func finishRecording() {
        guard recordingState == .recording else { return }
        recordingState = .finishing
        transcriber.finish()
    }

    func cancelRecording() {
        transcriber.cancel()
        recordingState = .idle
    }

    func load() {
        do {
            notes = try environment.noteRepository.list()
            hasLoaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }
        load()
    }

    func search(_ query: String) {
        searchQuery = query
        do {
            notes = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? try environment.noteRepository.list()
                : try environment.noteRepository.search(query)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func createNote(
        title: String,
        bodyMarkdown: String,
        tags: [String]
    ) throws -> NoteRecord {
        let now = environment.clock.now
        let note = NoteRecord(
            id: UUID().uuidString,
            title: normalizedTitle(title),
            bodyMarkdown: bodyMarkdown,
            sourceType: "manual",
            sourceID: nil,
            tags: normalizedTags(tags),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try environment.noteRepository.save(note)
        selectedNoteID = note.id
        search(searchQuery)
        lastError = nil
        lastActionMessage = "已创建笔记"
        return note
    }

    func updateNote(
        id: String,
        title: String,
        bodyMarkdown: String,
        tags: [String]
    ) throws {
        guard let existing = try environment.noteRepository.note(id: id) else {
            throw NotesViewModelError.noteNotFound
        }
        let note = NoteRecord(
            id: existing.id,
            title: normalizedTitle(title),
            bodyMarkdown: bodyMarkdown,
            sourceType: existing.sourceType,
            sourceID: existing.sourceID,
            tags: normalizedTags(tags),
            createdAt: existing.createdAt,
            updatedAt: environment.clock.now,
            deletedAt: existing.deletedAt
        )
        try environment.noteRepository.save(note)
        search(searchQuery)
        lastError = nil
        lastActionMessage = "已保存笔记"
    }

    func deleteNote(id: String) throws {
        try environment.noteRepository.softDelete(id: id, deletedAt: environment.clock.now)
        if previewedNote?.id == id {
            previewedNote = nil
        }
        if selectedNoteID == id {
            selectedNoteID = nil
            draftTitle = ""
            draftBodyMarkdown = ""
            draftTagsText = ""
        }
        search(searchQuery)
        lastError = nil
        lastActionMessage = "已删除笔记"
    }

    func selectNote(id: String) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        selectedNoteID = note.id
        draftTitle = note.title
        draftBodyMarkdown = note.bodyMarkdown
        draftTagsText = note.tags.joined(separator: ", ")
    }

    func previewNote(id: String) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        previewedNote = note
    }

    func dismissPreview() {
        previewedNote = nil
    }

    func saveDraft() throws {
        let tags = parseTags(draftTagsText)
        if let selectedNoteID {
            try updateNote(
                id: selectedNoteID,
                title: draftTitle,
                bodyMarkdown: draftBodyMarkdown,
                tags: tags
            )
        } else {
            _ = try createNote(
                title: draftTitle,
                bodyMarkdown: draftBodyMarkdown,
                tags: tags
            )
        }
    }

    func newDraft() {
        selectedNoteID = nil
        draftTitle = ""
        draftBodyMarkdown = ""
        draftTagsText = ""
        lastError = nil
        lastActionMessage = "已新建空白草稿"
    }

    @discardableResult
    func saveFromHistoryEntry(id: String) throws -> NoteRecord {
        guard let entry = try environment.historyRepository.entry(id: id) else {
            throw NotesViewModelError.sourceNotFound
        }
        let now = environment.clock.now
        let title = entry.targetAppName.map { "\($0) 听写" } ?? "听写记录"
        let note = NoteRecord(
            id: UUID().uuidString,
            title: title,
            bodyMarkdown: entry.finalText,
            sourceType: "history",
            sourceID: entry.id,
            tags: ["history"],
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try environment.noteRepository.save(note)
        search(searchQuery)
        lastError = nil
        lastActionMessage = "已从历史保存笔记"
        return note
    }

    @discardableResult
    func saveFromTranscriptionJob(id: String) throws -> NoteRecord {
        guard let job = try environment.transcriptionJobRepository.job(id: id),
              let finalText = job.finalText else {
            throw NotesViewModelError.sourceNotFound
        }
        let now = environment.clock.now
        let note = NoteRecord(
            id: UUID().uuidString,
            title: job.sourceFileName,
            bodyMarkdown: "# \(job.sourceFileName)\n\n\(finalText)",
            sourceType: "fileTranscription",
            sourceID: job.id,
            tags: ["file-transcription"],
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try environment.noteRepository.save(note)
        search(searchQuery)
        lastError = nil
        lastActionMessage = "已从转写保存笔记"
        return note
    }

    func exportMarkdown(noteID: String) throws -> String {
        guard let note = try environment.noteRepository.note(id: noteID) else {
            throw NotesViewModelError.noteNotFound
        }
        let markdown = "# \(note.title)\n\n\(note.bodyMarkdown)"
        lastExport = markdown
        lastError = nil
        lastActionMessage = "已生成 Markdown 导出内容"
        return markdown
    }

    func report(error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    private func configureTranscriber() {
        transcriber.onTranscription = { [weak self] text, isFinal in
            guard let self else { return }
            if isFinal {
                self.deliverFinalRecordingText(self.bodyByApplyingRecordingText(text))
            } else {
                self.draftBodyMarkdown = self.bodyByApplyingRecordingText(text)
                self.lastError = nil
            }
        }
        transcriber.onError = { [weak self] error in
            guard let self else { return }
            self.recordingState = .idle
            self.report(error: error)
        }
    }

    private func deliverFinalRecordingText(_ text: String) {
        let target = InAppTextOutputTarget { [weak self] text in
            self?.draftBodyMarkdown = text
        }
        let result = notesOutputService.deliverToInAppTextTarget(
            text: text,
            target: target
        )

        guard result.kind == .inserted else {
            recordingState = .idle
            draftBodyMarkdown = text
            lastError = outputFailureMessage(for: result)
            lastActionMessage = nil
            return
        }

        lastError = nil
        completeRecordedNote()
    }

    private func completeRecordedNote() {
        recordingState = .idle
        let text = draftBodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            lastError = "没有识别到可保存的内容，请重试。"
            return
        }
        do {
            let title = String(text.prefix(24))
            _ = try createNote(
                title: title,
                bodyMarkdown: text,
                tags: ["recording"]
            )
            draftTitle = title
            draftBodyMarkdown = text
            lastActionMessage = "录音已保存到最近记录"
        } catch {
            report(error: error)
        }
    }

    private func bodyByApplyingRecordingText(_ text: String) -> String {
        let mutableBody = NSMutableString(string: recordingBaseBody)
        mutableBody.replaceCharacters(in: recordingSelection, with: text)
        return mutableBody as String
    }

    private func outputFailureMessage(for result: OutputResult) -> String {
        switch result {
        case .targetChanged(let reason),
             .permissionDenied(let reason),
             .injectionFailed(let reason),
             .copyFailed(let reason):
            return reason
        case .cancelled:
            return "录音输出已取消。"
        case .copied:
            return "录音文本未写入笔记。"
        case .injected:
            return "录音输出失败。"
        }
    }

    private static func clampedSelection(_ selection: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, selection.location), length)
        let availableLength = length - location
        return NSRange(
            location: location,
            length: min(max(0, selection.length), availableLength)
        )
    }

    private func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名笔记" : trimmed
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    private func parseTags(_ text: String) -> [String] {
        normalizedTags(text.split(separator: ",").map(String.init))
    }
}

enum NotesViewModelError: LocalizedError {
    case noteNotFound
    case sourceNotFound

    var errorDescription: String? {
        switch self {
        case .noteNotFound:
            return "笔记不存在。"
        case .sourceNotFound:
            return "来源内容不存在。"
        }
    }
}
