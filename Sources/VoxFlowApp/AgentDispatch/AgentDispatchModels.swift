import Foundation

enum AgentSessionStatus: String, Codable, Equatable, Sendable {
    case active
    case exited
    case stale

    var isDispatchable: Bool {
        self == .active
    }

    var localizedTitle: String {
        switch self {
        case .active: return "在线"
        case .exited: return "已退出"
        case .stale: return "已失效"
        }
    }
}

struct AgentSelfSummary: Codable, Equatable, Sendable {
    let label: String
    let summary: String
    let topics: [String]
    let phase: String
    let expiresAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case label, summary, topics, phase
        case expiresAt = "expires_at"
    }
}

struct AgentProviderReference: Codable, Equatable, Sendable {
    let provider: String
    let kind: String
    let value: String
    let description: String?
}

struct AgentObservedTitle: Codable, Equatable, Sendable {
    let title: String
    let source: String
    let updatedAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case title, source
        case updatedAt = "updated_at"
    }
}

struct AgentDispatchLogEntry: Codable, Equatable, Identifiable, Sendable {
    let agentID: String
    let message: String
    let submitted: Bool
    let failureReason: AgentDispatchFailureReason?
    let providerRefs: [AgentProviderReference]
    let timestamp: TimeInterval

    var id: String { "\(agentID)-\(timestamp)-\(message)" }

    private enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case message, submitted
        case failureReason = "failure_reason"
        case providerRefs = "provider_refs"
        case timestamp
    }
}

struct AgentSessionCard: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let agentID: String
    let wrapperPID: Int?
    let childPID: Int?
    let cli: String
    let command: [String]
    let cwd: String
    let repoRoot: String?
    let repoName: String?
    let branch: String?
    let terminal: String?
    let tty: String?
    let inputChannel: String?
    let status: AgentSessionStatus
    let exitCode: Int?
    let selfSummary: AgentSelfSummary?
    let providerSessionRefs: [AgentProviderReference]
    let observedTitle: AgentObservedTitle?
    let lastDispatchedAt: TimeInterval?
    let mcpInjected: Bool
    let mcpSeenAt: TimeInterval?
    let mcpReportedAt: TimeInterval?
    let mcpConfigPath: String?
    let mcpCommand: String?
    let mcpArgs: [String]
    let mcpLogPath: String?
    let mcpLastRequest: String?
    let mcpLastError: String?
    let startedAt: TimeInterval?
    let updatedAt: TimeInterval?
    private let explicitDisplayName: String?

    var id: String { agentID }
    var currentSelfSummary: AgentSelfSummary? {
        selfSummary.flatMap { $0.expiresAt > Date().timeIntervalSince1970 ? $0 : nil }
    }
    var displayName: String {
        explicitDisplayName
            ?? observedTitle?.title
            ?? currentSelfSummary?.label
            ?? repoName
            ?? cli
    }

    init(
        schemaVersion: Int,
        agentID: String,
        cli: String,
        command: [String],
        cwd: String,
        repoName: String? = nil,
        branch: String? = nil,
        status: AgentSessionStatus,
        displayName: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.agentID = agentID
        wrapperPID = nil
        childPID = nil
        self.cli = cli
        self.command = command
        self.cwd = cwd
        repoRoot = nil
        self.repoName = repoName
        self.branch = branch
        terminal = nil
        tty = nil
        inputChannel = nil
        self.status = status
        exitCode = nil
        selfSummary = nil
        providerSessionRefs = []
        observedTitle = nil
        lastDispatchedAt = nil
        mcpInjected = false
        mcpSeenAt = nil
        mcpReportedAt = nil
        mcpConfigPath = nil
        mcpCommand = nil
        mcpArgs = []
        mcpLogPath = nil
        mcpLastRequest = nil
        mcpLastError = nil
        startedAt = nil
        updatedAt = nil
        explicitDisplayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case agentID = "agent_id"
        case wrapperPID = "wrapper_pid"
        case childPID = "child_pid"
        case cli, command, cwd
        case repoRoot = "repo_root"
        case repoName = "repo_name"
        case branch, terminal, tty
        case inputChannel = "input_channel"
        case status
        case exitCode = "exit_code"
        case selfSummary = "self_summary"
        case providerSessionRefs = "provider_session_refs"
        case observedTitle = "observed_title"
        case lastDispatchedAt = "last_dispatched_at"
        case mcpInjected = "mcp_injected"
        case mcpSeenAt = "mcp_seen_at"
        case mcpReportedAt = "mcp_reported_at"
        case mcpConfigPath = "mcp_config_path"
        case mcpCommand = "mcp_command"
        case mcpArgs = "mcp_args"
        case mcpLogPath = "mcp_log_path"
        case mcpLastRequest = "mcp_last_request"
        case mcpLastError = "mcp_last_error"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        agentID = try container.decode(String.self, forKey: .agentID)
        wrapperPID = try container.decodeIfPresent(Int.self, forKey: .wrapperPID)
        childPID = try container.decodeIfPresent(Int.self, forKey: .childPID)
        cli = try container.decode(String.self, forKey: .cli)
        command = try container.decode([String].self, forKey: .command)
        cwd = try container.decode(String.self, forKey: .cwd)
        repoRoot = try container.decodeIfPresent(String.self, forKey: .repoRoot)
        repoName = try container.decodeIfPresent(String.self, forKey: .repoName)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        terminal = try container.decodeIfPresent(String.self, forKey: .terminal)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        inputChannel = try container.decodeIfPresent(String.self, forKey: .inputChannel)
        status = try container.decode(AgentSessionStatus.self, forKey: .status)
        exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        selfSummary = try container.decodeIfPresent(AgentSelfSummary.self, forKey: .selfSummary)
        providerSessionRefs = try container.decodeIfPresent(
            [AgentProviderReference].self,
            forKey: .providerSessionRefs
        ) ?? []
        observedTitle = try container.decodeIfPresent(AgentObservedTitle.self, forKey: .observedTitle)
        lastDispatchedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .lastDispatchedAt)
        mcpInjected = try container.decodeIfPresent(Bool.self, forKey: .mcpInjected) ?? false
        mcpSeenAt = try container.decodeIfPresent(TimeInterval.self, forKey: .mcpSeenAt)
        mcpReportedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .mcpReportedAt)
        mcpConfigPath = try container.decodeIfPresent(String.self, forKey: .mcpConfigPath)
        mcpCommand = try container.decodeIfPresent(String.self, forKey: .mcpCommand)
        mcpArgs = try container.decodeIfPresent([String].self, forKey: .mcpArgs) ?? []
        mcpLogPath = try container.decodeIfPresent(String.self, forKey: .mcpLogPath)
        mcpLastRequest = try container.decodeIfPresent(String.self, forKey: .mcpLastRequest)
        mcpLastError = try container.decodeIfPresent(String.self, forKey: .mcpLastError)
        startedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .startedAt)
        updatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt)
        explicitDisplayName = nil
    }
}

extension Array where Element == AgentSessionCard {
    var currentDispatchableAgents: [AgentSessionCard] {
        filter(\.status.isDispatchable)
    }
}

enum AgentDispatchFailureReason: String, Codable, Equatable, Sendable {
    case exited
    case stale
    case inputChannelMissing = "input_channel_missing"
    case ambiguous
    case notFound = "not_found"
    case writeFailed = "write_failed"
}

enum AgentResolveOutcome: Equatable, Sendable, Decodable {
    case direct(agentID: String, message: String, matchedBy: String)
    case ambiguous(candidates: [String])
    case notFound
    case invalidMessage
    case unavailable(agentID: String, reason: AgentDispatchFailureReason)

    private enum CodingKeys: String, CodingKey {
        case outcome
        case agentID = "agent_id"
        case message
        case matchedBy = "matched_by"
        case candidates
        case reason
    }

    private enum Kind: String, Decodable {
        case direct, ambiguous
        case notFound = "not_found"
        case invalidMessage = "invalid_message"
        case unavailable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .outcome) {
        case .direct:
            self = .direct(
                agentID: try container.decode(String.self, forKey: .agentID),
                message: try container.decode(String.self, forKey: .message),
                matchedBy: try container.decode(String.self, forKey: .matchedBy)
            )
        case .ambiguous:
            self = .ambiguous(candidates: try container.decode([String].self, forKey: .candidates))
        case .notFound:
            self = .notFound
        case .invalidMessage:
            self = .invalidMessage
        case .unavailable:
            self = .unavailable(
                agentID: try container.decode(String.self, forKey: .agentID),
                reason: try container.decode(AgentDispatchFailureReason.self, forKey: .reason)
            )
        }
    }
}

struct AgentDispatchRequest: Equatable, Sendable {
    let agentID: String
    let message: String
    let submit: Bool
}

struct AgentModelResolution: Equatable, Sendable {
    let agentID: String
    let message: String
    let confidence: Double
}

protocol AgentTargetModelResolving: Sendable {
    func resolve(
        utterance: String,
        candidates: [AgentSessionCard]
    ) async throws -> AgentModelResolution?
}

struct AgentConfirmationIntent: Equatable, Sendable {
    let alias: String?
    let message: String

    static func parse(_ utterance: String) -> AgentConfirmationIntent {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in ["，", ",", "：", ":"] {
            if let range = trimmed.range(of: separator) {
                let target = String(trimmed[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = String(trimmed[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !target.isEmpty, !message.isEmpty {
                    return AgentConfirmationIntent(alias: target, message: message)
                }
            }
        }
        if trimmed.hasPrefix("给"),
           let range = trimmed.range(of: "说") {
            let target = String(trimmed[trimmed.index(after: trimmed.startIndex)..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = String(trimmed[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !target.isEmpty, !message.isEmpty {
                return AgentConfirmationIntent(alias: target, message: message)
            }
        }
        return AgentConfirmationIntent(alias: nil, message: trimmed)
    }
}
