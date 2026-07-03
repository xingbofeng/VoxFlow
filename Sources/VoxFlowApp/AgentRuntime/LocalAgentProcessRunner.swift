import Darwin
import Foundation

struct LocalAgentProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

enum LocalAgentProcessRunner {
    static func run(
        _ launchPath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        stdin: String? = nil,
        cwd: String? = nil,
        timeoutSeconds: Double? = nil
    ) throws -> LocalAgentProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = environmentWithStablePath(environment)
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutAccumulator = DataAccumulator()
        let stderrAccumulator = DataAccumulator()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutAccumulator.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrAccumulator.append(data)
            }
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe?
        if stdin != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            stdinPipe = pipe
        } else {
            stdinPipe = nil
        }

        try process.run()
        let processGroupCreated = setpgid(process.processIdentifier, process.processIdentifier) == 0
        if let stdinPipe {
            if let data = stdin?.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            try? stdinPipe.fileHandleForWriting.close()
        }

        let timedOut = waitForExit(process, timeoutSeconds: timeoutSeconds)
        if timedOut {
            terminateProcessTree(rootPID: process.processIdentifier, signal: SIGTERM, usesProcessGroup: processGroupCreated)
            if waitForExit(process, timeoutSeconds: 1) {
                terminateProcessTree(rootPID: process.processIdentifier, signal: SIGKILL, usesProcessGroup: processGroupCreated)
                process.waitUntilExit()
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutAccumulator.append(stdoutPipe.fileHandleForReading.availableData)
        stderrAccumulator.append(stderrPipe.fileHandleForReading.availableData)

        return LocalAgentProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutAccumulator.stringValue(),
            stderr: stderrAccumulator.stringValue(),
            timedOut: timedOut
        )
    }

    private static func waitForExit(_ process: Process, timeoutSeconds: Double?) -> Bool {
        guard let timeoutSeconds else {
            process.waitUntilExit()
            return false
        }
        let deadline = Date().addingTimeInterval(max(1, timeoutSeconds))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return process.isRunning
    }

    private static func terminateProcessTree(rootPID: Int32, signal: Int32, usesProcessGroup: Bool) {
        if usesProcessGroup {
            kill(-rootPID, signal)
        }
        for childPID in childProcessIDs(of: rootPID).reversed() {
            kill(childPID, signal)
        }
        kill(rootPID, signal)
    }

    private static func childProcessIDs(of parentPID: Int32) -> [Int32] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", String(parentPID)]
        let output = Pipe()
        pgrep.standardOutput = output
        pgrep.standardError = Pipe()
        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let directChildren = text
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int32($0) }
        return directChildren + directChildren.flatMap { childProcessIDs(of: $0) }
    }

    private static func environmentWithStablePath(_ environment: [String: String]?) -> [String: String] {
        var resolved = environment ?? ProcessInfo.processInfo.environment
        let fallbackDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let existingPath = resolved["PATH"] ?? ""
        var directories = existingPath
            .split(separator: ":")
            .map(String.init)
        for directory in fallbackDirectories where !directories.contains(directory) {
            directories.append(directory)
        }
        resolved["PATH"] = directories.joined(separator: ":")
        return resolved
    }
}

private final class DataAccumulator: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func stringValue() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}
