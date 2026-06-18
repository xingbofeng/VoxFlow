import Foundation

public struct ASRSessionID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct PartialTranscript: Equatable, Sendable {
    public let stablePrefix: String
    public let unstableSuffix: String
    public let revision: UInt64
    public let audioDuration: Duration

    public init(
        stablePrefix: String,
        unstableSuffix: String,
        revision: UInt64,
        audioDuration: Duration
    ) {
        self.stablePrefix = stablePrefix
        self.unstableSuffix = unstableSuffix
        self.revision = revision
        self.audioDuration = audioDuration
    }
}

public struct ASRMetrics: Equatable, Sendable {
    public let audioDuration: Duration
    public let processedFrameCount: UInt64
    public let droppedFrameCount: UInt64

    public init(
        audioDuration: Duration,
        processedFrameCount: UInt64,
        droppedFrameCount: UInt64
    ) {
        self.audioDuration = audioDuration
        self.processedFrameCount = processedFrameCount
        self.droppedFrameCount = droppedFrameCount
    }
}

public enum ASRErrorCategory: String, CaseIterable, Equatable, Sendable {
    case modelNotInstalled
    case modelCorrupt
    case runtimeUnsupported
    case hardwareUnsupported
    case unsupportedLanguage
    case preparationFailed
    case firstPartialTimeout
    case streamStalled
    case finalTimeout
    case emptyTranscript
    case workerCrashed
    case audioDropped
    case cancelled
}

public struct ASRError: Equatable, Sendable {
    public let category: ASRErrorCategory
    public let message: String

    public init(
        category: ASRErrorCategory,
        message: String
    ) {
        self.category = category
        self.message = message
    }
}

public enum ASREvent: Equatable, Sendable {
    case preparing(sessionID: ASRSessionID, revision: UInt64)
    case ready(sessionID: ASRSessionID, revision: UInt64)
    case speechStarted(sessionID: ASRSessionID, revision: UInt64, sequenceNumber: UInt64)
    case partial(sessionID: ASRSessionID, transcript: PartialTranscript)
    case endpoint(sessionID: ASRSessionID, revision: UInt64, sequenceNumber: UInt64)
    case final(sessionID: ASRSessionID, revision: UInt64, text: String)
    case metrics(sessionID: ASRSessionID, revision: UInt64, metrics: ASRMetrics)
    case failure(sessionID: ASRSessionID, revision: UInt64, error: ASRError)

    public var sessionID: ASRSessionID {
        switch self {
        case let .preparing(sessionID, _),
             let .ready(sessionID, _),
             let .speechStarted(sessionID, _, _),
             let .partial(sessionID, _),
             let .endpoint(sessionID, _, _),
             let .final(sessionID, _, _),
             let .metrics(sessionID, _, _),
             let .failure(sessionID, _, _):
            return sessionID
        }
    }

    public var revision: UInt64 {
        switch self {
        case let .preparing(_, revision),
             let .ready(_, revision),
             let .speechStarted(_, revision, _),
             let .endpoint(_, revision, _),
             let .final(_, revision, _),
             let .metrics(_, revision, _),
             let .failure(_, revision, _):
            return revision
        case let .partial(_, transcript):
            return transcript.revision
        }
    }
}
