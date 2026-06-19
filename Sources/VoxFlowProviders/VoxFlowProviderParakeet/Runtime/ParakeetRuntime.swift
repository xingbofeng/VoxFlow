import Foundation
import ParakeetStreamingASR

public protocol ParakeetTranscribing: Sendable {
    func accept(audio: [Float]) async throws -> String
    func finish() async throws -> String
    func cancel() async
}

public protocol ParakeetTranscriberMaking: Sendable {
    func makeTranscriber(directoryURL: URL) async throws -> any ParakeetTranscribing
}

private actor ParakeetSpeechSwiftTranscriber: ParakeetTranscribing {
    private let session: StreamingSession

    init(model: ParakeetStreamingASRModel) throws {
        session = try model.createSession()
    }

    func accept(audio: [Float]) async throws -> String {
        let partials = try session.pushAudio(audio)
        return partials.last?.text ?? ""
    }

    func finish() async throws -> String {
        let finals = try session.finalize()
        return finals.last(where: \.isFinal)?.text ?? finals.last?.text ?? ""
    }

    func cancel() async {}
}

public struct ParakeetTranscriberFactory: ParakeetTranscriberMaking {
    public init() {}

    public func makeTranscriber(directoryURL: URL) async throws -> any ParakeetTranscribing {
        guard ParakeetModel.modelsExist(at: directoryURL) else {
            throw ParakeetProviderError.modelNotInstalled
        }
        let model = try await ParakeetStreamingASRModel.fromPretrained(
            modelId: ParakeetModel.modelID
        )
        return try ParakeetSpeechSwiftTranscriber(model: model)
    }
}
