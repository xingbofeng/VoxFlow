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
                    created_at, updated_at, last_applied_at,
                    hit_count, is_blocklisted, last_hit_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    last_applied_at = excluded.last_applied_at,
                    hit_count = excluded.hit_count,
                    is_blocklisted = excluded.is_blocklisted,
                    last_hit_at = excluded.last_hit_at
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

    // MARK: - Hotword methods

    func listHotwords() throws -> [CorrectionTargetTerm] {
        Self.logger.debug("hotword_repo_list_start")
        let hotwords = try databaseQueue.read { connection in
            let statement = try connection.prepare(
                selectSQL + """
                 WHERE lifecycle = 'active' AND is_blocklisted = 0
                 ORDER BY
                    (CASE source WHEN 'manual' THEN 0 WHEN 'imported' THEN 1 ELSE 2 END) ASC,
                    hit_count DESC,
                    last_hit_at DESC,
                    updated_at DESC,
                    text COLLATE NOCASE ASC
                """
            )
            var hotwords: [CorrectionTargetTerm] = []
            while try statement.step() {
                hotwords.append(try row(from: statement))
            }
            return hotwords
        }
        Self.logger.debug("hotword_repo_list_done count=\(hotwords.count)")
        return hotwords
    }

    func blocklist(id: UUID) throws {
        Self.logger.debug("hotword_repo_blocklist_start id=\(id)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_correction_targets
                SET is_blocklisted = 1, updated_at = ?
                WHERE id = ?
                """
            )
            try statement.bind(formatter.string(from: Date()), at: 1)
            try statement.bind(id.uuidString, at: 2)
            _ = try statement.step()
        }
        Self.logger.info("hotword_repo_blocklist_success id=\(id)")
    }

    @discardableResult
    func saveHotwordIfNotBlocklisted(_ target: CorrectionTargetTerm) throws -> Bool {
        let normalized = target.normalizedText
        let existing = try existingTarget(normalizedText: normalized, scope: target.scope)
        if existing?.isBlocklisted == true {
            Self.logger.info("hotword_repo_save_skipped_blocklisted normalized=\(normalized)")
            return false
        }
        if var existing {
            existing.text = target.text
            existing.lifecycle = .active
            existing.source = target.source
            existing.observedCount = max(existing.observedCount, target.observedCount)
            existing.updatedAt = Date()
            try save(existing)
            return true
        }
        try save(target)
        return true
    }

    func listLearningCandidates(limit: Int) throws -> [CorrectionTargetTerm] {
        Self.logger.debug("hotword_repo_learning_candidates_start limit=\(limit)")
        guard limit > 0 else { return [] }
        let candidates = try databaseQueue.read { connection in
            let statement = try connection.prepare(
                selectSQL + """
                 WHERE lifecycle = 'candidate'
                   AND source = 'automaticLearning'
                   AND is_blocklisted = 0
                 ORDER BY observed_count DESC, updated_at DESC, text COLLATE NOCASE ASC
                 LIMIT ?
                """
            )
            try statement.bind(limit, at: 1)
            var candidates: [CorrectionTargetTerm] = []
            while try statement.step() {
                candidates.append(try row(from: statement))
            }
            return candidates
        }
        Self.logger.debug("hotword_repo_learning_candidates_done count=\(candidates.count)")
        return candidates
    }

    @discardableResult
    func recordKeyTermObservation(_ term: String, now: Date) throws -> CorrectionTargetTerm? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = CorrectionTargetTerm.normalize(trimmed)
        if let existing = try existingTarget(normalizedText: normalized, scope: .global),
           existing.isBlocklisted {
            Self.logger.info("hotword_repo_observation_skipped_blocklisted normalized=\(normalized)")
            return existing
        }

        let nowText = formatter.string(from: now)
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO voice_correction_targets (
                    id, text, normalized_text, scope_type, scope_value,
                    lifecycle, source, observed_count, applied_count, reverted_count,
                    created_at, updated_at, last_applied_at,
                    hit_count, is_blocklisted, last_hit_at
                ) VALUES (?, ?, ?, 'global', NULL, 'candidate', 'automaticLearning', 1, 0, 0, ?, ?, NULL, 0, 0, NULL)
                ON CONFLICT(scope_type, IFNULL(scope_value, ''), normalized_text) DO UPDATE SET
                    text = excluded.text,
                    observed_count = observed_count + 1,
                    updated_at = excluded.updated_at
                """
            )
            try statement.bind(UUID().uuidString, at: 1)
            try statement.bind(trimmed, at: 2)
            try statement.bind(normalized, at: 3)
            try statement.bind(nowText, at: 4)
            try statement.bind(nowText, at: 5)
            _ = try statement.step()
        }
        return try existingTarget(normalizedText: normalized, scope: .global)
    }

    func unblocklist(normalizedText: String) throws {
        Self.logger.debug("hotword_repo_unblocklist_start normalized=\(normalizedText)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_correction_targets
                SET is_blocklisted = 0, updated_at = ?
                WHERE normalized_text = ?
                """
            )
            try statement.bind(formatter.string(from: Date()), at: 1)
            try statement.bind(normalizedText, at: 2)
            _ = try statement.step()
        }
        Self.logger.info("hotword_repo_unblocklist_success normalized=\(normalizedText)")
    }

    private func existingTarget(
        normalizedText: String,
        scope: RuleScope
    ) throws -> CorrectionTargetTerm? {
        try databaseQueue.read { connection -> CorrectionTargetTerm? in
            let statement = try connection.prepare(
                selectSQL + """
                 WHERE scope_type = ?
                   AND IFNULL(scope_value, '') = ?
                   AND normalized_text = ? COLLATE NOCASE
                 LIMIT 1
                """
            )
            switch scope {
            case .global:
                try statement.bind("global", at: 1)
                try statement.bind("", at: 2)
            case .application(let bundleIdentifier):
                try statement.bind("application", at: 1)
                try statement.bind(bundleIdentifier, at: 2)
            }
            try statement.bind(normalizedText, at: 3)
            guard try statement.step() else { return nil }
            return try row(from: statement)
        }
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
        try statement.bind(target.hitCount, at: 14)
        try statement.bind(target.isBlocklisted ? 1 : 0, at: 15)
        try statement.bind(target.lastHitAt.map(formatter.string(from:)), at: 16)
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
            lastAppliedAt: statement.columnString(at: 12).flatMap(formatter.date(from:)),
            hitCount: statement.columnInt(at: 13),
            isBlocklisted: statement.columnInt(at: 14) != 0,
            lastHitAt: statement.columnString(at: 15).flatMap(formatter.date(from:))
        )
    }

    private var selectSQL: String {
        """
        SELECT id, text, normalized_text, scope_type, scope_value,
               lifecycle, source, observed_count, applied_count, reverted_count,
               created_at, updated_at, last_applied_at,
               hit_count, is_blocklisted, last_hit_at
        FROM voice_correction_targets
        """
    }
}
