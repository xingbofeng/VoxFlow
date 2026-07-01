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
    public let agentAction: AgentActionDiagnosticSummary?
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
        agentAction = Self.agentActionSummary(from: task.trace)
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

    public struct AgentActionDiagnosticSummary: Codable, Equatable, Sendable {
        public let providerID: String?
        public let executionMode: String?
        public let status: String?
        public let model: String?
        public let inputTokens: Int?
        public let outputTokens: Int?
        public let totalTokens: Int?
        public let eventCount: Int
        public let hasScreenImage: Bool
        public let failureReason: String?
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

    private static func agentActionSummary(from rawValue: String?) -> AgentActionDiagnosticSummary? {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = root["agentAction"] as? [String: Any] else {
            return nil
        }
        let tokenUsage = action["tokenUsage"] as? [String: Any]
        let events = action["events"] as? [Any]
        let screenContext = action["screenContext"] as? [String: Any]
        let imagePath = screenContext?["imagePath"] as? String
        return AgentActionDiagnosticSummary(
            providerID: action["providerID"] as? String,
            executionMode: action["executionMode"] as? String,
            status: action["status"] as? String,
            model: action["model"] as? String,
            inputTokens: tokenUsage?["inputTokens"] as? Int,
            outputTokens: tokenUsage?["outputTokens"] as? Int,
            totalTokens: tokenUsage?["totalTokens"] as? Int,
            eventCount: events?.count ?? 0,
            hasScreenImage: imagePath?.isEmpty == false,
            failureReason: action["failureReason"] as? String
        )
    }
}
