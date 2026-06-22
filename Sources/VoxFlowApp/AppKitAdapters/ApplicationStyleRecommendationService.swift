import Foundation

// MARK: - StyleRecommendationSource

enum StyleRecommendationSource: String, Codable, Equatable, Sendable {
    case userRule
    case systemPreset
    case aiRecommendation
    case defaultStyle
}

// MARK: - ApplicationStyleRecommendation

struct ApplicationStyleRecommendation: Equatable, Sendable {
    let bundleID: String
    let appName: String
    let suggestedStyleID: String
    let source: StyleRecommendationSource
    let confidence: Double
}

// MARK: - ApplicationStyleRecommending

protocol ApplicationStyleRecommending: Sendable {
    func recommend(
        apps: [InstalledApplication],
        existingRules: [AppStyleRule]
    ) -> [ApplicationStyleRecommendation]

    func merge(
        registryRecommendations: [ApplicationStyleRecommendation],
        aiResults: [BatchClassificationResult],
        apps: [InstalledApplication],
        existingRules: [AppStyleRule],
        defaultStyleID: String?,
        enabledStyleIDs: Set<String>
    ) -> [ApplicationStyleRecommendation]
}

// MARK: - ApplicationStyleRecommendationService

struct ApplicationStyleRecommendationService: ApplicationStyleRecommending {
    private static let logger = AppLogger.general

    private let registry: KnownApplicationRegistry

    init(registry: KnownApplicationRegistry = .builtIn()) {
        self.registry = registry
    }

    func recommend(
        apps: [InstalledApplication],
        existingRules: [AppStyleRule]
    ) -> [ApplicationStyleRecommendation] {
        Self.logger.debug("ApplicationStyleRecommendationService recommend apps=\(apps.count) rules=\(existingRules.count)")
        let userRuleBundleIDs: Set<String> = Set(
            existingRules.map { $0.bundleID.lowercased() }
        )

        return apps.compactMap { app -> ApplicationStyleRecommendation? in
            guard let bundleID = app.bundleID else { return nil }
            let key = bundleID.lowercased()

            // User rule wins — skip this app entirely
            if userRuleBundleIDs.contains(key) { return nil }

            // Registry hit
            if let entry = registry.lookup(bundleID: bundleID) {
                Self.logger.debug("ApplicationStyleRecommendationService registry hit bundleID=\(bundleID)")
                return ApplicationStyleRecommendation(
                    bundleID: bundleID,
                    appName: app.name,
                    suggestedStyleID: entry.suggestedStyleID,
                    source: .systemPreset,
                    confidence: 1.0
                )
            }

            Self.logger.debug("ApplicationStyleRecommendationService no preset for bundleID=\(bundleID)")

            // Unknown — no recommendation (Phase 4 LLM will handle these)
            return nil
        }
    }

    func merge(
        registryRecommendations: [ApplicationStyleRecommendation],
        aiResults: [BatchClassificationResult],
        apps: [InstalledApplication],
        existingRules: [AppStyleRule],
        defaultStyleID: String?,
        enabledStyleIDs: Set<String>
    ) -> [ApplicationStyleRecommendation] {
        Self.logger.debug("ApplicationStyleRecommendationService merge start registry=\(registryRecommendations.count) ai=\(aiResults.count)")
        let userRuleBundleIDs: Set<String> = Set(
            existingRules.map { $0.bundleID.lowercased() }
        )
        let registryBundleIDs: Set<String> = Set(
            registryRecommendations.map { $0.bundleID.lowercased() }
        )
        let aiMap: [String: String] = Dictionary(
            aiResults
                .filter { enabledStyleIDs.contains($0.styleID) }
                .map { ($0.bundleID.lowercased(), $0.styleID) },
            uniquingKeysWith: { first, _ in first }
        )

        let appsByID: [String: InstalledApplication] = Dictionary(
            apps.compactMap { app -> (String, InstalledApplication)? in
                guard let bundleID = app.bundleID else { return nil }
                return (bundleID.lowercased(), app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var results: [ApplicationStyleRecommendation] = []

        // Start with registry hits (higher priority than AI)
        results.append(contentsOf: registryRecommendations)

        // Add AI recommendations for apps not already covered
        for (key, styleID) in aiMap {
            guard !userRuleBundleIDs.contains(key),
                  !registryBundleIDs.contains(key),
                  let app = appsByID[key] else { continue }
            Self.logger.debug("ApplicationStyleRecommendationService add AI recommendation bundleID=\(key) styleID=\(styleID)")
            results.append(
                ApplicationStyleRecommendation(
                    bundleID: app.bundleID ?? key,
                    appName: app.name,
                    suggestedStyleID: styleID,
                    source: .aiRecommendation,
                    confidence: 0.7
                )
            )
        }

        return results
    }
}
