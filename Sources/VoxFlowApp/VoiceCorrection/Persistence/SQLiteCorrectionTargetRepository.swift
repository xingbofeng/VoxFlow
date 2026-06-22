import Foundation
import VoxFlowVoiceCorrection

final class SQLiteCorrectionTargetRepository: CorrectionTargetRepository {
    private static let logger = AppLogger.database

    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ target: CorrectionTargetTerm) throws {
        Self.logger.debug("correction_target_repo_save_start id=\(target.id) textLen=\(target.text.count)")
        try target.validate()
        let record = CorrectionTargetRecord(target: target)
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO voice_correction_targets (
                    id, text, normalized_text, scope_type, scope_value,
                    lifecycle, source, observed_count, applied_count, reverted_count,
                    created_at, updated_at, last_applied_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    text = excluded.text,
                    normalized_text = excluded.normalized_text,
                    scope_type = excluded.scope_type,
                    scope_value = excluded.scope_value,
                    lifecycle = excluded.lifecycle,
                    source = excluded.source,
                    observed_count = excluded.observed_count,
                    applied_count = excluded.applied_count,
                    reverted_count = excluded.reverted_count,
                    updated_at = excluded.updated_at,
                    last_applied_at = excluded.last_applied_at
                """
            )
            try bind(record, to: statement)
            _ = try statement.step()
        }
        Self.logger.info("correction_target_repo_save_success id=\(target.id)")
    }

    func target(id: UUID) throws -> CorrectionTargetTerm? {
        Self.logger.debug("correction_target_repo_target_start id=\(id)")
        let result: CorrectionTargetTerm? = try databaseQueue.read { connection -> CorrectionTargetTerm? in
            let statement = try connection.prepare(selectSQL + " WHERE id = ? LIMIT 1")
            try statement.bind(id.uuidString, at: 1)
            guard try statement.step() else {
                return nil
            }
            return try row(from: statement)
        }
        Self.logger.debug("correction_target_repo_target_done id=\(id) found=\(result != nil)")
        return result
    }

    func list() throws -> [CorrectionTargetTerm] {
        Self.logger.debug("correction_target_repo_list_start")
        let targets = try databaseQueue.read { connection in
            let statement = try connection.prepare(
                selectSQL + " ORDER BY updated_at DESC, text COLLATE NOCASE ASC"
            )
            var targets: [CorrectionTargetTerm] = []
            while try statement.step() {
                targets.append(try row(from: statement))
            }
            return targets
        }
        Self.logger.debug("correction_target_repo_list_done count=\(targets.count)")
        return targets
    }

    func delete(id: UUID) throws {
        Self.logger.debug("correction_target_repo_delete_start id=\(id)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "DELETE FROM voice_correction_targets WHERE id = ?"
            )
            try statement.bind(id.uuidString, at: 1)
            _ = try statement.step()
        }
        Self.logger.info("correction_target_repo_delete_success id=\(id)")
    }

    private func bind(
        _ record: CorrectionTargetRecord,
        to statement: SQLiteStatement
    ) throws {
        let target = record.target
        try statement.bind(target.id.uuidString, at: 1)
        try statement.bind(target.text, at: 2)
        try statement.bind(target.normalizedText, at: 3)
        try statement.bind(record.scopeType, at: 4)
        try statement.bind(record.scopeValue, at: 5)
        try statement.bind(target.lifecycle.rawValue, at: 6)
        try statement.bind(target.source.rawValue, at: 7)
        try statement.bind(target.observedCount, at: 8)
        try statement.bind(target.appliedCount, at: 9)
        try statement.bind(target.revertedCount, at: 10)
        try statement.bind(formatter.string(from: target.createdAt), at: 11)
        try statement.bind(formatter.string(from: target.updatedAt), at: 12)
        try statement.bind(target.lastAppliedAt.map(formatter.string(from:)), at: 13)
    }

    private func row(from statement: SQLiteStatement) throws -> CorrectionTargetTerm {
        guard let idText = statement.columnString(at: 0),
              let id = UUID(uuidString: idText),
              let text = statement.columnString(at: 1),
              let normalizedText = statement.columnString(at: 2),
              let scopeType = statement.columnString(at: 3),
              let lifecycleText = statement.columnString(at: 5),
              let lifecycle = RuleLifecycle(rawValue: lifecycleText),
              let sourceText = statement.columnString(at: 6),
              let source = RuleSource(rawValue: sourceText),
              let createdAtText = statement.columnString(at: 10),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAtText = statement.columnString(at: 11),
              let updatedAt = formatter.date(from: updatedAtText)
        else {
            Self.logger.error("correction_target_repo_row_invalid")
            throw SQLiteError.stepFailed("Invalid voice_correction_targets row.")
        }

        let scope: RuleScope
        switch scopeType {
        case "global":
            scope = .global
        case "application":
            guard let bundleIdentifier = statement.columnString(at: 4) else {
                Self.logger.error("correction_target_repo_row_missing_application_scope id=\(id)")
                throw SQLiteError.stepFailed("Missing target application scope value.")
            }
            scope = .application(bundleIdentifier: bundleIdentifier)
        default:
            Self.logger.error("correction_target_repo_row_invalid_scope id=\(id) scopeType=\(scopeType)")
            throw SQLiteError.stepFailed("Invalid correction target scope.")
        }

        return CorrectionTargetTerm(
            id: id,
            text: text,
            normalizedText: normalizedText,
            scope: scope,
            lifecycle: lifecycle,
            source: source,
            observedCount: statement.columnInt(at: 7),
            appliedCount: statement.columnInt(at: 8),
            revertedCount: statement.columnInt(at: 9),
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastAppliedAt: statement.columnString(at: 12).flatMap(formatter.date(from:))
        )
    }

    private var selectSQL: String {
        """
        SELECT id, text, normalized_text, scope_type, scope_value,
               lifecycle, source, observed_count, applied_count, reverted_count,
               created_at, updated_at, last_applied_at
        FROM voice_correction_targets
        """
    }
}
