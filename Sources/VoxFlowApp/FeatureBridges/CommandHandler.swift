import Foundation

enum CommandEditError: Error, Equatable {
    /// The focused input area offers no text to edit (empty, not a text field,
    /// or a secure field).
    case noEditableText
}

extension CommandEditError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noEditableText:
            return L10n.localize(
                "app.dictation.no_editable_text",
                comment: "Voice command needs text in the focused input area"
            )
        }
    }
}

@MainActor
protocol CommandHandling: AnyObject {
    /// Voice commands need a configured model beside the text to edit.
    var isConfigured: Bool { get }
    /// Whether the focused input area currently holds text a command can edit.
    func hasEditableText() -> Bool
    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws
    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws
    func finish(rawTranscript: String) async throws -> OutputResult
    func cancel()
    func fail(_ error: Error)
}

/// Voice command handler: snapshots the focused input area when recording
/// starts, turns the transcript into an edit instruction, and has the result
/// written back over that same input area.
@MainActor
final class DefaultCommandHandler: CommandHandling {
    private let coordinator: VoiceTaskCoordinator
    private let refiner: (any PromptAwareTextRefining)?
    private let inputAreaTextProvider: @MainActor (Int?) -> String?
    private let isSecureTextField: @MainActor (Int?) -> Bool
    private let currentTarget: @MainActor () -> DictationTarget?

    private var target: DictationTarget?
    private var editingText: String?
    private var activeTaskID: String?

    init(
        coordinator: VoiceTaskCoordinator,
        refiner: (any PromptAwareTextRefining)?,
        inputAreaTextProvider: @escaping @MainActor (Int?) -> String?,
        isSecureTextField: @escaping @MainActor (Int?) -> Bool,
        currentTarget: @escaping @MainActor () -> DictationTarget?
    ) {
        self.coordinator = coordinator
        self.refiner = refiner
        self.inputAreaTextProvider = inputAreaTextProvider
        self.isSecureTextField = isSecureTextField
        self.currentTarget = currentTarget
    }

    var isConfigured: Bool {
        refiner?.isConfigured == true
    }

    func hasEditableText() -> Bool {
        editableText(for: currentTarget()) != nil
    }

    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws {
        if activeTaskID != nil || coordinator.activeTaskID(for: .command) != nil {
            throw CoordinatorError.workflowAlreadyRunning(VoiceWorkflowKind.command.rawValue)
        }
        guard let text = editableText(for: target) else {
            AppLogger.dictation.info("CommandHandler start rejected: no editable text")
            throw CommandEditError.noEditableText
        }
        self.target = target
        editingText = text
        AppLogger.dictation.debug("CommandHandler start target=\(target?.bundleID ?? "nil") textLen=\(text.count)")
        let task = try coordinator.startTask(
            mode: .command,
            target: target,
            asrMetadata: asrMetadata
        )
        activeTaskID = task.id
        AppLogger.dictation.info("CommandHandler task started id=\(task.id)")
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {
        try coordinator.updateASRMetadata(metadata, kind: .command)
    }

    func finish(rawTranscript: String) async throws -> OutputResult {
        guard let taskID = activeTaskID, let editingText else {
            AppLogger.dictation.warning("CommandHandler finish rejected: no active task")
            throw CoordinatorError.noActiveTask
        }
        AppLogger.dictation.debug("CommandHandler finish task=\(taskID) instructionLen=\(rawTranscript.count) textLen=\(editingText.count)")
        try coordinator.recordRawTranscript(rawTranscript, kind: .command)

        let result = try await coordinator.processCommandAndDeliver(
            instruction: rawTranscript,
            editingText: editingText
        )
        activeTaskID = nil
        target = nil
        self.editingText = nil
        return result
    }

    func cancel() {
        AppLogger.dictation.debug("CommandHandler cancel task=\(activeTaskID ?? "nil")")
        try? coordinator.cancelTask(kind: .command)
        activeTaskID = nil
        target = nil
        editingText = nil
    }

    func fail(_ error: Error) {
        AppLogger.dictation.warning("CommandHandler fail \(error.localizedDescription)")
        if case CoordinatorError.workflowAlreadyRunning = error {
            return
        }
        try? coordinator.recordFailure(
            stage: "command",
            code: "command_failed",
            message: error.localizedDescription,
            recoverable: true,
            kind: .command
        )
        activeTaskID = nil
        target = nil
        editingText = nil
    }

    private func editableText(for target: DictationTarget?) -> String? {
        guard let pid = target?.pid, !isSecureTextField(pid) else { return nil }
        // The raw field value is kept as-is: it is later compared against the
        // live field content to prove nothing changed before writing back.
        guard let text = inputAreaTextProvider(pid),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
}
