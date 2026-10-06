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
        // 读端必须与子进程并发排空：管道缓冲约 64KB，不读会把写满的子进程卡死。
        // readDataToEndOfFile 只在 EOF 返回，EOF 即输出完整，
        // 消除退出瞬间 readabilityHandler 已取走数据但尚未落账的竞态。
        let drained = DispatchGroup()
        let stdoutReader = OutputPipeReader(
            handle: stdoutPipe.fileHandleForReading,
            accumulator: stdoutAccumulator,
            finished: drained
        )
        let stderrReader = OutputPipeReader(
            handle: stderrPipe.fileHandleForReading,
            accumulator: stderrAccumulator,
            finished: drained
        )
        drained.enter()
        DispatchQueue.global().async { stdoutReader.drainToEndOfFile() }
        drained.enter()
        DispatchQueue.global().async { stderrReader.drainToEndOfFile() }
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

        do {
            try process.run()
        } catch {
            // 读者线程仍在等 EOF；关闭父进程写端让其立即返回，再抛出原始错误。
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            _ = drained.wait(timeout: .now() + 2)
            throw error
        }
        // 父进程写端必须在 spawn 成功后关闭：所有写端都关闭，读端才会见到 EOF。
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
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

        // 正常情况下子进程退出后读端立即 EOF；超时只兜底孙进程继承写端的病态场景，
        // 此时按锁保护下已落账的部分输出返回，不让调用方挂死。
        _ = drained.wait(timeout: .now() + 5)

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

/// 阻塞读一个子进程输出管道到 EOF；必须跑在后台队列，读到 EOF 前不会返回。
/// `@unchecked Sendable`：FileHandle 与 DispatchGroup 自身线程安全，
/// @Sendable 闭包只捕获本类型实例。
private final class OutputPipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let accumulator: DataAccumulator
    private let finished: DispatchGroup

    init(handle: FileHandle, accumulator: DataAccumulator, finished: DispatchGroup) {
        self.handle = handle
        self.accumulator = accumulator
        self.finished = finished
    }

    func drainToEndOfFile() {
        accumulator.append(handle.readDataToEndOfFile())
        finished.leave()
    }
}
