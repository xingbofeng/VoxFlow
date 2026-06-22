import Darwin
import Foundation

private let agentRouterMaximumRequestBytes = 1_048_576

protocol AgentRouterTransport: Sendable {
    func send(_ data: Data) async throws -> Data
}

final class AgentRouterClient: AgentRouting, @unchecked Sendable {
    private let transport: any AgentRouterTransport
    private let timeoutNanoseconds: UInt64
    private let lock = NSLock()
    private var nextID = 1

    init(
        transport: any AgentRouterTransport,
        timeoutNanoseconds: UInt64 = 1_500_000_000
    ) {
        self.transport = transport
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    convenience init(socketURL: URL) {
        self.init(transport: UnixAgentRouterTransport(socketURL: socketURL))
    }

    func listAgents() async throws -> [AgentSessionCard] {
        try await request(method: "list_agents", params: ["include_inactive": false])
    }

    func listAllAgents() async throws -> [AgentSessionCard] {
        try await request(method: "list_agents", params: ["include_inactive": true])
    }

    func resolve(utterance: String) async throws -> AgentResolveOutcome {
        try await request(method: "resolve_agent", params: ["utterance": utterance])
    }

    func send(_ request: AgentDispatchRequest) async throws {
        let _: AgentRouterMutationResult = try await self.request(
            method: "send_message",
            params: [
                "agent_id": request.agentID,
                "message": request.message,
                "submit": request.submit,
            ]
        )
    }

    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws {
        let _: AgentRouterMutationResult = try await request(
            method: "learn_alias",
            params: [
                "alias": alias,
                "agent_id": agentID,
                "user_confirmed": userConfirmed,
            ]
        )
    }

    func listAliases() async throws -> [String: String] {
        try await request(method: "list_aliases", params: [:])
    }

    func removeAlias(_ alias: String) async throws {
        let _: AgentRouterMutationResult = try await request(
            method: "remove_alias",
            params: ["alias": alias]
        )
    }

    func listDispatchLog(limit: Int = 30) async throws -> [AgentDispatchLogEntry] {
        try await request(method: "list_dispatch_log", params: ["limit": limit])
    }

    func clearDispatchLog() async throws {
        let _: AgentRouterClearDispatchLogResult = try await request(method: "clear_dispatch_log", params: [:])
    }

    func cleanStaleSessions() async throws {
        let _: AgentRouterCleanResult = try await request(method: "clean_stale", params: [:])
    }

    func cleanInactiveSessions() async throws {
        let _: AgentRouterCleanResult = try await request(method: "clean_inactive", params: [:])
    }

    func terminateAgent(agentID: String) async throws {
        let _: AgentRouterTerminateResult = try await request(
            method: "terminate_agent",
            params: ["agent_id": agentID]
        )
    }

    private func request<Result: Decodable>(
        method: String,
        params: [String: Any]
    ) async throws -> Result {
        let id: Int = lock.withLock {
            defer { nextID += 1 }
            return nextID
        }
        AppLogger.network.debug("AgentRouterClient request start method=\(method) id=\(id) paramsCount=\(params.count)")
        let payload: [String: Any] = [
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard data.count <= agentRouterMaximumRequestBytes else {
            AppLogger.network.warning("AgentRouterClient request too large method=\(method) id=\(id) bytes=\(data.count)")
            throw AgentRouterClientError.requestTooLarge
        }
        let response = try await withRequestTimeout {
            try await self.transport.send(data)
        }
        AppLogger.network.debug("AgentRouterClient request response method=\(method) id=\(id) bytes=\(response.count)")
        let envelope = try JSONDecoder().decode(AgentRouterEnvelope<Result>.self, from: response)
        if let error = envelope.error {
            AppLogger.network.warning("AgentRouterClient request failed method=\(method) id=\(id) reason=\(error.message)")
            throw AgentRouterClientError.router(error.message)
        }
        guard let result = envelope.result else {
            AppLogger.network.error("AgentRouterClient request missing result method=\(method) id=\(id)")
            throw AgentRouterClientError.invalidResponse
        }
        AppLogger.network.debug("AgentRouterClient request success method=\(method) id=\(id)")
        return result
    }

    private func withRequestTimeout<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        try await withThrowingTaskGroup(of: Result.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask { [timeoutNanoseconds] in
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                AppLogger.network.warning("AgentRouterClient request timeout nanos=\(timeoutNanoseconds)")
                throw AgentRouterClientError.timeout
            }
            guard let result = try await group.next() else {
                throw AgentRouterClientError.invalidResponse
            }
            group.cancelAll()
            return result
        }
    }
}

private struct AgentRouterEnvelope<Result: Decodable>: Decodable {
    let result: Result?
    let error: AgentRouterRemoteError?
}

private struct AgentRouterRemoteError: Decodable {
    let message: String
}

private struct AgentRouterMutationResult: Decodable {
    let submitted: Bool?
    let saved: Bool?
    let removed: Bool?
}

private struct AgentRouterCleanResult: Decodable {
    let removed: Int
}

private struct AgentRouterTerminateResult: Decodable {
    let terminated: Bool
}

private struct AgentRouterClearDispatchLogResult: Decodable {
    let cleared: Bool
}

final class UnixAgentRouterTransport: AgentRouterTransport, @unchecked Sendable {
    private let socketPath: String

    init(socketURL: URL) {
        socketPath = socketURL.path
    }

    func send(_ data: Data) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try self.sendSynchronously(data)
        }.value
    }

    private func sendSynchronously(_ data: Data) throws -> Data {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            AppLogger.network.error("AgentRouterTransport failed create unix socket")
            throw POSIXError(.ENOTCONN)
        }
        defer { close(descriptor) }
        try configureTimeouts(for: descriptor)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            AppLogger.network.error("AgentRouterTransport socket path too long path=\(socketPath)")
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: pathBytes)
        }
        AppLogger.network.debug("AgentRouterTransport connect socket path=\(socketPath)")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            AppLogger.network.error("AgentRouterTransport connect failed descriptor=\(descriptor) errno=\(errno)")
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOTCONN)
        }

        var request = data
        request.append(0x0A)
        try request.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(
                    descriptor,
                    buffer.baseAddress!.advanced(by: offset),
                    buffer.count - offset
                )
                guard written > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += written
            }
        }

        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.read(descriptor, &chunk, chunk.count)
            guard count >= 0 else {
                AppLogger.network.error("AgentRouterTransport read failed descriptor=\(descriptor) errno=\(errno)")
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            response.append(contentsOf: chunk.prefix(count))
            if response.last == 0x0A { break }
        }
        guard !response.isEmpty else {
            AppLogger.network.warning("AgentRouterTransport empty response socket=\(socketPath)")
            throw AgentRouterClientError.invalidResponse
        }
        if response.last == 0x0A { response.removeLast() }
        AppLogger.network.debug("AgentRouterTransport response length=\(response.count)")
        return response
    }

    private func configureTimeouts(for descriptor: Int32) throws {
        var timeout = timeval(tv_sec: 1, tv_usec: 500_000)
        let size = socklen_t(MemoryLayout<timeval>.size)
        let sendResult = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, size)
        guard sendResult == 0 else {
            AppLogger.network.warning("AgentRouterTransport configure send timeout failed descriptor=\(descriptor)")
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let receiveResult = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, size)
        guard receiveResult == 0 else {
            AppLogger.network.warning("AgentRouterTransport configure receive timeout failed descriptor=\(descriptor)")
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        AppLogger.network.debug("AgentRouterTransport timeouts configured descriptor=\(descriptor)")
    }
}
