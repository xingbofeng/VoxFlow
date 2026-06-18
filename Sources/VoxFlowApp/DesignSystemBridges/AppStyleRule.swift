import Foundation

struct AppStyleRule: Codable, Equatable, Identifiable {
    let id: String
    let bundleID: String
    let appName: String
    let styleID: String
}

final class AppStyleRuleStore {
    private struct Payload: Codable {
        let rules: [AppStyleRule]
    }

    static let settingsKey = "style.appRules"

    private let settingsRepository: any SettingsRepository

    init(settingsRepository: any SettingsRepository) {
        self.settingsRepository = settingsRepository
    }

    func list() throws -> [AppStyleRule] {
        guard let json = try settingsRepository.value(forKey: Self.settingsKey),
              let data = json.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode(Payload.self, from: data).rules) ?? []
    }

    func save(_ rule: AppStyleRule) throws {
        let ruleBundleID = Self.normalized(rule.bundleID)
        let ruleAppName = Self.normalized(rule.appName)
        var rules = try list().filter { existing in
            if existing.id == rule.id {
                return false
            }
            if let ruleBundleID,
               Self.normalized(existing.bundleID) == ruleBundleID {
                return false
            }
            if ruleBundleID == nil,
               let ruleAppName,
               Self.normalized(existing.appName) == ruleAppName {
                return false
            }
            return true
        }
        rules.append(rule)
        try write(rules)
    }

    func delete(id: String) throws {
        try write(try list().filter { $0.id != id })
    }

    func replaceAll(_ rules: [AppStyleRule]) throws {
        try write(rules)
    }

    private func write(_ rules: [AppStyleRule]) throws {
        let data = try JSONEncoder().encode(Payload(rules: rules))
        try settingsRepository.set(Self.settingsKey, jsonValue: String(data: data, encoding: .utf8) ?? #"{"rules":[]}"#)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

@MainActor
protocol StyleSelecting {
    func style(for target: DictationTarget?) async throws -> StyleProfileRecord?
}

final class SettingsBackedStyleSelector: StyleSelecting {
    private let styleRepository: any StyleRepository
    private let appStyleRuleStore: AppStyleRuleStore
    private let classifier: (any ApplicationStyleClassifying)?

    init(
        styleRepository: any StyleRepository,
        settingsRepository: any SettingsRepository,
        classifier: (any ApplicationStyleClassifying)? = nil
    ) {
        self.styleRepository = styleRepository
        self.appStyleRuleStore = AppStyleRuleStore(settingsRepository: settingsRepository)
        self.classifier = classifier
    }

    func style(for target: DictationTarget?) async throws -> StyleProfileRecord? {
        if let target,
           let rule = try matchingRule(for: target),
           let profile = try styleRepository.profile(id: rule.styleID),
           profile.enabled {
            return profile
        }
        if let target, let classifier {
            let styles = try styleRepository.list(category: nil).filter(\.enabled)
            if let classifiedID = try? await classifier.classify(target: target, styles: styles),
               let profile = try styleRepository.profile(id: classifiedID),
               profile.enabled {
                return profile
            }
        }
        return try styleRepository.defaultProfile()
    }

    private func matchingRule(for target: DictationTarget) throws -> AppStyleRule? {
        let rules = try appStyleRuleStore.list()
        if let bundleID = normalized(target.bundleID) {
            return rules.first { normalized($0.bundleID) == bundleID }
        }
        if let appName = normalized(target.appName) {
            return rules.first { normalized($0.appName) == appName }
        }
        return nil
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}
