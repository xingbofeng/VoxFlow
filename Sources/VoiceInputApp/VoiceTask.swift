import Foundation

// MARK: - VoiceTaskMode

enum VoiceTaskMode: String, Codable, Equatable {
    case dictation
    case agentCompose
}

// MARK: - VoiceTaskStage

enum VoiceTaskStage: String, Codable, CaseIterable, Equatable, Comparable {
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

    static func < (lhs: VoiceTaskStage, rhs: VoiceTaskStage) -> Bool {
        lhs.order < rhs.order
    }

    func validateAdvancement(to next: VoiceTaskStage) throws {
        guard next >= self else {
            throw VoiceTaskError.backwardsStageTransition(
                from: self.rawValue,
                to: next.rawValue
            )
        }
    }
}

// MARK: - VoiceTaskStatus

enum VoiceTaskStatus: String, Codable, Equatable {
    case inProgress
    case completed
    case partiallyCompleted
    case failed
    case cancelled
}

// MARK: - VoiceTaskFailure

struct VoiceTaskFailure: Codable, Equatable {
    let stage: String
    let code: String
    let message: String
    let recoverable: Bool
}

// MARK: - OutputResult

enum OutputResult: Codable, Equatable {
    case injected
    case copied
    case targetChanged(reason: String)
    case injectionFailed(reason: String)
    case copyFailed(reason: String)
    case cancelled
}

// MARK: - VoiceTaskError

enum VoiceTaskError: Error, Equatable {
    case backwardsStageTransition(from: String, to: String)
    case taskNotFound(String)
}

// MARK: - VoiceTask

struct VoiceTask: Equatable {
    let id: String
    var mode: VoiceTaskMode
    var stage: VoiceTaskStage
    var status: VoiceTaskStatus
    var targetAppBundleID: String?
    var targetAppName: String?
    var targetAppPID: Int?
    var targetWindowID: String?
    var targetWindowTitle: String?
    var audioRelativePath: String?
    var rawTranscript: String?
    var contextJson: String?
    var finalText: String?
    var outputResult: String?
    var failureJson: String?
    var warnings: [String]
    var trace: String?
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
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
        self.warnings = warnings
        self.trace = trace
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}
