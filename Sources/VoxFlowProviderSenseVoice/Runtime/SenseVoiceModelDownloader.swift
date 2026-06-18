import FluidAudio
import Foundation

public struct SenseVoiceModelDownloadProgress: Sendable, Equatable {
    public let fractionCompleted: Double
    public let status: String

    public init(fractionCompleted: Double, status: String) {
        self.fractionCompleted = fractionCompleted
        self.status = status
    }
}

public protocol SenseVoiceModelDownloading: Sendable {
    func download(
        progress: @escaping @MainActor @Sendable (SenseVoiceModelDownloadProgress) -> Void
    ) async throws -> URL
}

public struct SenseVoiceModelDownloader: SenseVoiceModelDownloading {
    public init() {}

    public func download(
        progress: @escaping @MainActor @Sendable (SenseVoiceModelDownloadProgress) -> Void
    ) async throws -> URL {
        let handler: DownloadUtils.ProgressHandler = { update in
            let phase = switch update.phase {
            case .listing: "读取模型清单"
            case .downloading: "下载模型文件"
            case .compiling(let modelName): "编译 \(modelName)"
            }
            Task { @MainActor in
                progress(
                    SenseVoiceModelDownloadProgress(
                        fractionCompleted: update.fractionCompleted,
                        status: phase
                    )
                )
            }
        }
        return try await SenseVoiceModels.download(
            precision: SenseVoiceModel.precision,
            progressHandler: handler
        )
    }
}
