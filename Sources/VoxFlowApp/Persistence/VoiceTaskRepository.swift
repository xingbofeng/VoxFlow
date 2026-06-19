import Foundation

final class VoiceTaskRepository {
    private let databaseQueue: DatabaseQueue
    private let clock: any AppClock
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue, clock: any AppClock) {
        self.databaseQueue = databaseQueue
        self.clock = clock
    }

    // MARK: - Create

    func create(_ task: VoiceTask) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO voice_tasks (
                    id, mode, stage, status,
                    target_app_bundle_id, target_app_name, target_app_pid,
                    target_window_id, target_window_title,
                    audio_relative_path, raw_transcript, context_json,
                    final_text, output_result, failure_json,
                    asr_metadata_json, warnings_json, trace_json,
                    created_at, updated_at, completed_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            )
            try bind(task, to: statement)
            _ = try statement.step()
        }
    }

    // MARK: - Fetch

    func fetch(id: String) throws -> VoiceTask? {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, mode, stage, status,
                       target_app_bundle_id, target_app_name, target_app_pid,
                       target_window_id, target_window_title,
                       audio_relative_path, raw_transcript, context_json,
                       final_text, output_result, failure_json,
                       asr_metadata_json, warnings_json, trace_json,
                       created_at, updated_at, completed_at
                FROM voice_tasks
                WHERE id = ?
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                return nil
            }
            return try row(from: statement)
        }
    }

    // MARK: - Update stage

    func updateStage(_ task: VoiceTask) throws {
        // Validate monotonic advancement by reading the current stage.
        guard let existing = try fetch(id: task.id) else {
            throw VoiceTaskError.taskNotFound(task.id)
        }
        try existing.stage.validateAdvancement(to: task.stage)

        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET stage = ?, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(task.stage.rawValue, at: 1)
            try statement.bind(formatter.string(from: task.updatedAt), at: 2)
            try statement.bind(task.id, at: 3)
            _ = try statement.step()
        }
    }

    // MARK: - Field-level updates

    func updateRawTranscript(id: String, rawTranscript: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET raw_transcript = ?, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(rawTranscript, at: 1)
            try statement.bind(formatter.string(from: clock.now), at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
    }

    func updateFinalText(id: String, finalText: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET final_text = ?, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(finalText, at: 1)
            try statement.bind(formatter.string(from: clock.now), at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
    }

    func clearFinalText(id: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET final_text = NULL, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(formatter.string(from: clock.now), at: 1)
            try statement.bind(id, at: 2)
            _ = try statement.step()
        }
    }

    func updateContextJson(id: String, contextJson: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET context_json = ?, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(contextJson, at: 1)
            try statement.bind(formatter.string(from: clock.now), at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
    }

    func updateWarnings(id: String, warnings: [String]) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET warnings_json = ?, updated_at = ?
                WHERE id = ?
                """
            )
            let warningsData = try JSONEncoder().encode(warnings)
            try statement.bind(String(data: warningsData, encoding: .utf8) ?? "[]", at: 1)
            try statement.bind(formatter.string(from: clock.now), at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
    }

    func updateTrace(id: String, trace: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET trace_json = ?, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(trace, at: 1)
            try statement.bind(formatter.string(from: clock.now), at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
    }

    func updateOutputResult(id: String, outputResult: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET output_result = ?, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(outputResult, at: 1)
            try statement.bind(formatter.string(from: clock.now), at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
    }

    func updateFailure(id: String, failureJson: String, status: VoiceTaskStatus) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET failure_json = ?, status = ?, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(failureJson, at: 1)
            try statement.bind(status.rawValue, at: 2)
            try statement.bind(formatter.string(from: clock.now), at: 3)
            try statement.bind(id, at: 4)
            _ = try statement.step()
        }
    }

    func updateASRMetadata(id: String, metadata: VoiceTaskASRMetadata) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET asr_metadata_json = ?, updated_at = ?
                WHERE id = ?
                """
            )
            let metadataData = try JSONEncoder().encode(metadata)
            try statement.bind(String(data: metadataData, encoding: .utf8) ?? "{}", at: 1)
            try statement.bind(formatter.string(from: clock.now), at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
    }

    func complete(
        id: String,
        status: VoiceTaskStatus,
        outputResult: String?,
        completedAt: Date
    ) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_tasks
                SET status = ?, output_result = ?, completed_at = ?, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(status.rawValue, at: 1)
            try statement.bind(outputResult, at: 2)
            try statement.bind(formatter.string(from: completedAt), at: 3)
            try statement.bind(formatter.string(from: clock.now), at: 4)
            try statement.bind(id, at: 5)
            _ = try statement.step()
        }
    }

    // MARK: - Queries

    func queryIncompleteTasks() throws -> [VoiceTask] {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, mode, stage, status,
                       target_app_bundle_id, target_app_name, target_app_pid,
                       target_window_id, target_window_title,
                       audio_relative_path, raw_transcript, context_json,
                       final_text, output_result, failure_json,
                       asr_metadata_json, warnings_json, trace_json,
                       created_at, updated_at, completed_at
                FROM voice_tasks
                WHERE status = 'inProgress'
                ORDER BY created_at ASC
                """
            )
            var tasks: [VoiceTask] = []
            while try statement.step() {
                tasks.append(try row(from: statement))
            }
            return tasks
        }
    }

    func listRecent(mode: VoiceTaskMode, limit: Int) throws -> [VoiceTask] {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, mode, stage, status,
                       target_app_bundle_id, target_app_name, target_app_pid,
                       target_window_id, target_window_title,
                       audio_relative_path, raw_transcript, context_json,
                       final_text, output_result, failure_json,
                       asr_metadata_json, warnings_json, trace_json,
                       created_at, updated_at, completed_at
                FROM voice_tasks
                WHERE mode = ?
                ORDER BY created_at DESC
                LIMIT ?
                """
            )
            try statement.bind(mode.rawValue, at: 1)
            try statement.bind(limit, at: 2)
            var tasks: [VoiceTask] = []
            while try statement.step() {
                tasks.append(try row(from: statement))
            }
            return tasks
        }
    }

    func delete(id: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "DELETE FROM voice_tasks WHERE id = ?"
            )
            try statement.bind(id, at: 1)
            _ = try statement.step()
        }
    }

    // MARK: - Private

    private func bind(_ task: VoiceTask, to statement: SQLiteStatement) throws {
        try statement.bind(task.id, at: 1)
        try statement.bind(task.mode.rawValue, at: 2)
        try statement.bind(task.stage.rawValue, at: 3)
        try statement.bind(task.status.rawValue, at: 4)
        try statement.bind(task.targetAppBundleID, at: 5)
        try statement.bind(task.targetAppName, at: 6)
        try statement.bind(task.targetAppPID, at: 7)
        try statement.bind(task.targetWindowID, at: 8)
        try statement.bind(task.targetWindowTitle, at: 9)
        try statement.bind(task.audioRelativePath, at: 10)
        try statement.bind(task.rawTranscript, at: 11)
        try statement.bind(task.contextJson, at: 12)
        try statement.bind(task.finalText, at: 13)
        try statement.bind(task.outputResult, at: 14)
        try statement.bind(task.failureJson, at: 15)
        let asrMetadataData = try task.asrMetadata.map { try JSONEncoder().encode($0) }
        try statement.bind(asrMetadataData.flatMap { String(data: $0, encoding: .utf8) }, at: 16)
        let warningsData = try JSONEncoder().encode(task.warnings)
        try statement.bind(String(data: warningsData, encoding: .utf8) ?? "[]", at: 17)
        try statement.bind(task.trace, at: 18)
        try statement.bind(formatter.string(from: task.createdAt), at: 19)
        try statement.bind(formatter.string(from: task.updatedAt), at: 20)
        try statement.bind(task.completedAt.map(formatter.string(from:)), at: 21)
    }

    private func row(from statement: SQLiteStatement) throws -> VoiceTask {
        guard let id = statement.columnString(at: 0),
              let modeRaw = statement.columnString(at: 1),
              let stageRaw = statement.columnString(at: 2),
              let statusRaw = statement.columnString(at: 3),
              let mode = VoiceTaskMode(rawValue: modeRaw),
              let stage = VoiceTaskStage(rawValue: stageRaw),
              let status = VoiceTaskStatus(rawValue: statusRaw),
              let createdAtText = statement.columnString(at: 18),
              let updatedAtText = statement.columnString(at: 19),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid voice_tasks row.")
        }

        let asrMetadata = statement.columnString(at: 15).flatMap { json in
            try? JSONDecoder().decode(
                VoiceTaskASRMetadata.self,
                from: Data(json.utf8)
            )
        }

        let warningsJson = statement.columnString(at: 16) ?? "[]"
        let warnings = (try? JSONDecoder().decode(
            [String].self,
            from: Data(warningsJson.utf8)
        )) ?? []

        let completedAt = statement.columnString(at: 20).flatMap(formatter.date(from:))

        return VoiceTask(
            id: id,
            mode: mode,
            stage: stage,
            status: status,
            targetAppBundleID: statement.columnString(at: 4),
            targetAppName: statement.columnString(at: 5),
            targetAppPID: {
                let value = statement.columnInt(at: 6)
                // columnInt returns 0 for NULL; check if the raw column is nil.
                if statement.columnString(at: 6) != nil {
                    return value
                }
                return nil as Int?
            }(),
            targetWindowID: statement.columnString(at: 7),
            targetWindowTitle: statement.columnString(at: 8),
            audioRelativePath: statement.columnString(at: 9),
            rawTranscript: statement.columnString(at: 10),
            contextJson: statement.columnString(at: 11),
            finalText: statement.columnString(at: 12),
            outputResult: statement.columnString(at: 13),
            failureJson: statement.columnString(at: 14),
            asrMetadata: asrMetadata,
            warnings: warnings,
            trace: statement.columnString(at: 17),
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }
}
