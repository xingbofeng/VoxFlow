import Foundation

struct CorrectionEvidenceRecord: Equatable, Sendable {
    let id: UUID
    let original: String
    let corrected: String
    let correctionType: StructuredCorrection.CorrectionType
    let occurrenceCount: Int
    let source: String
    let createdAt: Date
    let updatedAt: Date
    let lastSeenAt: Date

    init(
        id: UUID = UUID(),
        original: String,
        corrected: String,
        correctionType: StructuredCorrection.CorrectionType,
        occurrenceCount: Int = 1,
        source: String = "llmStructured",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.correctionType = correctionType
        self.occurrenceCount = occurrenceCount
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
    }

    var normalizedOriginal: String {
        Self.normalize(original)
    }

    var normalizedCorrected: String {
        Self.normalize(corrected)
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

protocol CorrectionEvidenceRepository {
    @discardableResult
    func upsert(_ correction: StructuredCorrection) throws -> CorrectionEvidenceRecord
    func hasReverseEvidence(original: String, corrected: String) throws -> Bool
    func relevantKnownCorrections(for rawText: String, limit: Int) throws -> [StructuredCorrectionPromptContext.KnownCorrection]
}

final class SQLiteCorrectionEvidenceRepository: CorrectionEvidenceRepository {
    private static let logger = AppLogger.database

    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    @discardableResult
    func upsert(_ correction: StructuredCorrection) throws -> CorrectionEvidenceRecord {
        let now = Date()
        let original = correction.original.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = correction.corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOriginal = CorrectionEvidenceRecord.normalize(original)
        let normalizedCorrected = CorrectionEvidenceRecord.normalize(corrected)

        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO voice_correction_evidence (
                    id, original, normalized_original, corrected, normalized_corrected,
                    correction_type, occurrence_count, source, created_at, updated_at, last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?, 1, 'llmStructured', ?, ?, ?)
                ON CONFLICT(normalized_original, normalized_corrected, correction_type) DO UPDATE SET
                    original = excluded.original,
                    corrected = excluded.corrected,
                    occurrence_count = occurrence_count + 1,
                    updated_at = excluded.updated_at,
                    last_seen_at = excluded.last_seen_at
                """
            )
            try statement.bind(UUID().uuidString, at: 1)
            try statement.bind(original, at: 2)
            try statement.bind(normalizedOriginal, at: 3)
            try statement.bind(corrected, at: 4)
            try statement.bind(normalizedCorrected, at: 5)
            try statement.bind(correction.type.rawValue, at: 6)
            try statement.bind(formatter.string(from: now), at: 7)
            try statement.bind(formatter.string(from: now), at: 8)
            try statement.bind(formatter.string(from: now), at: 9)
            _ = try statement.step()
        }

        guard let saved = try evidence(
            normalizedOriginal: normalizedOriginal,
            normalizedCorrected: normalizedCorrected,
            correctionType: correction.type
        ) else {
            throw SQLiteError.stepFailed("Missing upserted voice_correction_evidence row.")
        }
        Self.logger.info(
            "correction_evidence_upserted type=\(correction.type.rawValue) count=\(saved.occurrenceCount)"
        )
        return saved
    }

    func hasReverseEvidence(original: String, corrected: String) throws -> Bool {
        let normalizedOriginal = CorrectionEvidenceRecord.normalize(original)
        let normalizedCorrected = CorrectionEvidenceRecord.normalize(corrected)
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT 1 FROM voice_correction_evidence
                WHERE normalized_original = ?
                  AND normalized_corrected = ?
                LIMIT 1
                """
            )
            try statement.bind(normalizedCorrected, at: 1)
            try statement.bind(normalizedOriginal, at: 2)
            return try statement.step()
        }
    }

    func relevantKnownCorrections(
        for rawText: String,
        limit: Int
    ) throws -> [StructuredCorrectionPromptContext.KnownCorrection] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }

        let candidates = try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, original, corrected, correction_type, occurrence_count,
                       source, created_at, updated_at, last_seen_at
                FROM voice_correction_evidence
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM voice_correction_targets
                    WHERE voice_correction_targets.normalized_text = voice_correction_evidence.normalized_corrected
                      AND voice_correction_targets.is_blocklisted = 1
                )
                ORDER BY occurrence_count DESC, last_seen_at DESC
                LIMIT 200
                """
            )
            var records: [CorrectionEvidenceRecord] = []
            while try statement.step() {
                records.append(try row(from: statement))
            }
            return records
        }

        return candidates
            .filter { trimmed.localizedCaseInsensitiveContains($0.original) }
            .prefix(limit)
            .map {
                StructuredCorrectionPromptContext.KnownCorrection(
                    original: $0.original,
                    corrected: $0.corrected
                )
            }
    }

    private func evidence(
        normalizedOriginal: String,
        normalizedCorrected: String,
        correctionType: StructuredCorrection.CorrectionType
    ) throws -> CorrectionEvidenceRecord? {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, original, corrected, correction_type, occurrence_count,
                       source, created_at, updated_at, last_seen_at
                FROM voice_correction_evidence
                WHERE normalized_original = ?
                  AND normalized_corrected = ?
                  AND correction_type = ?
                LIMIT 1
                """
            )
            try statement.bind(normalizedOriginal, at: 1)
            try statement.bind(normalizedCorrected, at: 2)
            try statement.bind(correctionType.rawValue, at: 3)
            guard try statement.step() else { return nil }
            return try row(from: statement)
        }
    }

    private func row(from statement: SQLiteStatement) throws -> CorrectionEvidenceRecord {
        guard let idText = statement.columnString(at: 0),
              let id = UUID(uuidString: idText),
              let original = statement.columnString(at: 1),
              let corrected = statement.columnString(at: 2),
              let correctionTypeText = statement.columnString(at: 3),
              let correctionType = StructuredCorrection.CorrectionType(rawValue: correctionTypeText),
              let source = statement.columnString(at: 5),
              let createdAtText = statement.columnString(at: 6),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAtText = statement.columnString(at: 7),
              let updatedAt = formatter.date(from: updatedAtText),
              let lastSeenAtText = statement.columnString(at: 8),
              let lastSeenAt = formatter.date(from: lastSeenAtText)
        else {
            throw SQLiteError.stepFailed("Invalid voice_correction_evidence row.")
        }
        return CorrectionEvidenceRecord(
            id: id,
            original: original,
            corrected: corrected,
            correctionType: correctionType,
            occurrenceCount: statement.columnInt(at: 4),
            source: source,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastSeenAt: lastSeenAt
        )
    }
}
