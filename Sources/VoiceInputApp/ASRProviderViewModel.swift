import Combine
import FluidAudio
import Foundation

protocol Qwen3ModelDownloading: Sendable {
    func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL
}

extension Qwen3ModelDownloader: Qwen3ModelDownloading {}

protocol FluidAudioLocalModelDownloading: Sendable {
    func download(
        model: FluidAudioLocalASRModel,
        progress: @escaping @MainActor @Sendable (Double, String) -> Void
    ) async throws -> URL
}

struct FluidAudioLocalModelDownloader: FluidAudioLocalModelDownloading {
    func download(
        model: FluidAudioLocalASRModel,
        progress: @escaping @MainActor @Sendable (Double, String) -> Void
    ) async throws -> URL {
        let handler: DownloadUtils.ProgressHandler = { update in
            let phase = switch update.phase {
            case .listing: "读取模型清单"
            case .downloading: "下载模型文件"
            case .compiling(let modelName): "编译 \(modelName)"
            }
            Task { @MainActor in
                progress(update.fractionCompleted, phase)
            }
        }
        switch model {
        case .paraformer:
            return try await ParaformerModels.download(precision: .int8, progressHandler: handler)
        case .senseVoice:
            return try await SenseVoiceModels.download(precision: model.precision ?? .fp32, progressHandler: handler)
        }
    }
}

@MainActor
final class ASRProviderViewModel: ObservableObject {
    @Published private(set) var providers: [ASRProviderDescriptor] = []
    @Published private(set) var selectedTags: Set<String> = []
    @Published private(set) var downloadProgress: Qwen3ModelDownloadProgress?
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadingProviderID: String? = nil
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    private let environment: AppEnvironment
    private let asrManager: ASRManager
    private let registry: ASRProviderRegistry
    private let downloader: any Qwen3ModelDownloading
    private let localModelDownloader: any FluidAudioLocalModelDownloading
    private let sherpaModelDownloader: any SherpaASRModelDownloading
    private let whisperKitModelDownloader: any WhisperKitModelDownloading
    private let fileManager: FileManager
    private var cancellables = Set<AnyCancellable>()

    init(
        environment: AppEnvironment,
        asrManager: ASRManager = ASRManager(),
        registry: ASRProviderRegistry? = nil,
        downloader: any Qwen3ModelDownloading = Qwen3ModelDownloader(),
        localModelDownloader: any FluidAudioLocalModelDownloading = FluidAudioLocalModelDownloader(),
        sherpaModelDownloader: any SherpaASRModelDownloading = SherpaASRModelDownloader(),
        whisperKitModelDownloader: any WhisperKitModelDownloading = WhisperKitModelDownloader(),
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.asrManager = asrManager
        self.registry = registry ?? ASRProviderRegistry(asrManager: asrManager)
        self.downloader = downloader
        self.localModelDownloader = localModelDownloader
        self.sherpaModelDownloader = sherpaModelDownloader
        self.whisperKitModelDownloader = whisperKitModelDownloader
        self.fileManager = fileManager
        load()
        // 监听菜单栏等外部途径切换模型后的 UserDefaults 变化
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.load()
            }
            .store(in: &cancellables)
    }

    var visibleProviders: [ASRProviderDescriptor] {
        providers.filter { ASRProviderFilter(tags: selectedTags).matches($0) }
    }

    var availableTags: [String] {
        Array(Set(providers.flatMap(\.tags))).sorted()
    }

    var selectedQwenModelSize: ASRManager.ModelSize {
        asrManager.qwen3ModelSize
    }

    var qwenModelPath: String? {
        asrManager.qwen3ModelPath
    }

    var selectedFunASRPrecision: ASRManager.FunASRPrecision { asrManager.funASRPrecision }
    var selectedWhisperVariant: ASRManager.WhisperVariant { asrManager.whisperVariant }
    var selectedParaformerLanguage: ASRManager.ParaformerLanguage { asrManager.paraformerLanguage }

    func sherpaVariant(for id: String) -> SherpaASRModelVariant? {
        switch id {
        case ASRProviderID.funASR:
            return asrManager.funASRModelVariant
        case ASRProviderID.paraformer:
            return asrManager.paraformerModelVariant
        default:
            return nil
        }
    }

    func whisperKitVariant(for id: String) -> WhisperKitModelVariant? {
        id == ASRProviderID.whisper ? asrManager.whisperModelVariant : nil
    }

    func selectFunASRPrecision(_ precision: ASRManager.FunASRPrecision) {
        asrManager.funASRPrecision = precision
        configurationDidChange()
    }

    func selectWhisperVariant(_ variant: ASRManager.WhisperVariant) {
        asrManager.whisperVariant = variant
        configurationDidChange()
    }

    func selectParaformerLanguage(_ language: ASRManager.ParaformerLanguage) {
        asrManager.paraformerLanguage = language
        configurationDidChange()
    }

    func selectQwenModelSize(_ size: ASRManager.ModelSize) {
        asrManager.qwen3ModelSize = size
        configurationDidChange()
    }

    private func configurationDidChange() {
        load()
        lastError = nil
        lastActionMessage = "已切换模型配置"
    }

    func load() {
        do {
            providers = registry.descriptors()
            try persistProviderRecords()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func selectDefaultProvider(id: String) {
        do {
            try registry.selectDefaultProvider(id: id)
            load()
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
        case ASRProviderID.funASR, ASRProviderID.paraformer:
            return sherpaVariant(for: id)?.defaultDirectoryURL.path
        case ASRProviderID.whisper:
            return asrManager.whisperModelVariant.defaultDirectoryURL.path
        case ASRProviderID.senseVoice: return FluidAudioLocalASRModel.senseVoice.directoryURL.path
        default: return nil
        }
    }

    private func fallbackEngine(for id: String) -> ASREngineType? {
        switch id {
        case ASRProviderID.qwen3: return .qwen3
        case ASRProviderID.funASR: return .funASR
        case ASRProviderID.whisper: return .whisper
        case ASRProviderID.paraformer: return .paraformer
        case ASRProviderID.senseVoice: return .senseVoice
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
                guard asrManager.qwen3ModelSize == .size0_6B else {
                    load()
                    lastError = "Qwen3-ASR 1.7B 的本地运行时尚未接入；当前 CoreML 引擎只支持 0.6B。"
                    return
                }
                let manifest = Qwen3ModelManifest.manifest(for: asrManager.qwen3ModelSize)
                let url = try await downloader.download(manifest: manifest) { [weak self] progress in
                    self?.downloadProgress = progress
                }
                let missingPaths = manifest.missingRequiredLocalPaths(at: url, fileManager: fileManager)
                guard missingPaths.isEmpty else {
                    load()
                    lastError = "模型下载完成但缺少必要文件：\(missingPaths.joined(separator: "、"))"
                    return
                }
                asrManager.qwen3ModelPath = url.path
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if let variant = whisperKitVariant(for: id) {
                _ = try await whisperKitModelDownloader.download(variant: variant) { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted
                    )
                }
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else if let variant = sherpaVariant(for: id) {
                _ = try await sherpaModelDownloader.download(variant: variant) { [weak self] update in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: update.status,
                        fileProgress: update.fractionCompleted ?? 0
                    )
                }
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
            } else {
                let model: FluidAudioLocalASRModel
                switch id {
                case ASRProviderID.senseVoice: model = .senseVoice
                default: return
                }
                _ = try await localModelDownloader.download(model: model) { [weak self] fraction, phase in
                    self?.downloadProgress = Qwen3ModelDownloadProgress(
                        fileIndex: 0,
                        fileCount: 1,
                        fileName: phase,
                        fileProgress: fraction
                    )
                }
                load()
                lastError = nil
                lastActionMessage = "本地模型下载完成"
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
                lastHealthStatus: descriptor.isAvailable ? "ok" : "unavailable",
                lastHealthMessage: descriptor.statusMessage,
                lastCheckedAt: now,
                createdAt: existing[descriptor.id]?.createdAt ?? now,
                updatedAt: now
            )
            try environment.asrProviderRepository.save(record)
        }
    }

    private func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
