import Foundation

enum AgentProviderExecutionCapability: String, Codable, Equatable, Hashable, Sendable {
    case textOnly
    case agentRuntime
}

enum AgentRuntimeKind: String, Codable, Equatable, Sendable {
    case codex
}

struct AgentProviderDescriptor: Codable, Equatable, Sendable {
    let providerID: String
    let displayName: String
    let capabilities: Set<AgentProviderExecutionCapability>
    let supportsImageContextByDefault: Bool
    let runtimeKind: AgentRuntimeKind?
}

enum AgentRuntimeAvailabilityStatus: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var reason: String? {
        if case let .unavailable(reason) = self { return reason }
        return nil
    }
}

struct AgentRuntimeAvailability: Equatable, Sendable {
    let providerID: String
    let status: AgentRuntimeAvailabilityStatus
    let detectedAt: Date
    let expiresAt: Date
    let cliPath: String?
    let cliVersion: String?

    var isAvailable: Bool { status.isAvailable }
}

enum AgentExecutionMode: String, Codable, Equatable, Sendable {
    case codexRuntime
    case codexTextFallback
    case textOnly
}

enum AgentActionStatus: String, Codable, Equatable, Sendable {
    case pending
    case running
    case waitingForPermission
    case completed
    case failed
    case cancelled
}

enum AgentActionEventKind: String, Codable, Equatable, Sendable {
    case turnStarted
    case modelDelta
    case planUpdated
    case toolRequested
    case toolProgress
    case toolResolved
    case tokenUsageUpdated
    case turnCompleted
    case warning
    case error
}

struct AgentTokenUsage: Codable, Equatable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
}

struct ScreenContextSnapshot: Codable, Equatable, Sendable {
    let thumbnailPath: String?
    let imagePath: String?
    let appName: String?
    let bundleID: String?
    let windowTitle: String?
    let capturedAt: Date?
}

struct AgentActionEvent: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: AgentActionEventKind
    let title: String
    let detail: String?
    let timestamp: Date
    let elapsedMS: Int?
    let toolName: String?
    let isFailure: Bool

    init(
        id: String = UUID().uuidString,
        kind: AgentActionEventKind,
        title: String,
        detail: String? = nil,
        timestamp: Date,
        elapsedMS: Int? = nil,
        toolName: String? = nil,
        isFailure: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.elapsedMS = elapsedMS
        self.toolName = toolName
        self.isFailure = isFailure
    }
}

struct AgentActionTrace: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let providerID: String
    let executionMode: AgentExecutionMode
    let status: AgentActionStatus
    let userInstruction: String
    let screenContext: ScreenContextSnapshot?
    let events: [AgentActionEvent]
    let resultSummary: String?
    let model: String?
    let tokenUsage: AgentTokenUsage?
    let startedAt: Date
    let completedAt: Date?
    let failureReason: String?

    init(
        schemaVersion: Int = 1,
        providerID: String,
        executionMode: AgentExecutionMode,
        status: AgentActionStatus,
        userInstruction: String,
        screenContext: ScreenContextSnapshot? = nil,
        events: [AgentActionEvent],
        resultSummary: String? = nil,
        model: String? = nil,
        tokenUsage: AgentTokenUsage? = nil,
        startedAt: Date,
        completedAt: Date? = nil,
        failureReason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.providerID = providerID
        self.executionMode = executionMode
        self.status = status
        self.userInstruction = userInstruction
        self.screenContext = screenContext
        self.events = events
        self.resultSummary = resultSummary
        self.model = model
        self.tokenUsage = tokenUsage
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.failureReason = failureReason
    }

    func safeForPersistence() -> AgentActionTrace {
        AgentActionTrace(
            schemaVersion: schemaVersion,
            providerID: providerID,
            executionMode: executionMode,
            status: status,
            userInstruction: userInstruction,
            screenContext: screenContext,
            events: events,
            resultSummary: resultSummary,
            model: model,
            tokenUsage: tokenUsage,
            startedAt: startedAt,
            completedAt: completedAt,
            failureReason: failureReason
        )
    }
}

struct AgentRuntimeRequest: Equatable, Sendable {
    let taskID: String
    let instruction: String
    let context: ContextSnapshot?
    let target: DictationTarget?
    let workspace: AgentRuntimeSessionWorkspace
    let screenContext: ScreenContextSnapshot?
    let model: String?
}

struct AgentRuntimeResult: Equatable, Sendable {
    let summary: String
    let status: AgentActionStatus
    let trace: AgentActionTrace
}

struct AgentRuntimeProviderSelection: Equatable, Sendable {
    let providerID: String
    let model: String?

    var usesCodexRuntime: Bool {
        providerID.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame
    }
}

enum AgentRuntimeError: LocalizedError, Equatable {
    case unavailable(String)
    case executionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            return reason
        case let .executionFailed(reason):
            return reason
        case .cancelled:
            return "Runtime action cancelled."
        }
    }
}

enum AgentProviderRegistry {
    static let codex = AgentProviderDescriptor(
        providerID: "codex",
        displayName: "Codex",
        capabilities: [.textOnly, .agentRuntime],
        supportsImageContextByDefault: true,
        runtimeKind: .codex
    )

    static let enabledRuntimeProviders: [AgentProviderDescriptor] = [codex]
}
