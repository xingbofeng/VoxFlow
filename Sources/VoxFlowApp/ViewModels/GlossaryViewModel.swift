import Combine
import Foundation

struct GlossaryImportSummary: Equatable {
    let created: Int
    let updated: Int
    let skipped: Int
}

enum GlossaryDataFormat: String, CaseIterable, Identifiable {
    case json
    case csv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: return "JSON"
        case .csv: return "CSV"
        }
    }
}

@MainActor
final class GlossaryViewModel: ObservableObject {
    @Published private(set) var terms: [GlossaryTerm] = []
    @Published private(set) var replacementRules: [ReplacementRule] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var lastImportSummary: GlossaryImportSummary?
    @Published var searchText = ""

    private let environment: any AppServiceProviding

    init(environment: any AppServiceProviding) {
        self.environment = environment
        load()
    }

    func load() {
        do {
            terms = try environment.glossaryRepository.list(category: nil)
            replacementRules = try environment.replacementRuleRepository.list(category: nil)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateSearch(_ query: String) {
        searchText = query
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                terms = try environment.glossaryRepository.list(category: nil)
                replacementRules = try environment.replacementRuleRepository.list(category: nil)
            } else {
                terms = try environment.glossaryRepository.search(trimmed)
                replacementRules = try environment.replacementRuleRepository.search(trimmed)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveTerm(
        id: String?,
        term: String,
        aliasesText: String,
        category: String,
        enabled: Bool,
        priority: Int,
        notes: String?
    ) throws {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else {
            let error = GlossaryViewModelError.emptyTerm
            report(error: error)
            throw error
        }
        let now = environment.clock.now
        let existing = id.flatMap { existingTerm(id: $0) }
        let record = GlossaryTerm(
            id: id ?? UUID().uuidString,
            term: normalizedTerm,
            aliases: parseAliases(aliasesText),
            category: normalizedCategory(category),
            enabled: enabled,
            priority: priority,
            notes: normalizedOptional(notes),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try environment.glossaryRepository.save(record)
        updateSearch(searchText)
        lastError = nil
        lastActionMessage = id == nil ? "已添加词条 \(normalizedTerm)" : "已更新词条 \(normalizedTerm)"
    }

    func deleteTerm(id: String) {
        do {
            try environment.glossaryRepository.delete(id: id)
            updateSearch(searchText)
            lastError = nil
            lastActionMessage = "已删除词条"
        } catch {
            report(error: error)
        }
    }

    @discardableResult
    func addWordList(_ text: String) throws -> GlossaryImportSummary {
        var created = 0
        var skipped = 0
        var existingTerms = Set(
            try environment.glossaryRepository
                .list(category: nil)
                .map { $0.term.lowercased() }
        )

        for line in text.components(separatedBy: .newlines) {
            let term = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else {
                continue
            }
            let key = term.lowercased()
            guard !existingTerms.contains(key) else {
                skipped += 1
                continue
            }

            let now = environment.clock.now
            try environment.glossaryRepository.save(
                GlossaryTerm(
                    id: UUID().uuidString,
                    term: term,
                    aliases: [],
                    category: "general",
                    enabled: true,
                    priority: 100,
                    notes: nil,
                    createdAt: now,
                    updatedAt: now
                )
            )
            existingTerms.insert(key)
            created += 1
        }

        let summary = GlossaryImportSummary(created: created, updated: 0, skipped: skipped)
        lastImportSummary = summary
        updateSearch(searchText)
        lastError = nil
        lastActionMessage = created == 0 ? "没有新增词条" : "已添加 \(created) 个词条"
        return summary
    }

    @discardableResult
    func importWordList(from url: URL) throws -> GlossaryImportSummary {
        guard url.pathExtension.lowercased() == "txt" else {
            throw GlossaryViewModelError.txtFilesOnly
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GlossaryViewModelError.invalidUTF8
        }
        let summary = try addWordList(text)
        lastActionMessage = "已从 TXT 导入 \(summary.created) 个词条"
        return summary
    }

    func saveReplacementRule(
        id: String?,
        source: String,
        target: String,
        matchMode: ReplacementMatchMode,
        applyStage: ReplacementApplyStage,
        category: String,
        enabled: Bool,
        priority: Int
    ) throws {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty else {
            let error = GlossaryViewModelError.emptyRuleSource
            report(error: error)
            throw error
        }
        let now = environment.clock.now
        let existing = id.flatMap { existingRule(id: $0) }
        let rule = ReplacementRule(
            id: id ?? UUID().uuidString,
            source: normalizedSource,
            target: target,
            matchMode: matchMode,
            applyStage: applyStage,
            category: normalizedCategory(category),
            enabled: enabled,
            priority: priority,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try environment.replacementRuleRepository.save(rule)
        updateSearch(searchText)
        lastError = nil
        lastActionMessage = id == nil ? "已添加替换规则" : "已更新替换规则"
    }

    func deleteReplacementRule(id: String) {
        do {
            try environment.replacementRuleRepository.delete(id: id)
            updateSearch(searchText)
            lastError = nil
            lastActionMessage = "已删除替换规则"
        } catch {
            report(error: error)
        }
    }

    func saveSimpleReplacement(source: String, target: String) throws {
        try saveReplacementRule(
            id: nil,
            source: source,
            target: target,
            matchMode: .contains,
            applyStage: .beforeLLM,
            category: "general",
            enabled: true,
            priority: 100
        )
    }

    func exportData(format: GlossaryDataFormat) throws -> String {
        let data = PortableGlossaryData(
            terms: try environment.glossaryRepository.list(category: nil).map(PortableGlossaryTerm.init(term:)),
            replacementRules: try environment.replacementRuleRepository
                .list(category: nil)
                .map(PortableReplacementRule.init(rule:))
        )

        let output: String
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            output = try String(data: encoder.encode(data), encoding: .utf8) ?? "{}"
        case .csv:
            output = exportCSV(data)
        }
        lastError = nil
        lastActionMessage = "已生成 \(format.title) 导出内容"
        return output
    }

    @discardableResult
    func importData(_ text: String, format: GlossaryDataFormat) throws -> GlossaryImportSummary {
        let data: PortableGlossaryData
        switch format {
        case .json:
            data = try JSONDecoder().decode(PortableGlossaryData.self, from: Data(text.utf8))
        case .csv:
            data = try importCSV(text)
        }

        let summary = try importPortableData(data)
        lastImportSummary = summary
        updateSearch(searchText)
        lastError = nil
        lastActionMessage = "已导入词汇表数据"
        return summary
    }

    @discardableResult
    func importTerms(_ text: String) throws -> GlossaryImportSummary {
        var created = 0
        var updated = 0
        var skipped = 0
        var existingByTerm = Dictionary(
            uniqueKeysWithValues: try environment.glossaryRepository
                .list(category: nil)
                .map { ($0.term.lowercased(), $0) }
        )

        for line in text.components(separatedBy: .newlines) {
            let parsed = parseImportLine(line)
            guard let parsed else {
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    skipped += 1
                }
                continue
            }

            let key = parsed.term.lowercased()
            let now = environment.clock.now
            if let existing = existingByTerm[key] {
                let mergedAliases = mergeAliases(existing.aliases, parsed.aliases)
                let updatedTerm = GlossaryTerm(
                    id: existing.id,
                    term: existing.term,
                    aliases: mergedAliases,
                    category: parsed.category,
                    enabled: existing.enabled,
                    priority: existing.priority,
                    notes: existing.notes,
                    createdAt: existing.createdAt,
                    updatedAt: now
                )
                try environment.glossaryRepository.save(updatedTerm)
                existingByTerm[key] = updatedTerm
                updated += 1
            } else {
                let term = GlossaryTerm(
                    id: UUID().uuidString,
                    term: parsed.term,
                    aliases: parsed.aliases,
                    category: parsed.category,
                    enabled: true,
                    priority: 100,
                    notes: nil,
                    createdAt: now,
                    updatedAt: now
                )
                try environment.glossaryRepository.save(term)
                existingByTerm[key] = term
                created += 1
            }
        }

        let summary = GlossaryImportSummary(created: created, updated: updated, skipped: skipped)
        lastImportSummary = summary
        updateSearch(searchText)
        lastError = nil
        lastActionMessage = "已导入逐行词条"
        return summary
    }

    func report(error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    private func importPortableData(_ data: PortableGlossaryData) throws -> GlossaryImportSummary {
        var created = 0
        var updated = 0
        var skipped = 0
        var existingTerms = Dictionary(
            uniqueKeysWithValues: try environment.glossaryRepository
                .list(category: nil)
                .map { ($0.term.lowercased(), $0) }
        )
        var existingRules = Dictionary(
            uniqueKeysWithValues: try environment.replacementRuleRepository
                .list(category: nil)
                .map { (Self.replacementKey($0.source, $0.matchMode, $0.applyStage), $0) }
        )

        for portableTerm in data.terms {
            let normalizedTerm = portableTerm.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedTerm.isEmpty else {
                skipped += 1
                continue
            }

            let key = normalizedTerm.lowercased()
            let now = environment.clock.now
            if let existing = existingTerms[key] {
                let merged = GlossaryTerm(
                    id: existing.id,
                    term: existing.term,
                    aliases: mergeAliases(existing.aliases, portableTerm.aliases),
                    category: normalizedCategory(portableTerm.category),
                    enabled: existing.enabled,
                    priority: existing.priority,
                    notes: existing.notes ?? normalizedOptional(portableTerm.notes),
                    createdAt: existing.createdAt,
                    updatedAt: now
                )
                try environment.glossaryRepository.save(merged)
                existingTerms[key] = merged
                updated += 1
            } else {
                let term = GlossaryTerm(
                    id: UUID().uuidString,
                    term: normalizedTerm,
                    aliases: portableTerm.aliases,
                    category: normalizedCategory(portableTerm.category),
                    enabled: portableTerm.enabled,
                    priority: portableTerm.priority,
                    notes: normalizedOptional(portableTerm.notes),
                    createdAt: now,
                    updatedAt: now
                )
                try environment.glossaryRepository.save(term)
                existingTerms[key] = term
                created += 1
            }
        }

        for portableRule in data.replacementRules {
            let source = portableRule.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty,
                  let matchMode = ReplacementMatchMode(rawValue: portableRule.matchMode),
                  let applyStage = ReplacementApplyStage(rawValue: portableRule.applyStage) else {
                skipped += 1
                continue
            }

            let key = Self.replacementKey(source, matchMode, applyStage)
            let now = environment.clock.now
            if let existing = existingRules[key] {
                let merged = ReplacementRule(
                    id: existing.id,
                    source: existing.source,
                    target: portableRule.target,
                    matchMode: existing.matchMode,
                    applyStage: existing.applyStage,
                    category: normalizedCategory(portableRule.category),
                    enabled: existing.enabled,
                    priority: existing.priority,
                    createdAt: existing.createdAt,
                    updatedAt: now
                )
                try environment.replacementRuleRepository.save(merged)
                existingRules[key] = merged
                updated += 1
            } else {
                let rule = ReplacementRule(
                    id: UUID().uuidString,
                    source: source,
                    target: portableRule.target,
                    matchMode: matchMode,
                    applyStage: applyStage,
                    category: normalizedCategory(portableRule.category),
                    enabled: portableRule.enabled,
                    priority: portableRule.priority,
                    createdAt: now,
                    updatedAt: now
                )
                try environment.replacementRuleRepository.save(rule)
                existingRules[key] = rule
                created += 1
            }
        }

        return GlossaryImportSummary(created: created, updated: updated, skipped: skipped)
    }

    private func existingTerm(id: String) -> GlossaryTerm? {
        (try? environment.glossaryRepository.list(category: nil))?.first { $0.id == id }
    }

    private func existingRule(id: String) -> ReplacementRule? {
        (try? environment.replacementRuleRepository.list(category: nil))?.first { $0.id == id }
    }

    private func parseAliases(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",，|;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: []) { result, alias in
                if !result.contains(alias) {
                    result.append(alias)
                }
            }
    }

    private func mergeAliases(_ lhs: [String], _ rhs: [String]) -> [String] {
        rhs.reduce(into: lhs) { result, alias in
            if !result.contains(alias) {
                result.append(alias)
            }
        }
    }

    private func normalizedCategory(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "general" : trimmed
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func parseImportLine(_ line: String) -> (term: String, aliases: [String], category: String)? {
        let parts = line
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let term = parts.first, !term.isEmpty else {
            return nil
        }

        let aliases = parts.count > 1 ? parseAliases(parts[1]) : []
        let category = parts.count > 2 ? normalizedCategory(parts[2]) : "general"
        return (term: term, aliases: aliases, category: category)
    }

    private func exportCSV(_ data: PortableGlossaryData) -> String {
        let header = [
            "kind", "term", "aliases", "category", "enabled", "priority",
            "notes", "source", "target", "matchMode", "applyStage"
        ]
        var rows = [header]
        rows.append(contentsOf: data.terms.map { term in
            [
                "term",
                term.term,
                term.aliases.joined(separator: "|"),
                term.category,
                String(term.enabled),
                String(term.priority),
                term.notes ?? "",
                "",
                "",
                "",
                ""
            ]
        })
        rows.append(contentsOf: data.replacementRules.map { rule in
            [
                "replacement",
                "",
                "",
                rule.category,
                String(rule.enabled),
                String(rule.priority),
                "",
                rule.source,
                rule.target,
                rule.matchMode,
                rule.applyStage
            ]
        })
        return rows.map { $0.map(Self.escapeCSVField).joined(separator: ",") }.joined(separator: "\n")
    }

    private func importCSV(_ text: String) throws -> PortableGlossaryData {
        let rows = Self.parseCSV(text)
        guard let header = rows.first else {
            return PortableGlossaryData(terms: [], replacementRules: [])
        }
        let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
        var terms: [PortableGlossaryTerm] = []
        var rules: [PortableReplacementRule] = []

        for row in rows.dropFirst() {
            let kind = Self.csvValue(row, indexes, "kind").lowercased()
            switch kind {
            case "term":
                terms.append(
                    PortableGlossaryTerm(
                        term: Self.csvValue(row, indexes, "term"),
                        aliases: parseAliases(Self.csvValue(row, indexes, "aliases")),
                        category: Self.csvValue(row, indexes, "category", default: "general"),
                        enabled: Self.csvBool(row, indexes, "enabled", default: true),
                        priority: Self.csvInt(row, indexes, "priority", default: 100),
                        notes: normalizedOptional(Self.csvValue(row, indexes, "notes"))
                    )
                )
            case "replacement":
                rules.append(
                    PortableReplacementRule(
                        source: Self.csvValue(row, indexes, "source"),
                        target: Self.csvValue(row, indexes, "target"),
                        matchMode: Self.csvValue(row, indexes, "matchMode", default: ReplacementMatchMode.contains.rawValue),
                        applyStage: Self.csvValue(row, indexes, "applyStage", default: ReplacementApplyStage.beforeLLM.rawValue),
                        category: Self.csvValue(row, indexes, "category", default: "general"),
                        enabled: Self.csvBool(row, indexes, "enabled", default: true),
                        priority: Self.csvInt(row, indexes, "priority", default: 100)
                    )
                )
            default:
                continue
            }
        }

        return PortableGlossaryData(terms: terms, replacementRules: rules)
    }

    private static func replacementKey(
        _ source: String,
        _ matchMode: ReplacementMatchMode,
        _ applyStage: ReplacementApplyStage
    ) -> String {
        "\(source.lowercased())|\(matchMode.rawValue)|\(applyStage.rawValue)"
    }

    private static func escapeCSVField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if character == "\n", !isQuoted {
                row.append(field)
                if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(row)
                }
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
            index += 1
        }

        row.append(field)
        if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.append(row)
        }
        return rows.map { row in
            row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    private static func csvValue(
        _ row: [String],
        _ indexes: [String: Int],
        _ name: String,
        default defaultValue: String = ""
    ) -> String {
        guard let index = indexes[name], row.indices.contains(index), !row[index].isEmpty else {
            return defaultValue
        }
        return row[index]
    }

    private static func csvBool(
        _ row: [String],
        _ indexes: [String: Int],
        _ name: String,
        default defaultValue: Bool
    ) -> Bool {
        let value = csvValue(row, indexes, name).lowercased()
        if ["true", "1", "yes"].contains(value) { return true }
        if ["false", "0", "no"].contains(value) { return false }
        return defaultValue
    }

    private static func csvInt(
        _ row: [String],
        _ indexes: [String: Int],
        _ name: String,
        default defaultValue: Int
    ) -> Int {
        Int(csvValue(row, indexes, name)) ?? defaultValue
    }
}

enum GlossaryViewModelError: LocalizedError {
    case emptyTerm
    case emptyRuleSource
    case txtFilesOnly
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .emptyTerm:
            return "标准词不能为空。"
        case .emptyRuleSource:
            return "替换来源不能为空。"
        case .txtFilesOnly:
            return "只支持导入 TXT 文件。"
        case .invalidUTF8:
            return "TXT 文件必须使用 UTF-8 编码。"
        }
    }
}

private struct PortableGlossaryData: Codable {
    let terms: [PortableGlossaryTerm]
    let replacementRules: [PortableReplacementRule]
}

private struct PortableGlossaryTerm: Codable {
    let term: String
    let aliases: [String]
    let category: String
    let enabled: Bool
    let priority: Int
    let notes: String?

    init(
        term: String,
        aliases: [String],
        category: String,
        enabled: Bool,
        priority: Int,
        notes: String?
    ) {
        self.term = term
        self.aliases = aliases
        self.category = category
        self.enabled = enabled
        self.priority = priority
        self.notes = notes
    }

    init(term: GlossaryTerm) {
        self.init(
            term: term.term,
            aliases: term.aliases,
            category: term.category,
            enabled: term.enabled,
            priority: term.priority,
            notes: term.notes
        )
    }
}

private struct PortableReplacementRule: Codable {
    let source: String
    let target: String
    let matchMode: String
    let applyStage: String
    let category: String
    let enabled: Bool
    let priority: Int

    init(
        source: String,
        target: String,
        matchMode: String,
        applyStage: String,
        category: String,
        enabled: Bool,
        priority: Int
    ) {
        self.source = source
        self.target = target
        self.matchMode = matchMode
        self.applyStage = applyStage
        self.category = category
        self.enabled = enabled
        self.priority = priority
    }

    init(rule: ReplacementRule) {
        self.init(
            source: rule.source,
            target: rule.target,
            matchMode: rule.matchMode.rawValue,
            applyStage: rule.applyStage.rawValue,
            category: rule.category,
            enabled: rule.enabled,
            priority: rule.priority
        )
    }
}
