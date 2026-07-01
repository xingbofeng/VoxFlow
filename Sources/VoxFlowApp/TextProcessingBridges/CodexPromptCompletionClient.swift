import Foundation

protocol CodexPromptCompleting: Sendable {
    var isAvailable: Bool { get }
    func complete(prompt: String, model: String?, timeoutSeconds: Double) async throws -> String
}

struct CodexPromptCompletionClient: CodexPromptCompleting {
    private let cliPaths: [String]

    init(
        cliPaths: [String] = CodexRuntimeDetectorConfiguration.default.candidateCLIPaths
    ) {
        self.cliPaths = cliPaths
    }

    var isAvailable: Bool {
        cliPath != nil
    }

    func complete(prompt: String, model: String?, timeoutSeconds: Double) async throws -> String {
        guard let cliPath else {
            throw LLMRefiner.Error.notConfigured
        }
        return try await Task.detached(priority: .userInitiated) {
            try runCodexExec(
                cliPath: cliPath,
                prompt: prompt,
                model: model,
                timeoutSeconds: timeoutSeconds
            )
        }.value
    }

    private var cliPath: String? {
        cliPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func execArguments(
        workdir: String,
        outputPath: String,
        model: String?
    ) -> [String] {
        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "--sandbox",
            "read-only",
            "--cd",
            workdir,
            "--output-last-message",
            outputPath,
        ]
        if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        arguments.append("-")
        return arguments
    }
}

private func runCodexExec(
    cliPath: String,
    prompt: String,
    model: String?,
    timeoutSeconds: Double
) throws -> String {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("VoxFlowCodexPrompt-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let outputURL = root.appendingPathComponent("last-message.txt", isDirectory: false)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cliPath)
    process.arguments = CodexPromptCompletionClient.execArguments(
        workdir: root.path,
        outputPath: outputURL.path,
        model: model
    )

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    if let data = prompt.data(using: .utf8) {
        stdinPipe.fileHandleForWriting.write(data)
    }
    try? stdinPipe.fileHandleForWriting.close()

    let deadline = Date().addingTimeInterval(max(1, timeoutSeconds))
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()
        throw LLMRefiner.Error.httpError(code: 408)
    }

    let stdout = String(
        data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    let stderr = String(
        data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""

    guard process.terminationStatus == 0 else {
        throw LLMRefiner.Error.apiError(
            code: Int(process.terminationStatus),
            message: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    let fileOutput = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
    let output = fileOutput.isEmpty ? stdout : fileOutput
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw LLMRefiner.Error.invalidResponse
    }
    return trimmed
}
