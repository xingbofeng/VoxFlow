import Foundation
import VoxFlowPromptKit

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
    func style(for target: DictationTarget?, transcript: String?) async throws -> StyleProfileRecord?
    /// Most recent style selection trace. Records manual rules, cache hits,
    /// router calls, defaults, and fallback source codes without user text.
    var lastRouteTrace: StyleRouteTrace? { get }
}

extension StyleSelecting {
    func style(for target: DictationTarget?, transcript: String?) async throws -> StyleProfileRecord? {
        try await style(for: target)
    }
}

final class SettingsBackedStyleSelector: StyleSelecting {
    private let styleRepository: any StyleRepository
    private let appStyleRuleStore: AppStyleRuleStore
    private let autoMatchSettingsStore: StyleAutoMatchSettingsStore
    private let classifier: (any ApplicationStyleClassifying)?
    private(set) var lastRouteTrace: StyleRouteTrace?

    init(
        styleRepository: any StyleRepository,
        settingsRepository: any SettingsRepository,
        classifier: (any ApplicationStyleClassifying)? = nil
    ) {
        self.styleRepository = styleRepository
        self.appStyleRuleStore = AppStyleRuleStore(settingsRepository: settingsRepository)
        self.autoMatchSettingsStore = StyleAutoMatchSettingsStore(settingsRepository: settingsRepository)
        self.classifier = classifier
    }

    func style(for target: DictationTarget?) async throws -> StyleProfileRecord? {
        try await style(for: target, transcript: nil)
    }

    func style(for target: DictationTarget?, transcript: String?) async throws -> StyleProfileRecord? {
        if let target,
           let rule = try matchingRule(for: target),
           let profile = try styleRepository.profile(id: rule.styleID),
           profile.enabled {
            lastRouteTrace = Self.trace(
                source: "manualRule",
                selectedStyleID: profile.id,
                fallbackReason: nil
            )
            return profile
        }
        let settings = autoMatchSettingsStore.load()
        let shouldUseRouteCache = !Self.hasTranscript(transcript)
        if let target, settings.globalEnabled, shouldUseRouteCache {
            if let cached = cachedStyle(for: target, settings: settings) {
                return cached
            }
        }
        if let target, let classifier, settings.globalEnabled {
            let styles = try styleRepository.list(category: nil)
            if let llmClassifier = classifier as? LLMApplicationStyleClassifier {
                let outcome = try? await llmClassifier.classifyWithTrace(
                    target: target,
                    transcript: transcript,
                    styles: styles
                )
                lastRouteTrace = outcome?.trace
                if let outcome, let profile = try? styleRepository.profile(id: outcome.styleID ?? ""),
                   profile.isEligibleForAutoRouter {
                    saveRouteCache(styleID: profile.id, target: target, settings: settings)
                    return profile
                }
            } else if let classifiedID = try? await classifier.classify(target: target, transcript: transcript, styles: styles),
               let profile = try styleRepository.profile(id: classifiedID),
               profile.isEligibleForAutoRouter {
                saveRouteCache(styleID: profile.id, target: target, settings: settings)
                lastRouteTrace = Self.trace(
                    source: "aiRouter",
                    candidateStyleIDs: styles.filter(\.isEligibleForAutoRouter).map(\.id),
                    selectedStyleID: profile.id,
                    fallbackReason: nil
                )
                return profile
            }
        }
        let defaultProfile = try styleRepository.defaultProfile()
        lastRouteTrace = Self.trace(
            source: settings.globalEnabled ? "fallback" : "default",
            selectedStyleID: defaultProfile?.id,
            fallbackReason: settings.globalEnabled ? "router_unavailable" : nil
        )
        return defaultProfile
    }

    private static func hasTranscript(_ transcript: String?) -> Bool {
        transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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

    private func routeCacheKey(for target: DictationTarget) -> String? {
        if let bundleID = normalized(target.bundleID) {
            return "bundle:\(bundleID)"
        }
        if let appName = normalized(target.appName) {
            return "app:\(appName)"
        }
        return nil
    }

    private func cachedStyle(for target: DictationTarget, settings: StyleAutoMatchSettings) -> StyleProfileRecord? {
        guard let key = routeCacheKey(for: target),
              var entry = settings.routeCache[key],
              !entry.isExpired(at: Date()),
              let profile = try? styleRepository.profile(id: entry.styleID),
              profile.isEligibleForAutoRouter else {
            return nil
        }
        entry.hitCount += 1
        entry.lastUsedAt = Date()
        try? autoMatchSettingsStore.update { settings in
            settings.routeCache[key] = entry
        }
        lastRouteTrace = Self.trace(
            source: "aiRouteCache",
            selectedStyleID: profile.id,
            fallbackReason: nil
        )
        return profile
    }

    private func saveRouteCache(styleID: String, target: DictationTarget, settings: StyleAutoMatchSettings) {
        guard let key = routeCacheKey(for: target) else { return }
        let now = Date()
        let entry = StyleRouteCacheEntry(
            styleID: styleID,
            source: "aiRouter",
            createdAt: now,
            lastUsedAt: now,
            expiresAt: now.addingTimeInterval(TimeInterval(settings.routeCacheTTLHours * 3600)),
            hitCount: 0
        )
        try? autoMatchSettingsStore.update { settings in
            settings.routeCache[key] = entry
        }
    }

    private static func trace(
        source: String,
        candidateStyleIDs: [String] = [],
        selectedStyleID: String?,
        fallbackReason: String?
    ) -> StyleRouteTrace {
        StyleRouteTrace(
            candidateStyleIDs: candidateStyleIDs,
            routerResponse: nil,
            selectedStyleID: selectedStyleID,
            fallbackReason: fallbackReason,
            styleSelectionSource: source,
            routerVersion: StyleRouterPromptCatalog.system.version.stringValue,
            renderedPromptHash: "",
            durationMS: nil
        )
    }
}
