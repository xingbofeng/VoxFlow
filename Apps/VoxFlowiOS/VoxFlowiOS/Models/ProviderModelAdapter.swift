import Foundation
import Shared

enum ModelEngine: String {
    case parakeet = "PK"
    case system = "SYS"
    case tencent = "TC"
    case aliyun = "ALI"
    case volcengine = "VOLC"
}

enum ModelState: Equatable {
    case notDownloaded
    case downloading
    case prewarming
    case ready
    case unavailable(String)
    case error(String)
}

enum ModelLoadState: Equatable {
    case idle
    case loading
    case ready
}

extension Notification.Name {
    static let dictusModelLoadStateChanged = Notification.Name("DictusModelLoadStateChanged")
}

struct DeviceCapabilities {
    static func current() -> DeviceCapabilities { DeviceCapabilities() }
}

struct ActiveModelStatus: Equatable {
    let info: ModelInfo
    let state: ModelState

    var isReady: Bool {
        state == .ready
    }
}

struct ModelInfo: Identifiable, Equatable {
    let identifier: String
    var id: String { identifier }
    let provider: SelectedProvider
    let engine: ModelEngine
    let displayName: String
    let localizedDescription: String
    let accuracyScore: Double
    let speedScore: Double
    let sizeLabel: String

    static var all: [ModelInfo] { allIncludingDeprecated }

    static var allIncludingDeprecated: [ModelInfo] {
        SelectedProvider.allCases.map(Self.init(provider:))
    }

    static func available(on _: Any? = nil) -> [ModelInfo] {
        allIncludingDeprecated
    }

    static func forIdentifier(_ identifier: String) -> ModelInfo? {
        allIncludingDeprecated.first { $0.identifier == identifier }
    }

    static func isRecommended(_ identifier: String) -> Bool {
        identifier == SelectedProvider.appleSpeech.rawValue
    }

    init(provider: SelectedProvider) {
        self.provider = provider
        self.identifier = provider.rawValue
        self.displayName = provider.displayName
        self.localizedDescription = L10n.t(provider.summaryKey)

        switch provider {
        case .appleSpeech:
            engine = .system
            accuracyScore = 0.70
            speedScore = 0.88
            sizeLabel = L10n.t("services.runtime.system")
        case .tencent:
            engine = .tencent
            accuracyScore = 0.82
            speedScore = 0.76
            sizeLabel = L10n.t("services.runtime.cloud")
        case .aliyun:
            engine = .aliyun
            accuracyScore = 0.80
            speedScore = 0.78
            sizeLabel = L10n.t("services.runtime.cloud")
        case .volcengine:
            engine = .volcengine
            accuracyScore = 0.82
            speedScore = 0.80
            sizeLabel = L10n.t("services.runtime.cloud")
        }
    }
}

@MainActor
final class ModelManager: ObservableObject {
    @Published var activeModel: String?
    @Published var downloadedModels: Set<String>
    @Published var modelStates: [String: ModelState]
    @Published var downloadProgress: [String: Double] = [:]
    @Published var modelLoadState: ModelLoadState = .idle

    private let credentialStore: LocalCredentialStore

    init(credentialStore: LocalCredentialStore = LocalCredentialStore()) {
        self.credentialStore = credentialStore
        let active = Self.persistedProvider().rawValue
        self.activeModel = active
        self.downloadedModels = [active]
        self.modelStates = Dictionary(
            uniqueKeysWithValues: ModelInfo.allIncludingDeprecated.map {
                ($0.identifier, $0.identifier == active ? .ready : .notDownloaded)
            }
        )
        refreshCredentialStates()
    }

    func loadState() {
        let active = Self.persistedProvider().rawValue
        activeModel = active
        downloadedModels = [active]
        modelStates = Dictionary(
            uniqueKeysWithValues: ModelInfo.allIncludingDeprecated.map { info in
                if let provider = SelectedProvider(rawValue: info.identifier) {
                    return (info.identifier, state(for: provider, selected: info.identifier == active))
                }
                return (info.identifier, .notDownloaded)
            }
        )
    }

    func selectModel(_ identifier: String) {
        guard let provider = SelectedProvider(rawValue: identifier) else { return }
        persist(provider)
    }

    func downloadModel(_ identifier: String) async throws {
        guard let provider = SelectedProvider(rawValue: identifier) else { return }
        modelStates[identifier] = .downloading
        downloadProgress[identifier] = 0.35
        notifyModelLoadStateChanged()

        try await Task.sleep(nanoseconds: 250_000_000)
        downloadProgress[identifier] = 0.75
        modelLoadState = .loading
        notifyModelLoadStateChanged()

        try await Task.sleep(nanoseconds: 350_000_000)
        persist(provider)
        downloadProgress[identifier] = nil
        modelLoadState = .ready
        notifyModelLoadStateChanged()

        try await Task.sleep(nanoseconds: 900_000_000)
        modelLoadState = .idle
        notifyModelLoadStateChanged()
    }

    func cleanupFailedModel(_ identifier: String) {
        guard let provider = SelectedProvider(rawValue: identifier) else { return }
        persist(provider)
    }

    func deleteModel(_: String) throws {}

    func isRecommended(_ identifier: String) -> Bool {
        ModelInfo.isRecommended(identifier)
    }

    var isModelReady: Bool {
        guard let activeModel else { return false }
        return modelStates[activeModel] == .ready
    }

    var activeModelStatus: ActiveModelStatus? {
        guard let activeModel,
              let info = ModelInfo.forIdentifier(activeModel)
        else {
            return nil
        }
        return ActiveModelStatus(
            info: info,
            state: modelStates[activeModel] ?? .notDownloaded
        )
    }

    private func persist(_ provider: SelectedProvider) {
        activeModel = provider.rawValue
        downloadedModels = [provider.rawValue]
        modelStates = Dictionary(
            uniqueKeysWithValues: ModelInfo.allIncludingDeprecated.map {
                ($0.identifier, state(for: $0.provider, selected: $0.provider == provider))
            }
        )
        AppGroup.preferences.set(provider.rawValue, forKey: SharedKeys.provider)
        AppGroup.preferences.synchronize()
        UserDefaults.standard.set(provider.rawValue, forKey: "VoxFlowiOS.selectedProvider")
        refreshCredentialStates()
    }

    private func notifyModelLoadStateChanged() {
        NotificationCenter.default.post(name: .dictusModelLoadStateChanged, object: nil)
    }

    private func refreshCredentialStates() {
        for provider in SelectedProvider.allCases {
            modelStates[provider.rawValue] = state(
                for: provider,
                selected: provider == SelectedProvider(rawValue: activeModel ?? "")
            )
        }
    }

    private func state(for provider: SelectedProvider, selected: Bool) -> ModelState {
        if provider.requiresCredentials,
           let credentialProvider = provider.credentialProvider,
           !credentialStore.isEffectivelyComplete(credentialProvider) {
            return .unavailable(L10n.t("diagnostics.availability.missing_credentials"))
        }
        return selected ? .ready : .notDownloaded
    }

    private static func persistedProvider() -> SelectedProvider {
        let raw = AppGroup.preferences.string(forKey: SharedKeys.provider)
            ?? UserDefaults.standard.string(forKey: "VoxFlowiOS.selectedProvider")
            ?? SelectedProvider.appleSpeech.rawValue
        return SelectedProvider(rawValue: raw) ?? .appleSpeech
    }
}
