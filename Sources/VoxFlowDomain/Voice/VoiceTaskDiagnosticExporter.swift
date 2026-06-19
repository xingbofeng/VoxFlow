import Foundation

public struct VoiceTaskDiagnosticExporter: Sendable {
    public init() {}

    public func export(_ task: VoiceTask) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(VoiceTaskDiagnosticSnapshot(task: task))
    }
}

public struct VoiceTaskDiagnosticSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let mode: VoiceTaskMode
    public let stage: VoiceTaskStage
    public let status: VoiceTaskStatus
    public let targetAppBundleID: String?
    public let targetAppName: String?
    public let hasAudio: Bool
    public let rawTranscriptLength: Int
    public let finalTextLength: Int
    public let outputResultKind: OutputResultKind?
    public let failure: FailureSummary?
    public let asrMetadata: VoiceTaskASRMetadata?
    public let warningCodes: [String]
    public let createdAt: Date
    public let updatedAt: Date
    public let completedAt: Date?

    public init(task: VoiceTask) {
        id = task.id
        mode = task.mode
        stage = task.stage
        status = task.status
        targetAppBundleID = task.targetAppBundleID
        targetAppName = task.targetAppName
        hasAudio = task.audioRelativePath != nil
        rawTranscriptLength = task.rawTranscript?.count ?? 0
        finalTextLength = task.finalText?.count ?? 0
        outputResultKind = Self.outputResultKind(from: task.outputResult)
        failure = Self.failureSummary(from: task.failureJson)
        asrMetadata = task.asrMetadata
        warningCodes = task.warnings
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        completedAt = task.completedAt
    }

    public struct FailureSummary: Codable, Equatable, Sendable {
        public let stage: String
        public let code: String
        public let recoverable: Bool

        init(failure: VoiceTaskFailure) {
            stage = failure.stage
            code = failure.code
            recoverable = failure.recoverable
        }
    }

    private static func outputResultKind(from rawValue: String?) -> OutputResultKind? {
        OutputResultKind.decodePersisted(from: rawValue)
    }

    private static func failureSummary(from rawValue: String?) -> FailureSummary? {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let failure = try? JSONDecoder().decode(VoiceTaskFailure.self, from: data) else {
            return nil
        }
        return FailureSummary(failure: failure)
    }
}
