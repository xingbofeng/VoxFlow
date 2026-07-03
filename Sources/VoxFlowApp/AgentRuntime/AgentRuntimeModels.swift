import Foundation

enum AgentProviderExecutionCapability: String, Codable, Equatable, Hashable, Sendable {
    case agentRuntime
}

enum AgentRuntimeKind: String, Codable, Equatable, Sendable {
    case codex
    case opencode
    case claude
    case codebuddy
    case pi
}

struct LocalAgentProviderDescriptor: Codable, Equatable, Sendable {
    let providerID: String
    let displayName: String
    let baseURL: String
    let executableNames: [String]
    let capabilities: Set<AgentProviderExecutionCapability>
    let supportsImageContextByDefault: Bool
    let runtimeKind: AgentRuntimeKind?
}

typealias AgentProviderDescriptor = LocalAgentProviderDescriptor

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
    case localAgentRuntime
    case codexRuntime
    case textOnly

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.localAgentRuntime.rawValue:
            self = .localAgentRuntime
        case Self.codexRuntime.rawValue:
            self = .codexRuntime
        case Self.textOnly.rawValue,
             ["codex", "TextFallback"].joined(),
             ["localAgent", "TextFallback"].joined():
            self = .textOnly
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown agent execution mode: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

enum AgentRuntimeArtifactKind: String, Codable, Equatable, Sendable {
    case file
    case directory
}

struct AgentRuntimeArtifact: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: AgentRuntimeArtifactKind
    let path: String
    let summary: String?
    let updatedAt: Date?

    init(
        id: String = UUID().uuidString,
        kind: AgentRuntimeArtifactKind,
        path: String,
        summary: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.summary = summary
        self.updatedAt = updatedAt
    }
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
    let artifacts: [AgentRuntimeArtifact]
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
        artifacts: [AgentRuntimeArtifact] = [],
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
        self.artifacts = artifacts
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.failureReason = failureReason
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case providerID
        case executionMode
        case status
        case userInstruction
        case screenContext
        case events
        case resultSummary
        case model
        case tokenUsage
        case artifacts
        case startedAt
        case completedAt
        case failureReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        providerID = try container.decode(String.self, forKey: .providerID)
        executionMode = try container.decode(AgentExecutionMode.self, forKey: .executionMode)
        status = try container.decode(AgentActionStatus.self, forKey: .status)
        userInstruction = try container.decode(String.self, forKey: .userInstruction)
        screenContext = try container.decodeIfPresent(ScreenContextSnapshot.self, forKey: .screenContext)
        events = try container.decodeIfPresent([AgentActionEvent].self, forKey: .events) ?? []
        resultSummary = try container.decodeIfPresent(String.self, forKey: .resultSummary)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        tokenUsage = try container.decodeIfPresent(AgentTokenUsage.self, forKey: .tokenUsage)
        artifacts = try container.decodeIfPresent([AgentRuntimeArtifact].self, forKey: .artifacts) ?? []
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
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
            artifacts: artifacts,
            startedAt: startedAt,
            completedAt: completedAt,
            failureReason: failureReason
        )
    }

    func withArtifacts(_ artifacts: [AgentRuntimeArtifact]) -> AgentActionTrace {
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
            artifacts: artifacts,
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

    func withArtifacts(_ artifacts: [AgentRuntimeArtifact]) -> AgentRuntimeResult {
        AgentRuntimeResult(
            summary: summary,
            status: status,
            trace: trace.withArtifacts(artifacts)
        )
    }
}

struct AgentRuntimeProviderSelection: Equatable, Sendable {
    let providerID: String
    let model: String?

    var localAgentProvider: LocalAgentProviderDescriptor? {
        AgentProviderRegistry.localProvider(for: providerID)
    }

    var usesCodexRuntime: Bool {
        providerID.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame
    }

    var isAgentComposeRuntimeEligible: Bool {
        localAgentProvider != nil
    }
}

enum AgentRuntimeError: LocalizedError, Equatable {
    case unavailable(String)
    case executionFailed(String)
    case executionFailedWithOutput(String, stdout: String, stderr: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            return reason
        case let .executionFailed(reason):
            return reason
        case let .executionFailedWithOutput(reason, _, _):
            return reason
        case .cancelled:
            return "Runtime action cancelled."
        }
    }

    func withOutput(stdout: String, stderr: String) -> AgentRuntimeError {
        switch self {
        case let .executionFailed(reason):
            return .executionFailedWithOutput(reason, stdout: stdout, stderr: stderr)
        case .executionFailedWithOutput:
            return self
        case .unavailable, .cancelled:
            return self
        }
    }
}

enum AgentProviderRegistry {
    static let codex = LocalAgentProviderDescriptor(
        providerID: "codex",
        displayName: "Codex",
        baseURL: "local://codex",
        executableNames: ["codex"],
        capabilities: [.agentRuntime],
        supportsImageContextByDefault: true,
        runtimeKind: .codex
    )

    static let opencode = LocalAgentProviderDescriptor(
        providerID: "opencode",
        displayName: "Opencode",
        baseURL: "local://opencode",
        executableNames: ["opencode"],
        capabilities: [.agentRuntime],
        supportsImageContextByDefault: false,
        runtimeKind: .opencode
    )

    static let claude = LocalAgentProviderDescriptor(
        providerID: "claude",
        displayName: "Claude Code",
        baseURL: "local://claude",
        executableNames: ["claude"],
        capabilities: [.agentRuntime],
        supportsImageContextByDefault: false,
        runtimeKind: .claude
    )

    static let codebuddy = LocalAgentProviderDescriptor(
        providerID: "codebuddy",
        displayName: "CodeBuddy",
        baseURL: "local://codebuddy",
        executableNames: ["codebuddy"],
        capabilities: [.agentRuntime],
        supportsImageContextByDefault: false,
        runtimeKind: .codebuddy
    )

    static let pi = LocalAgentProviderDescriptor(
        providerID: "pi",
        displayName: "Pi Agent",
        baseURL: "local://pi",
        executableNames: ["pi"],
        capabilities: [.agentRuntime],
        supportsImageContextByDefault: false,
        runtimeKind: .pi
    )

    static let enabledRuntimeProviders: [LocalAgentProviderDescriptor] = [
        codex,
        opencode,
        claude,
        codebuddy,
        pi
    ]

    static func localProvider(for idOrType: String) -> LocalAgentProviderDescriptor? {
        enabledRuntimeProviders.first {
            $0.providerID.caseInsensitiveCompare(idOrType) == .orderedSame
        }
    }
}
