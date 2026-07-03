import Foundation
import VoxFlowProviderCloudCore
import VoxFlowProviderGroq

/// Groq Whisper 原生文件转写适配器（OpenSpec revamp-file-transcription-and-notes §2.2）。
///
/// 将 `GroqCloudASRClient.transcribeFile` 包装为 `NativeFileTranscribing`，
/// 供 `VoxFlowFileTranscriptionPipeline` 在 nativeFile 路径上调用。
final class GroqNativeFileTranscriber: NativeFileTranscribing, @unchecked Sendable {
    private let makeClient: () -> GroqCloudASRClient
    private let configuration: () -> CloudASRProviderConfiguration?

    init(
        makeClient: @escaping () -> GroqCloudASRClient,
        configuration: @escaping () -> CloudASRProviderConfiguration?
    ) {
        self.makeClient = makeClient
        self.configuration = configuration
    }

    func transcribeFile(
        _ fileURL: URL,
        asrProviderID: String,
        locale: Locale,
        prompt: String?
    ) async throws -> FileTranscriptionResult {
        guard let configuration = configuration() else {
            throw GroqNativeFileTranscriberError.notConfigured
        }
        let client = makeClient()
        let request = CloudASRFileRequest(
            fileURL: fileURL,
            locale: locale,
            configuration: configuration,
            prompt: prompt
        )
        let result = try await client.transcribeFile(request) { _ in }
        let durationMS: Int
        if let seconds = result.durationSeconds {
            durationMS = Int(seconds * 1_000)
        } else {
            durationMS = try VoxFlowFileTranscriptionPipeline.audioDurationMS(fileURL: fileURL)
        }
        return FileTranscriptionResult(
            text: result.text,
            durationMS: durationMS,
            segments: [
                TranscriptionSegment(
                    startMS: 0,
                    endMS: max(durationMS, 1),
                    text: result.text
                )
            ]
        )
    }
}

enum GroqNativeFileTranscriberError: LocalizedError, Equatable {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Groq provider is not configured."
        }
    }
}
