import Foundation

public enum VoiceTaskMode: String, Codable, Equatable, Sendable {
    case dictation
    case agentCompose
}

public enum VoiceTaskStage: String, Codable, CaseIterable, Equatable, Comparable, Sendable {
    case recording
    case transcribing
    case collectingContext
    case processing
    case outputting

    private var order: Int {
        switch self {
        case .recording: return 0
        case .transcribing: return 1
        case .collectingContext: return 2
        case .processing: return 3
        case .outputting: return 4
        }
    }

    public static func < (lhs: VoiceTaskStage, rhs: VoiceTaskStage) -> Bool {
        lhs.order < rhs.order
    }

    public func validateAdvancement(to next: VoiceTaskStage) throws {
        guard next >= self else {
            throw VoiceTaskError.backwardsStageTransition(
                from: self.rawValue,
                to: next.rawValue
            )
        }
    }
}

public enum VoiceTaskStatus: String, Codable, Equatable, Sendable {
    case inProgress
    case completed
    case partiallyCompleted
    case failed
    case cancelled
}

public struct VoiceTaskFailure: Codable, Equatable, Sendable {
    public let stage: String
    public let code: String
    public let message: String
    public let recoverable: Bool

    public init(
        stage: String,
        code: String,
        message: String,
        recoverable: Bool
    ) {
        self.stage = stage
        self.code = code
        self.message = message
        self.recoverable = recoverable
    }
}

public struct VoiceTaskASRMetadata: Codable, Equatable, Sendable {
    public var providerID: String?
    public var modelID: String?
    public var modelVersion: String?
    public var language: String?
    public var sessionID: String?
    public var audioDurationMs: Int?
    public var finalLatencyMs: Int?
    public var droppedFrameCount: Int?
    public var errorCode: String?

    public init(
        providerID: String? = nil,
        modelID: String? = nil,
        modelVersion: String? = nil,
        language: String? = nil,
        sessionID: String? = nil,
        audioDurationMs: Int? = nil,
        finalLatencyMs: Int? = nil,
        droppedFrameCount: Int? = nil,
        errorCode: String? = nil
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.modelVersion = modelVersion
        self.language = language
        self.sessionID = sessionID
        self.audioDurationMs = audioDurationMs
        self.finalLatencyMs = finalLatencyMs
        self.droppedFrameCount = droppedFrameCount
        self.errorCode = errorCode
    }
}

public enum OutputResult: Codable, Equatable, Sendable {
    case injected
    case copied
    case targetChanged(reason: String)
    case permissionDenied(reason: String)
    case injectionFailed(reason: String)
    case copyFailed(reason: String)
    case cancelled
}

public enum OutputResultKind: String, Codable, Equatable, Sendable {
    case inserted
    case copied
    case targetChanged
    case permissionDenied
    case failed
    case cancelled
}

public struct OutputResultSnapshot: Codable, Equatable, Sendable {
    public let kind: OutputResultKind

    public init(kind: OutputResultKind) {
        self.kind = kind
    }
}

public extension OutputResult {
    var kind: OutputResultKind {
        switch self {
        case .injected:
            return .inserted
        case .copied:
            return .copied
        case .targetChanged:
            return .targetChanged
        case .permissionDenied:
            return .permissionDenied
        case .injectionFailed, .copyFailed:
            return .failed
        case .cancelled:
            return .cancelled
        }
    }

    var snapshot: OutputResultSnapshot {
        OutputResultSnapshot(kind: kind)
    }
}

public extension OutputResultKind {
    static func decodePersisted(from rawValue: String?) -> OutputResultKind? {
        guard let rawValue,
              let data = rawValue.data(using: .utf8) else {
            return nil
        }
        if let snapshot = try? JSONDecoder().decode(OutputResultSnapshot.self, from: data) {
            return snapshot.kind
        }
        if let outputResult = try? JSONDecoder().decode(OutputResult.self, from: data) {
            return outputResult.kind
        }
        return nil
    }
}

public enum VoiceTaskError: Error, Equatable, Sendable {
    case backwardsStageTransition(from: String, to: String)
    case taskNotFound(String)
}

public struct VoiceTask: Equatable, Sendable {
    public let id: String
    public var mode: VoiceTaskMode
    public var stage: VoiceTaskStage
    public var status: VoiceTaskStatus
    public var targetAppBundleID: String?
    public var targetAppName: String?
    public var targetAppPID: Int?
    public var targetWindowID: String?
    public var targetWindowTitle: String?
    public var audioRelativePath: String?
    public var rawTranscript: String?
    public var contextJson: String?
    public var finalText: String?
    public var outputResult: String?
    public var failureJson: String?
    public var asrMetadata: VoiceTaskASRMetadata?
    public var warnings: [String]
    public var trace: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        id: String,
        mode: VoiceTaskMode,
        stage: VoiceTaskStage,
        status: VoiceTaskStatus = .inProgress,
        targetAppBundleID: String? = nil,
        targetAppName: String? = nil,
        targetAppPID: Int? = nil,
        targetWindowID: String? = nil,
        targetWindowTitle: String? = nil,
        audioRelativePath: String? = nil,
        rawTranscript: String? = nil,
        contextJson: String? = nil,
        finalText: String? = nil,
        outputResult: String? = nil,
        failureJson: String? = nil,
        asrMetadata: VoiceTaskASRMetadata? = nil,
        warnings: [String] = [],
        trace: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.mode = mode
        self.stage = stage
        self.status = status
        self.targetAppBundleID = targetAppBundleID
        self.targetAppName = targetAppName
        self.targetAppPID = targetAppPID
        self.targetWindowID = targetWindowID
        self.targetWindowTitle = targetWindowTitle
        self.audioRelativePath = audioRelativePath
        self.rawTranscript = rawTranscript
        self.contextJson = contextJson
        self.finalText = finalText
        self.outputResult = outputResult
        self.failureJson = failureJson
        self.asrMetadata = asrMetadata
        self.warnings = warnings
        self.trace = trace
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}
