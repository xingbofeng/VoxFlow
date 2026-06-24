import Foundation

struct SelectionHistoryRecordDraft: Equatable {
    let kind: VoiceAssetKind
    let selectedText: String
    let resultText: String
    let status: VoiceTaskStatus
    let failureMessage: String?
}

protocol SelectionHistoryRecording: AnyObject {
    func record(_ draft: SelectionHistoryRecordDraft)
}

final class NoopSelectionHistoryRecorder: SelectionHistoryRecording {
    func record(_ draft: SelectionHistoryRecordDraft) {}
}

final class SQLiteSelectionHistoryRecorder: SelectionHistoryRecording {
    private let databaseQueue: DatabaseQueue
    private let clock: any AppClock
    private let formatter = ISO8601DateFormatter()
    private let didRecord: (() -> Void)?

    init(
        databaseQueue: DatabaseQueue,
        clock: any AppClock,
        didRecord: (() -> Void)? = nil
    ) {
        self.databaseQueue = databaseQueue
        self.clock = clock
        self.didRecord = didRecord
    }

    func record(_ draft: SelectionHistoryRecordDraft) {
        let selectedText = draft.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultText = draft.resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty, !resultText.isEmpty else { return }

        let now = clock.now
        let nowText = formatter.string(from: now)
        let failureJson = draft.failureMessage.map { message in
            """
            {"stage":"selectionAction","code":"selection_action_partial","message":"\(Self.escapeJSONString(message))","recoverable":true}
            """
        }

        do {
            try databaseQueue.write { connection in
                let statement = try connection.prepare(
                    """
                    INSERT INTO voice_tasks (
                        id, mode, stage, status,
                        raw_transcript, final_text, output_result, failure_json,
                        warnings_json, created_at, updated_at, completed_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """
                )
                try statement.bind(UUID().uuidString, at: 1)
                try statement.bind(draft.kind.rawValue, at: 2)
                try statement.bind(VoiceTaskStage.processing.rawValue, at: 3)
                try statement.bind(draft.status.rawValue, at: 4)
                try statement.bind(selectedText, at: 5)
                try statement.bind(resultText, at: 6)
                try statement.bind(resultText, at: 7)
                try statement.bind(failureJson, at: 8)
                try statement.bind("[]", at: 9)
                try statement.bind(nowText, at: 10)
                try statement.bind(nowText, at: 11)
                try statement.bind(nowText, at: 12)
                _ = try statement.step()
            }
            didRecord?()
        } catch {
            AppLogger.database.error("记录划词历史失败：\(error.localizedDescription)")
        }
    }

    private static func escapeJSONString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
