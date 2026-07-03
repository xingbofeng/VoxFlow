import Foundation

/// 将旧版 `FileTranscriptionWorking`（单段、不分窗）适配为 `FileTranscriptionPipeline`。
///
/// 用于：
/// 1. 让既有测试 stub（`StubFileTranscriptionWorker` 等）无需重写即可继续驱动 ViewModel。
/// 2. 让 native file provider 失败回退时，pipeline 仍可降级为单段调用。
struct FileTranscriptionWorkerPipeline: FileTranscriptionPipeline {
    let worker: any FileTranscriptionWorking

    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        locale: Locale,
        existingSegments: [TranscriptionSegmentRecord],
        onSegment: @escaping @Sendable (PipelineSegmentUpdate) -> Void,
        progress: @escaping @Sendable (Double, Int, Int) -> Void
    ) async throws -> FileTranscriptionResult {
        // 续跑：已有完成段直接返回，不再调用 worker。
        if let completed = existingSegments.first(where: {
            $0.status == TranscriptionSegmentStatus.completed.rawValue
        }), let text = completed.finalText {
            onSegment(
                PipelineSegmentUpdate(
                    index: 0,
                    startMS: completed.startMS,
                    endMS: completed.endMS,
                    status: .completed,
                    text: text,
                    fallbackReason: nil,
                    retryCount: completed.retryCount,
                    providerID: completed.providerID ?? asrProviderID,
                    providerMode: .segmentedCompatible,
                    error: nil
                )
            )
            progress(1, 1, 1)
            return FileTranscriptionResult(
                text: text,
                durationMS: completed.durationMS,
                segments: [TranscriptionSegment(startMS: completed.startMS, endMS: completed.endMS, text: text)]
            )
        }

        onSegment(
            PipelineSegmentUpdate(
                index: 0,
                startMS: 0,
                endMS: 0,
                status: .running,
                text: nil,
                fallbackReason: nil,
                retryCount: 0,
                providerID: asrProviderID,
                providerMode: .segmentedCompatible,
                error: nil
            )
        )

        do {
            let result = try await worker.transcribe(
                fileURL: fileURL,
                asrProviderID: asrProviderID
            ) { fraction in
                progress(fraction, 0, 1)
            }
            let durationMS = max(result.durationMS, 1)
            onSegment(
                PipelineSegmentUpdate(
                    index: 0,
                    startMS: 0,
                    endMS: durationMS,
                    status: .completed,
                    text: result.text,
                    fallbackReason: nil,
                    retryCount: 0,
                    providerID: asrProviderID,
                    providerMode: .segmentedCompatible,
                    error: nil
                )
            )
            progress(1, 1, 1)
            return result
        } catch {
            onSegment(
                PipelineSegmentUpdate(
                    index: 0,
                    startMS: 0,
                    endMS: 0,
                    status: .failed,
                    text: nil,
                    fallbackReason: .providerError,
                    retryCount: 0,
                    providerID: asrProviderID,
                    providerMode: .segmentedCompatible,
                    error: error.localizedDescription
                )
            )
            throw error
        }
    }
}
