import AudioCommon
import CosyVoiceTTS
import Foundation
import KokoroTTS
import MADLADTranslation
import Qwen3TTS

actor CapabilityModelDownloadCoordinator {
    private var waitersByModelID: [String: [CheckedContinuation<Void, any Error>]] = [:]

    func waiterCount(modelID: String) -> Int {
        waitersByModelID[modelID]?.count ?? 0
    }

    func run(modelID: String, operation: @Sendable () async throws -> Void) async throws {
        if waitersByModelID[modelID] != nil {
            try await withCheckedThrowingContinuation { continuation in
                waitersByModelID[modelID, default: []].append(continuation)
            }
            return
        }

        waitersByModelID[modelID] = []
        do {
            try await operation()
            let waiters = waitersByModelID.removeValue(forKey: modelID) ?? []
            waiters.forEach { $0.resume() }
        } catch {
            let waiters = waitersByModelID.removeValue(forKey: modelID) ?? []
            waiters.forEach { $0.resume(throwing: error) }
            throw error
        }
    }
}

final class SoniqoCapabilityModelDownloader: CapabilityModelDownloading, @unchecked Sendable {
    private let cacheBaseDirectory: URL?
    private let fileManager: FileManager
    private let downloadCoordinator: CapabilityModelDownloadCoordinator

    init(
        cacheBaseDirectory: URL? = nil,
        fileManager: FileManager = .default,
        downloadCoordinator: CapabilityModelDownloadCoordinator = CapabilityModelDownloadCoordinator()
    ) {
        self.cacheBaseDirectory = cacheBaseDirectory
        self.fileManager = fileManager
        self.downloadCoordinator = downloadCoordinator
    }

    func isInstalled(modelID: String) -> Bool {
        if CapabilityModelID.isBuiltInOption(modelID) {
            return true
        }
        guard let model = SoniqoCapabilityModel(modelID: modelID),
              let cacheDirectory = try? cacheDirectory(for: model.huggingFaceModelID) else {
            return false
        }
        return model.requiredRelativePaths.contains { relativePath in
            fileManager.fileExists(atPath: cacheDirectory.appendingPathComponent(relativePath).path)
        }
    }

    func download(modelID: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        if CapabilityModelID.isBuiltInOption(modelID) {
            progress(1.0, "Built-in option")
            return
        }
        guard let model = SoniqoCapabilityModel(modelID: modelID) else { return }
        try await downloadCoordinator.run(modelID: modelID) {
            try await self.download(model: model, modelID: modelID, progress: progress)
        }
    }

    private func download(
        model: SoniqoCapabilityModel,
        modelID: String,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        switch modelID {
        case CapabilityModelID.kokoroTTS:
            _ = try await KokoroTTSModel.fromPretrained(
                modelId: model.huggingFaceModelID,
                cacheDir: try cacheDirectory(for: model.huggingFaceModelID),
                offlineMode: false,
                progressHandler: progress
            )
        case CapabilityModelID.qwen3TTS06B4Bit:
            _ = try await Qwen3TTSModel.fromPretrained(
                modelId: model.huggingFaceModelID,
                cacheDir: try cacheDirectory(for: model.huggingFaceModelID),
                offlineMode: false,
                progressHandler: progress
            )
        case CapabilityModelID.cosyVoice3:
            _ = try await CosyVoiceTTSModel.fromPretrained(
                modelId: model.huggingFaceModelID,
                cacheDir: try cacheDirectory(for: model.huggingFaceModelID),
                offlineMode: false,
                progressHandler: progress
            )
        case CapabilityModelID.madladTranslation:
            _ = try await MADLADTranslator.fromPretrained(
                modelId: model.huggingFaceModelID,
                quantization: .int4,
                cacheDir: try cacheDirectory(for: model.huggingFaceModelID),
                offlineMode: false,
                progressHandler: progress
            )
        default:
            return
        }
    }

    private func cacheDirectory(for huggingFaceModelID: String) throws -> URL {
        try HuggingFaceDownloader.getCacheDirectory(for: huggingFaceModelID, basePath: cacheBaseDirectory)
    }
}

private struct SoniqoCapabilityModel {
    let huggingFaceModelID: String
    let requiredRelativePaths: [String]

    init?(modelID: String) {
        switch modelID {
        case CapabilityModelID.kokoroTTS:
            huggingFaceModelID = KokoroTTSModel.defaultModelId
            requiredRelativePaths = ["kokoro_5s.mlmodelc", "vocab_index.json"]
        case CapabilityModelID.qwen3TTS06B4Bit:
            huggingFaceModelID = Qwen3TTSModel.defaultModelId
            requiredRelativePaths = ["model.safetensors", "config.json"]
        case CapabilityModelID.cosyVoice3:
            huggingFaceModelID = CosyVoiceTTSModel.defaultModelId
            requiredRelativePaths = ["llm.safetensors", "flow.safetensors", "hifigan.safetensors"]
        case CapabilityModelID.madladTranslation:
            huggingFaceModelID = MADLADTranslator.defaultModelId
            requiredRelativePaths = ["int4/model.safetensors", "int4/config.json"]
        default:
            return nil
        }
    }
}
