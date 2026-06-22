import Foundation
import VoxFlowVoiceCorrection

final class SQLiteCorrectionRuleRepository: CorrectionRuleRepository {
    private static let logger = AppLogger.database

    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ rule: CorrectionRule) throws {
        Self.logger.debug("correction_rule_repo_save_start id=\(rule.id) targetID=\(rule.targetID?.uuidString ?? "nil") enabled=\(rule.isEnabled)")
        try rule.validate()
        let record = CorrectionRuleRecord(rule: rule)
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO voice_correction_rules (
                    id, target_id, original, replacement, match_policy, scope_type, scope_value,
                    allowed_modes_json, lifecycle, source, case_sensitive, confidence,
                    observed_count, applied_count, reverted_count, provider_id, model_id,
                    language, enabled, created_at, updated_at, last_applied_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    target_id = excluded.target_id,
                    original = excluded.original,
                    replacement = excluded.replacement,
                    match_policy = excluded.match_policy,
                    scope_type = excluded.scope_type,
                    scope_value = excluded.scope_value,
                    allowed_modes_json = excluded.allowed_modes_json,
                    lifecycle = excluded.lifecycle,
                    source = excluded.source,
                    case_sensitive = excluded.case_sensitive,
                    confidence = excluded.confidence,
                    observed_count = excluded.observed_count,
                    applied_count = excluded.applied_count,
                    reverted_count = excluded.reverted_count,
                    provider_id = excluded.provider_id,
                    model_id = excluded.model_id,
                    language = excluded.language,
                    enabled = excluded.enabled,
                    updated_at = excluded.updated_at,
                    last_applied_at = excluded.last_applied_at
                """
            )
            try bind(record, to: statement)
            _ = try statement.step()
        }
        Self.logger.info("correction_rule_repo_save_success id=\(rule.id)")
    }

    func rule(id: UUID) throws -> CorrectionRule? {
        Self.logger.debug("correction_rule_repo_rule_start id=\(id)")
        let result: CorrectionRule? = try databaseQueue.read { connection -> CorrectionRule? in
            let statement = try connection.prepare(selectSQL + " WHERE id = ? LIMIT 1")
            try statement.bind(id.uuidString, at: 1)
            guard try statement.step() else {
                return nil
            }
            return try row(from: statement)
        }
        Self.logger.debug("correction_rule_repo_rule_done id=\(id) found=\(result != nil)")
        return result
    }

    func list() throws -> [CorrectionRule] {
        Self.logger.debug("correction_rule_repo_list_start")
        let rules = try databaseQueue.read { connection in
            let statement = try connection.prepare(
                selectSQL + " ORDER BY updated_at DESC, original COLLATE NOCASE ASC"
            )
            var rules: [CorrectionRule] = []
            while try statement.step() {
                rules.append(try row(from: statement))
            }
            return rules
        }
        Self.logger.debug("correction_rule_repo_list_done count=\(rules.count)")
        return rules
    }

    func setEnabled(_ isEnabled: Bool, id: UUID, updatedAt: Date) throws {
        Self.logger.debug("correction_rule_repo_set_enabled_start id=\(id) enabled=\(isEnabled)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "UPDATE voice_correction_rules SET enabled = ?, updated_at = ? WHERE id = ?"
            )
            try statement.bind(isEnabled ? 1 : 0, at: 1)
            try statement.bind(formatter.string(from: updatedAt), at: 2)
            try statement.bind(id.uuidString, at: 3)
            _ = try statement.step()
        }
        Self.logger.info("correction_rule_repo_set_enabled_success id=\(id) enabled=\(isEnabled)")
    }

    func recordApplications(ruleIDs: [UUID], at date: Date) throws {
        guard !ruleIDs.isEmpty else {
            Self.logger.debug("correction_rule_repo_record_applications_skipped empty=true")
            return
        }
        Self.logger.debug("correction_rule_repo_record_applications_start count=\(ruleIDs.count)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE voice_correction_rules
                SET applied_count = applied_count + 1,
                    last_applied_at = ?,
                    updated_at = ?
                WHERE id = ?
                """
            )
            let timestamp = formatter.string(from: date)
            for ruleID in ruleIDs {
                try statement.reset()
                try statement.bind(timestamp, at: 1)
                try statement.bind(timestamp, at: 2)
                try statement.bind(ruleID.uuidString, at: 3)
                _ = try statement.step()
            }
        }
        Self.logger.info("correction_rule_repo_record_applications_success count=\(ruleIDs.count)")
    }

    func delete(id: UUID) throws {
        Self.logger.debug("correction_rule_repo_delete_start id=\(id)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "DELETE FROM voice_correction_rules WHERE id = ?"
            )
            try statement.bind(id.uuidString, at: 1)
            _ = try statement.step()
        }
        Self.logger.info("correction_rule_repo_delete_success id=\(id)")
    }

    func clearAll() throws {
        Self.logger.warning("correction_rule_repo_clear_all_start")
        try databaseQueue.write { connection in
            try connection.execute("DELETE FROM voice_correction_rules")
        }
        Self.logger.warning("correction_rule_repo_clear_all_success")
    }

    private func bind(
        _ record: CorrectionRuleRecord,
        to statement: SQLiteStatement
    ) throws {
        let rule = record.rule
        try statement.bind(rule.id.uuidString, at: 1)
        try statement.bind(rule.targetID?.uuidString, at: 2)
        try statement.bind(rule.original, at: 3)
        try statement.bind(rule.replacement, at: 4)
        try statement.bind(rule.matchPolicy.rawValue, at: 5)
        try statement.bind(record.scopeType, at: 6)
        try statement.bind(record.scopeValue, at: 7)
        try statement.bind(record.allowedModesJSON, at: 8)
        try statement.bind(rule.lifecycle.rawValue, at: 9)
        try statement.bind(rule.source.rawValue, at: 10)
        try statement.bind(rule.caseSensitive ? 1 : 0, at: 11)
        try statement.bind(rule.confidence, at: 12)
        try statement.bind(rule.observedCount, at: 13)
        try statement.bind(rule.appliedCount, at: 14)
        try statement.bind(rule.revertedCount, at: 15)
        try statement.bind(rule.providerID, at: 16)
        try statement.bind(rule.modelID, at: 17)
        try statement.bind(rule.language, at: 18)
        try statement.bind(rule.isEnabled ? 1 : 0, at: 19)
        try statement.bind(formatter.string(from: rule.createdAt), at: 20)
        try statement.bind(formatter.string(from: rule.updatedAt), at: 21)
        try statement.bind(rule.lastAppliedAt.map(formatter.string(from:)), at: 22)
    }

    private func row(from statement: SQLiteStatement) throws -> CorrectionRule {
        guard let idText = statement.columnString(at: 0),
              let id = UUID(uuidString: idText),
              let original = statement.columnString(at: 2),
              let replacement = statement.columnString(at: 3),
              let matchPolicyText = statement.columnString(at: 4),
              let matchPolicy = MatchPolicy(rawValue: matchPolicyText),
              let scopeType = statement.columnString(at: 5),
              let allowedModesText = statement.columnString(at: 7),
              let lifecycleText = statement.columnString(at: 8),
              let lifecycle = RuleLifecycle(rawValue: lifecycleText),
              let sourceText = statement.columnString(at: 9),
              let source = RuleSource(rawValue: sourceText),
              let createdAtText = statement.columnString(at: 19),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAtText = statement.columnString(at: 20),
              let updatedAt = formatter.date(from: updatedAtText)
        else {
            Self.logger.error("correction_rule_repo_row_invalid")
            throw SQLiteError.stepFailed("Invalid voice_correction_rules row.")
        }

        let targetID = statement.columnString(at: 1).flatMap(UUID.init(uuidString:))
        let scope: RuleScope
        switch scopeType {
        case "global":
            scope = .global
        case "application":
            guard let bundleIdentifier = statement.columnString(at: 6) else {
                Self.logger.error("correction_rule_repo_row_missing_application_scope id=\(id)")
                throw SQLiteError.stepFailed("Missing application scope value.")
            }
            scope = .application(bundleIdentifier: bundleIdentifier)
        default:
            Self.logger.error("correction_rule_repo_row_invalid_scope id=\(id) scopeType=\(scopeType)")
            throw SQLiteError.stepFailed("Invalid correction rule scope.")
        }

        let allowedModeValues = try JSONDecoder().decode(
            [String].self,
            from: Data(allowedModesText.utf8)
        )
        let allowedModes = Set(allowedModeValues.compactMap(CorrectionInputMode.init(rawValue:)))

        return CorrectionRule(
            id: id,
            targetID: targetID,
            original: original,
            replacement: replacement,
            matchPolicy: matchPolicy,
            scope: scope,
            allowedModes: allowedModes,
            lifecycle: lifecycle,
            source: source,
            caseSensitive: statement.columnInt(at: 10) != 0,
            confidence: statement.columnDouble(at: 11),
            observedCount: statement.columnInt(at: 12),
            appliedCount: statement.columnInt(at: 13),
            revertedCount: statement.columnInt(at: 14),
            providerID: statement.columnString(at: 15),
            modelID: statement.columnString(at: 16),
            language: statement.columnString(at: 17),
            isEnabled: statement.columnInt(at: 18) != 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastAppliedAt: statement.columnString(at: 21).flatMap(formatter.date(from:))
        )
    }

    private var selectSQL: String {
        """
        SELECT id, target_id, original, replacement, match_policy, scope_type, scope_value,
               allowed_modes_json, lifecycle, source, case_sensitive, confidence,
               observed_count, applied_count, reverted_count, provider_id, model_id,
               language, enabled, created_at, updated_at, last_applied_at
        FROM voice_correction_rules
        """
    }
}
