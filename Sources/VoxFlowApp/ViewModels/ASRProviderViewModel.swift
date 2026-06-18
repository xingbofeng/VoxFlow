import Combine
import Foundation
import VoxFlowProviderFunASR
import VoxFlowProviderNVIDIA
import VoxFlowProviderParaformer
import VoxFlowProviderQwen3
import VoxFlowProviderSenseVoice
import VoxFlowProviderWhisper

enum ASRProviderScope: String, CaseIterable, Identifiable {
    case all
    case offline
    case online

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .online:
            return "在线"
        case .offline:
            return "离线"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .online:
            return "cloud"
        case .offline:
            return "externaldrive"
        }
    }

    func matches(_ descriptor: ASRProviderDescriptor) -> Bool {
        switch self {
        case .all:
            return true
        case .online:
            return descriptor.tags.contains("在线")
        case .offline:
            return descriptor.tags.contains("离线")
        }
    }

    func sort(_ descriptors: [ASRProviderDescriptor]) -> [ASRProviderDescriptor] {
        guard self == .online else { return descriptors }
        let rank = Dictionary(
            uniqueKeysWithValues: [
                ASRProviderID.groqWhisper,
                ASRProviderID.qwenCloudASR,
                ASRProviderID.mistralVoxtral,
                ASRProviderID.assemblyAI,
                ASRProviderID.volcengineDoubao,
                ASRProviderID.elevenLabsScribe,
            ].enumerated().map { ($0.element, $0.offset) }
        )
        return descriptors.sorted {
            (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max)
        }
    }
}

@MainActor
final class ASRProviderViewModel: ObservableObject {
    @Published private(set) var providers: [ASRProviderDescriptor] = []
    @Published private(set) var selectedTags: Set<String> = []
    @Published private(set) var providerScope: ASRProviderScope = .all
    @Published private(set) var downloadProgress: Qwen3ModelDownloadProgress?
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadingProviderID: String? = nil
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    private let environment: any AppServiceProviding
    private let asrManager: ASRManager
    private let registry: ASRProviderRegistry
    private let downloader: any Qwen3ModelDownloading
    private let sherpaModelDownloader: any SherpaASRModelDownloading
    private let senseVoiceModelDownloader: any SenseVoiceModelDownloading
    private let whisperKitModelDownloader: any WhisperKitModelDownloading
    private let paraformerModelDownloader: any ParaformerModelDownloading
    private let nvidiaNemotronModelDownloader: any NVIDIANemotronModelDownloading
    private let qwenReadinessPreparer: any Qwen3ModelReadinessPreparing
    private let qwenRuntimeProvisioner: any Qwen3MLXRuntimeProvisioning
    private let fileManager: FileManager
    private var cancellables = Set<AnyCancellable>()
    private var providerRecordPersistenceTask: Task<Void, Never>?

    init(
        environment: any AppServiceProviding,
        asrManager: ASRManager = ASRManager(),
        registry: ASRProviderRegistry? = nil,
        downloader: any Qwen3ModelDownloading = Qwen3ModelDownloader.live(),
        sherpaModelDownloader: any SherpaASRModelDownloading = SherpaASRModelDownloader(),
        senseVoiceModelDownloader: any SenseVoiceModelDownloading = SenseVoiceModelDownloader(),
        whisperKitModelDownloader: any WhisperKitModelDownloading = WhisperKitModelDownloader(),
        paraformerModelDownloader: any ParaformerModelDownloading = ParaformerModelDownloader(),
        nvidiaNemotronModelDownloader: any NVIDIANemotronModelDownloading = NVIDIANemotronModelDownloader(),
        qwenReadinessPreparer: any Qwen3ModelReadinessPreparing = Qwen3ModelReadinessPreparer(),
        qwenRuntimeProvisioner: any Qwen3MLXRuntimeProvisioning = Qwen3MLXRuntimeProvisioner(),
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.asrManager = asrManager
        self.registry = registry ?? ASRProviderRegistry(asrManager: asrManager)
        self.downloader = downloader
        self.sherpaModelDownloader = sherpaModelDownloader
        self.senseVoiceModelDownloader = senseVoiceModelDownloader
        self.whisperKitModelDownloader = whisperKitModelDownloader
        self.paraformerModelDownloader = paraformerModelDownloader
        self.nvidiaNemotronModelDownloader = nvidiaNemotronModelDownloader
        self.qwenReadinessPreparer = qwenReadinessPreparer
        self.qwenRuntimeProvisioner = qwenRuntimeProvisioner
        self.fileManager = fileManager
        refreshProviders(persistRecords: false)
        // 监听菜单栏等外部途径切换模型后的 UserDefaults 变化
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshProviders(persistRecords: false)
            }
            .store(in: &cancellables)
    }

    var visibleProviders: [ASRProviderDescriptor] {
        providerScope.sort(providers.filter { descriptor in
            providerScope.matches(descriptor)
                && ASRProviderFilter(tags: selectedTags).matches(descriptor)
        })
    }

    var availableTags: [String] {
        Array(Set(providers.filter(providerScope.matches).flatMap(\.tags))).sorted()
    }

    var selectedQwenModelSize: ASRManager.ModelSize {
        asrManager.qwen3ModelSize
    }

    var qwenModelPath: String? {
        asrManager.qwen3ModelPath
    }

    var selectedFunASRPrecision: ASRManager.FunASRPrecision { asrManager.funASRPrecision }
    var selectedWhisperVariant: ASRManager.WhisperVariant { asrManager.whisperVariant }

    func sherpaVariant(for id: String) -> SherpaASRModelVariant? {
        switch id {
        case ASRProviderID.funASR:
            return asrManager.funASRModelVariant
        default:
            return nil
        }
    }

    func whisperKitVariant(for id: String) -> WhisperKitModelVariant? {
        id == ASRProviderID.whisper ? asrManager.whisperModelVariant : nil
    }

    func selectFunASRPrecision(_ precision: ASRManager.FunASRPrecision, selectingProvider: Bool = false) {
        if selectingProvider {
            selectProviderForConfiguration(id: ASRProviderID.funASR)
        }
        asrManager.funASRPrecision = precision
        configurationDidChange()
    }

    func selectWhisperVariant(_ variant: ASRManager.WhisperVariant, selectingProvider: Bool = false) {
        if selectingProvider {
            selectProviderForConfiguration(id: ASRProviderID.whisper)
        }
        guard ASRManager.isWhisperRuntimeSupported(variant: variant) else {
            lastActionMessage = nil
            lastError = ASRManager.whisperRuntimeUnsupportedMessage(for: variant)
            return
        }
        asrManager.whisperVariant = variant
        configurationDidChange()
    }

    func selectQwenModelSize(_ size: ASRManager.ModelSize, selectingProvider: Bool = false) {
        if selectingProvider {
            selectProviderForConfiguration(id: ASRProviderID.qwen3)
        }
        asrManager.qwen3ModelSize = size
        configurationDidChange()
    }

    func selectProviderForConfiguration(id: String) {
        guard let fallbackEngine = fallbackEngine(for: id) else { return }
        asrManager.selectedEngineType = fallbackEngine
    }

    private func configurationDidChange() {
        refreshProviders(persistRecords: false)
        scheduleProviderRecordPersistence()
        lastError = nil
        lastActionMessage = "已切换模型配置"
    }

    func load() {
        refreshProviders(persistRecords: true)
    }

    private func refreshProviders(persistRecords: Bool) {
        do {
            providers = registry.descriptors()
            if persistRecords {
                try persistProviderRecords()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func scheduleProviderRecordPersistence() {
        providerRecordPersistenceTask?.cancel()
        providerRecordPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard let self, !Task.isCancelled else { return }
                try self.persistProviderRecords()
            } catch is CancellationError {
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func selectProviderScope(_ scope: ASRProviderScope) {
        providerScope = scope
        selectedTags.formIntersection(availableTags)
    }

    func selectDefaultProvider(id: String) {
        do {
            try registry.selectDefaultProvider(id: id)
            refreshProviders(persistRecords: false)
            scheduleProviderRecordPersistence()
            lastError = nil
            lastActionMessage = nil
        } catch {
            let message = error.localizedDescription
            load()
            lastError = message
        }
    }

    func setQwenModelPath(_ path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard Qwen3ModelManifest.supportedModelExists(at: url, fileManager: fileManager) else {
            lastError = "所选目录不是可用的 Qwen3-ASR 模型。"
            return
        }
        asrManager.qwen3ModelPath = path
        load()
        lastError = nil
        lastActionMessage = "已设置本地模型目录"
    }

    func downloadQwenModel() async {
        await downloadModel(id: ASRProviderID.qwen3)
    }

    private func modelPath(id: String) -> String? {
        switch id {
        case ASRProviderID.qwen3: return asrManager.qwen3ModelPath
        case ASRProviderID.funASR:
            return asrManager.funASRModelDirectoryURL(for: asrManager.funASRPrecision).path
        case ASRProviderID.whisper:
            return asrManager.whisperModelDirectoryURL(for: asrManager.whisperVariant).path
        case ASRProviderID.senseVoice: return asrManager.senseVoiceModelDirectoryURL().path
        case ASRProviderID.paraformer: return asrManager.paraformerModelDirectoryURL().path
        case ASRProviderID.nvidiaNemotron: return asrManager.nvidiaNemotronModelDirectoryURL().path
        default: return nil
        }
    }

    private func fallbackEngine(for id: String) -> ASREngineType? {
        switch id {
        case ASRProviderID.qwen3: return .qwen3
        case ASRProviderID.funASR: return .funASR
        case ASRProviderID.whisper: return .whisper
        case ASRProviderID.senseVoice: return .senseVoice
        case ASRProviderID.paraformer: return .paraformer
        case ASRProviderID.nvidiaNemotron: return .nvidiaNemotron
        default: return nil
        }
    }

    func downloadModel(id: String) async {
        isDownloading = true
        downloadingProviderID = id
        downloadProgress = nil
        lastError = nil
        defer {
            isDownloading = false
            downloadingProviderID = nil
        }

        do {
            if id == ASRProviderID.qwen3 {
                let modelSize = asrManager.qwen3ModelSize
                let coordinator = SettingsQwenModelDownloadCoordinator(
                    asrManager: asrManager,
                    downloader: downloader,
                    readinessPreparer: qwenReadinessPreparer,
                    runtimeProvisioner: qwenRuntimeProvisioner,
                    fileManager: fileManager
                )
                _ = try await coordinator.downloadQwen3Model(size: modelSize) { [weak self] progress in
                    self?.downloadProgress = progress
                }
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if let variant = whisperKitVariant(for: id) {
                let paths = try ApplicationSupportPaths.live(fileManager: fileManager)
                let installedURL = try await whisperKitModelDownloader.download(
                    variant: variant,
                    modelsDirectory: paths.modelsDirectory
                ) { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard variant.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markWhisperModelReady(at: installedURL.path, variant: asrManager.whisperVariant)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if let variant = sherpaVariant(for: id) {
                let installedURL = try await sherpaModelDownloader.download(variant: variant) { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted ?? 0
                    )
                }
                guard FunASRModelVariant(precision: asrManager.funASRPrecision).modelsExist(
                    at: installedURL,
                    fileManager: fileManager
                ) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markFunASRModelReady(at: installedURL.path, precision: asrManager.funASRPrecision)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.senseVoice {
                let installedURL = try await senseVoiceModelDownloader.download { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard SenseVoiceModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markSenseVoiceModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.paraformer {
                let installedURL = try await paraformerModelDownloader.download { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard ParaformerModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markParaformerModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if id == ASRProviderID.nvidiaNemotron {
                let installedURL = try await nvidiaNemotronModelDownloader.download { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                guard NVIDIANemotronModel.modelsExist(at: installedURL, fileManager: fileManager) else {
                    throw ASREngineError.modelNotLoaded
                }
                asrManager.markNVIDIANemotronModelReady(at: installedURL.path)
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else {
                return
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteLocalQwenModel() {
        deleteLocalModel(id: ASRProviderID.qwen3)
    }

    func deleteLocalModel(id: String) {
        do {
            guard let fallbackEngine = self.fallbackEngine(for: id) else { return }

            if let path = modelPath(id: id), fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(at: URL(fileURLWithPath: path, isDirectory: true))
            }
            if id == ASRProviderID.qwen3 {
                asrManager.qwen3ModelPath = nil
            }

            if asrManager.selectedEngineType == fallbackEngine {
                asrManager.selectedEngineType = .apple
            }
            load()
            lastError = nil
            lastActionMessage = "已删除本地模型"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    private func persistProviderRecords() throws {
        let existing = try environment.asrProviderRepository.list()
            .reduce(into: [String: ASRProviderRecord]()) { partial, record in
                partial[record.id] = record
            }
        let now = environment.clock.now
        for descriptor in providers {
            let record = ASRProviderRecord(
                id: descriptor.id,
                displayName: descriptor.displayName,
                providerType: descriptor.providerType,
                capabilitiesJSON: jsonString(descriptor.capabilities.identifiers),
                tagsJSON: jsonString(descriptor.tags),
                configJSON: jsonString([
                    "modelSize": descriptor.modelSize?.rawValue ?? "",
                    "privacy": descriptor.privacySummary,
                ]),
                enabled: true,
                isDefault: descriptor.isDefault,
                lastHealthStatus: healthStatus(for: descriptor),
                lastHealthMessage: descriptor.statusMessage,
                lastCheckedAt: now,
                createdAt: existing[descriptor.id]?.createdAt ?? now,
                updatedAt: now
            )
            try environment.asrProviderRepository.save(record)
        }
    }

    private func healthStatus(for descriptor: ASRProviderDescriptor) -> String {
        descriptor.healthStatus.rawValue
    }

    private func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
