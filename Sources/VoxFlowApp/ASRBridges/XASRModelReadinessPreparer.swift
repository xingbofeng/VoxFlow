import Foundation
import VoxFlowProviderXASR

protocol XASRModelReadinessPreparing: Sendable {
    func prepare(modelURL: URL) async throws
}

struct XASRModelReadinessPreparer: XASRModelReadinessPreparing {
    private let runner: XASRModelReadinessRunner

    init(streamFactory: any XASRStreamMaking) {
        runner = XASRModelReadinessRunner(streamFactory: streamFactory)
    }

    func prepare(modelURL: URL) async throws {
        do {
            let report = try await runner.prepare(modelURL: modelURL)
            guard report.isReady else { throw XASRModelReadinessError.canaryFailed }
            AppLogger.general.info("X-ASR readiness canary completed path=\(modelURL.lastPathComponent)")
        } catch {
            AppLogger.general.warning("X-ASR readiness failed reason=\(String(describing: error))")
            throw XASRModelReadinessError.canaryFailed
        }
    }
}

enum XASRModelReadinessError: LocalizedError {
    case canaryFailed

    var errorDescription: String? {
        L10n.localize("asr.xasr.canary_failed", comment: "X-ASR readiness failure")
    }
}

/// Keep switching invalidation ordered before new streams, including the readiness canary.
struct XASRAppStreamFactory: XASRStreamMaking {
    let runtime: XASRRuntime
    let beforeStart: @Sendable () async -> Void

    func makeStream(directoryURL: URL) async throws -> any XASRStreaming {
        await beforeStart()
        return try await runtime.makeStream(directoryURL: directoryURL)
    }
}
