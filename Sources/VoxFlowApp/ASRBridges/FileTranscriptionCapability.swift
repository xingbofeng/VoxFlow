import Foundation

/// 文件转写 provider 能力分类（OpenSpec revamp-file-transcription-and-notes §2.1）。
///
/// 区分原生文件转写、VoxFlow 分段兼容和不推荐长文件三类，用于在文件转写
/// pipeline 中决定优先路径：原生文件 API → 分段 worker → 不推荐长文件提示。
enum FileTranscriptionCapability: Equatable {
    /// Provider 暴露原生文件转写 API（例如 Groq Whisper 的 `transcribeFile`），
    /// 可直接把整段或分段文件交给 provider 处理。
    case nativeFile
    /// Provider 不支持原生文件 API，但可接受 VoxFlow 切出的窗口文件或音频帧。
    case segmentedCompatible
    /// Provider 技术上可尝试，但长文件稳定性不足，UI 需要给出不推荐提示。
    case notRecommendedForLongFiles
}

/// 文件转写能力解析器：根据 provider ID 返回其文件转写能力分类。
enum FileTranscriptionCapabilityResolver {
    /// 已知支持原生文件转写 API 的 provider ID 集合。
    static let nativeFileProviderIDs: Set<String> = [
        ASRProviderID.groqWhisper,
    ]

    /// 已知不推荐长文件的 provider ID 集合。
    /// Apple Speech 在文件转写场景对长音频稳定性有限，第一版归入不推荐长文件。
    static let notRecommendedForLongFilesProviderIDs: Set<String> = [
        ASRProviderID.appleSpeech,
    ]

    static func resolve(providerID: String?) -> FileTranscriptionCapability {
        guard let providerID, !providerID.isEmpty else {
            return .segmentedCompatible
        }
        if nativeFileProviderIDs.contains(providerID) {
            return .nativeFile
        }
        if notRecommendedForLongFilesProviderIDs.contains(providerID) {
            return .notRecommendedForLongFiles
        }
        return .segmentedCompatible
    }

    /// 是否可以走原生文件转写路径。
    static func supportsNativeFile(providerID: String?) -> Bool {
        resolve(providerID: providerID) == .nativeFile
    }
}
