import Foundation

protocol AgentRuntimeModelListing: Sendable {
    func listModels(cliPath: String) async -> [String]
}

struct CodexRuntimeModelListProvider: AgentRuntimeModelListing {
    func listModels(cliPath: String) async -> [String] {
        await Task.detached(priority: .utility) {
            Self.listModelsSynchronously(cliPath: cliPath)
        }.value
    }

    private static func listModelsSynchronously(cliPath: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["app-server", "--stdio"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let semaphore = DispatchSemaphore(value: 0)
        let readState = ModelListReadState()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if readState.append(data, parser: parseModelList(from:)) {
                semaphore.signal()
            }
        }

        do {
            try process.run()
        } catch {
            return []
        }
        defer {
            try? stdinPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }

        send(
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": ["name": "VoxFlow", "version": "1"],
                    "capabilities": [String: Any]()
                ]
            ],
            to: stdinPipe
        )
        send(["method": "model/list", "id": 2, "params": [String: Any]()], to: stdinPipe)

        _ = semaphore.wait(timeout: .now() + 6)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        return readState.models
    }

    private static func send(_ object: [String: Any], to pipe: Pipe) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.write(Data([0x0A]))
    }

    static func parseModelList(from data: Data) -> [String]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  object["id"] as? Int == 2,
                  let result = object["result"] as? [String: Any],
                  let models = result["data"] as? [[String: Any]] else {
                continue
            }
            let ids = models.compactMap { model -> String? in
                guard model["hidden"] as? Bool != true else {
                    return nil
                }
                return (model["id"] as? String) ?? (model["model"] as? String)
            }
            return Array(NSOrderedSet(array: ids)) as? [String]
        }
        return nil
    }

    private final class ModelListReadState: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var resolvedModels: [String] = []

        var models: [String] {
            lock.lock()
            defer { lock.unlock() }
            return resolvedModels
        }

        func append(_ data: Data, parser: (Data) -> [String]?) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(data)
            guard let models = parser(buffer) else { return false }
            resolvedModels = models
            return true
        }
    }
}
