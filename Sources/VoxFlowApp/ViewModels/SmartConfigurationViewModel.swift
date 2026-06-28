import Combine
import Foundation

// MARK: - SmartConfigurationPhase

enum SmartConfigurationPhase: Equatable, Sendable {
    case idle
    case scanning(progress: Double)
    case classifying(progress: Double)
    case reviewing
    case applying
    case completed
    case failed(String)

    static func == (lhs: SmartConfigurationPhase, rhs: SmartConfigurationPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.reviewing, .reviewing),
             (.applying, .applying),
             (.completed, .completed):
            return true
        case (.scanning(let a), .scanning(let b)),
             (.classifying(let a), .classifying(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - StyleRecommendationGroup

struct StyleRecommendationGroup: Identifiable, Equatable {
    let id: String
    let styleName: String
    let styleIconName: String
    let source: StyleRecommendationSource
    var recommendations: [ApplicationStyleRecommendation]
}

// MARK: - SmartConfigurationViewModel

@MainActor
final class SmartConfigurationViewModel: ObservableObject {
    @Published private(set) var phase: SmartConfigurationPhase = .idle
    @Published private(set) var groups: [StyleRecommendationGroup] = []
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var classificationProgress: Double = 0
    @Published private(set) var totalAppCount: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    private let environment: any AppServiceProviding
    private let appProvider: any InstalledApplicationProviding
    private let batchClassifier: (any BatchApplicationClassifying)?
    private let recommendationService: any ApplicationStyleRecommending
    private let invitationManager: (any SmartConfigInvitationManaging)?
    private let appStyleRuleStore: AppStyleRuleStore

    private var recommendations: [ApplicationStyleRecommendation] = []
    private var installedApps: [InstalledApplication] = []

    init(
        environment: any AppServiceProviding,
        appProvider: any InstalledApplicationProviding = FileSystemInstalledApplicationProvider(),
        batchClassifier: (any BatchApplicationClassifying)? = nil,
        recommendationService: any ApplicationStyleRecommending = ApplicationStyleRecommendationService(),
        invitationManager: (any SmartConfigInvitationManaging)? = nil
    ) {
        self.environment = environment
        self.appProvider = appProvider
        self.batchClassifier = batchClassifier
        self.recommendationService = recommendationService
        self.invitationManager = invitationManager
        self.appStyleRuleStore = AppStyleRuleStore(settingsRepository: environment.settingsRepository)
    }

    var canConfirm: Bool {
        !recommendations.isEmpty && phase == .reviewing
    }

    var canCancel: Bool {
        switch phase {
        case .scanning, .classifying, .reviewing:
            return true
        default:
            return false
        }
    }
    // MARK: - Scan and Classify

    func startConfiguration() async {
        do {
            phase = .scanning(progress: 0)
            scanProgress = 0
            classificationProgress = 0
            lastError = nil

            installedApps = appProvider.scanInstalledApplications()
            totalAppCount = installedApps.count
            phase = .scanning(progress: 1.0)

            let existingRules = try appStyleRuleStore.list()
            let styles = try environment.styleRepository.list(category: nil)
            let enabledStyles = styles.filter(\.enabled)
            let enabledStyleIDs = Set(enabledStyles.map(\.id))

            let registryRecs = recommendationService.recommend(
                apps: installedApps,
                existingRules: existingRules
            )

            let registryBundleIDs = Set(registryRecs.map { $0.bundleID.lowercased() })
            let userRuleBundleIDs = Set(existingRules.map { $0.bundleID.lowercased() })

            let unregisteredApps = installedApps.filter { app in
                guard let bundleID = app.bundleID else { return false }
                let key = bundleID.lowercased()
                return !registryBundleIDs.contains(key) && !userRuleBundleIDs.contains(key)
            }

            phase = .classifying(progress: 0)
            var aiResults: [BatchClassificationResult] = []

            if let batchClassifier, !unregisteredApps.isEmpty {
                do {
                    aiResults = try await batchClassifier.classifyBatch(
                        apps: unregisteredApps,
                        enabledStyles: enabledStyles
                    )
                    phase = .classifying(progress: 1.0)
                } catch {
                    lastError = error.localizedDescription
                }
            }

            let defaultProfile = try environment.styleRepository.defaultProfile()
            let defaultStyleID = defaultProfile?.id

            recommendations = recommendationService.merge(
                registryRecommendations: registryRecs,
                aiResults: aiResults,
                apps: installedApps,
                existingRules: existingRules,
                defaultStyleID: defaultStyleID,
                enabledStyleIDs: enabledStyleIDs
            )

            buildGroups(from: recommendations, styles: styles)

            invitationManager?.markStarted()
            phase = .reviewing
        } catch {
            lastError = error.localizedDescription
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Confirm

    func confirm() throws {
        phase = .applying
        var appliedCount = 0

        for rec in recommendations {
            let rule = AppStyleRule(
                id: UUID().uuidString,
                bundleID: rec.bundleID,
                appName: rec.appName,
                styleID: rec.suggestedStyleID
            )
            try appStyleRuleStore.save(rule)
            appliedCount += 1
        }

        recommendations.removeAll()
        phase = .completed
        lastError = nil
        lastActionMessage = String(format: L10n.localize("smart.config.action_applied_format", comment: ""), appliedCount)
    }

    // MARK: - Cancel

    func cancel() {
        recommendations.removeAll()
        groups.removeAll()
        phase = .idle
        lastError = nil
        lastActionMessage = L10n.localize("smart.config.action_cancel", comment: "")
    }

    // MARK: - Move app between styles

    func moveApp(bundleID: String, toStyleID: String) {
        guard let index = recommendations.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        let old = recommendations[index]
        recommendations[index] = ApplicationStyleRecommendation(
            bundleID: old.bundleID,
            appName: old.appName,
            suggestedStyleID: toStyleID,
            source: old.source,
            confidence: old.confidence
        )
        rebuildGroups()
    }

    // MARK: - Remove recommendation

    func removeRecommendation(bundleID: String) {
        recommendations.removeAll { $0.bundleID == bundleID }
        rebuildGroups()
    }

    // MARK: - Feedback

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    // MARK: - Private

    private func buildGroups(
        from recommendations: [ApplicationStyleRecommendation],
        styles: [StyleProfileRecord]
    ) {
        let styleMap: [String: StyleProfileRecord] = Dictionary(
            styles.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var groupedByStyleAndSource: [String: [StyleRecommendationSource: [ApplicationStyleRecommendation]]] = [:]

        for rec in recommendations {
            let key = rec.suggestedStyleID
            groupedByStyleAndSource[key, default: [:]][rec.source, default: []].append(rec)
        }

        var result: [StyleRecommendationGroup] = []
        for (styleID, sourceGroups) in groupedByStyleAndSource.sorted(by: { $0.key < $1.key }) {
            let style = styleMap[styleID]
            let styleName = style?.name ?? styleID
            let iconName = Self.iconName(for: styleID)

            for (source, recs) in sourceGroups.sorted(by: { sourceOrder($0.key) < sourceOrder($1.key) }) {
                let groupID = "\(styleID)_\(source.rawValue)"
                result.append(
                    StyleRecommendationGroup(
                        id: groupID,
                        styleName: styleName,
                        styleIconName: iconName,
                        source: source,
                        recommendations: recs
                    )
                )
            }
        }

        groups = result
    }

    private func rebuildGroups() {
        do {
            let styles = try environment.styleRepository.list(category: nil)
            buildGroups(from: recommendations, styles: styles)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func sourceOrder(_ source: StyleRecommendationSource) -> Int {
        switch source {
        case .userRule: return 0
        case .systemPreset: return 1
        case .aiRecommendation: return 2
        case .defaultStyle: return 3
        }
    }

    static func iconName(for styleID: String) -> String {
        switch styleID {
        case "builtin.original": return "text.alignleft"
        case "builtin.formal": return "doc.text"
        case "builtin.casual": return "bubble.left.and.bubble.right"
        case "builtin.energetic": return "sparkles"
        case "builtin.coding": return "chevron.left.forwardslash.chevron.right"
        case "builtin.email": return "envelope"
        case "builtin.chat": return "message"
        default: return "slider.horizontal.3"
        }
    }
}
