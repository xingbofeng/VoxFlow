import Foundation

public struct Qwen3MLXWorkerAudio: Equatable, Codable, Sendable {
    public let samples: [Float]
    public let sampleRate: Int

    public init(samples: [Float], sampleRate: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

public enum Qwen3MLXWorkerRequest: Equatable, Sendable {
    case start(modelPath: String, languageHint: String?)
    case addAudio(sessionID: String, audio: Qwen3MLXWorkerAudio)
    case finish(sessionID: String)
    case cancel(sessionID: String)
}

public enum Qwen3MLXWorkerResponse: Equatable, Sendable {
    case started(sessionID: String)
    case partial(transcript: String, isFinal: Bool)
    case final(transcript: String)
    case cancelled
    case failure(code: String, message: String)
}

public enum Qwen3MLXWorkerCodecError: Error, Equatable, Sendable {
    case invalidMessageType(String)
    case malformedAudioPayload
}

public enum Qwen3MLXWorkerLineCodec {
    public static func encode(_ request: Qwen3MLXWorkerRequest) throws -> Data {
        var data = try JSONEncoder().encode(SerializableRequest(request))
        data.append(0x0A)
        return data
    }

    public static func decodeRequest(_ data: Data) throws -> Qwen3MLXWorkerRequest {
        try JSONDecoder().decode(SerializableRequest.self, from: data.trimmedLineEnding()).request
    }

    public static func decodeResponse(_ data: Data) throws -> Qwen3MLXWorkerResponse {
        try JSONDecoder().decode(SerializableResponse.self, from: data.trimmedLineEnding()).response
    }
}

public protocol Qwen3MLXWorkerTransport: Sendable {
    func send(_ request: Qwen3MLXWorkerRequest) async throws -> Qwen3MLXWorkerResponse
    func close() async
}

public actor Qwen3MLXWorkerStreamingSession: Qwen3StreamingSession {
    private let modelURL: URL
    private let languageHint: String?
    private let transport: any Qwen3MLXWorkerTransport
    private var sessionID: String?
    private var isCancelled = false

    public init(
        modelURL: URL,
        languageHint: String?,
        transport: any Qwen3MLXWorkerTransport
    ) {
        self.modelURL = modelURL
        self.languageHint = languageHint
        self.transport = transport
    }

    public func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        let id = try await ensureStarted()
        let response = try await transport.send(
            .addAudio(
                sessionID: id,
                audio: Qwen3MLXWorkerAudio(samples: samples, sampleRate: 16_000)
            )
        )
        return try streamingUpdate(from: response)
    }

    public func finish() async throws -> Qwen3StreamingUpdate {
        let id = try await ensureStarted()
        let response = try await transport.send(.finish(sessionID: id))
        switch try streamingUpdate(from: response) {
        case .some(let update):
            return Qwen3StreamingUpdate(transcript: update.transcript, isFinal: true)
        case .none:
            throw Qwen3ProviderError.preparationFailed("Qwen3 MLX worker did not return a final transcript.")
        }
    }

    public func cancel() async {
        isCancelled = true
        if let sessionID {
            _ = try? await transport.send(.cancel(sessionID: sessionID))
        }
        await transport.close()
    }

    private func ensureStarted() async throws -> String {
        if let sessionID {
            return sessionID
        }
        let response = try await transport.send(
            .start(modelPath: modelURL.path, languageHint: languageHint)
        )
        switch response {
        case .started(let id):
            sessionID = id
            return id
        case .failure(let code, let message):
            throw providerError(code: code, message: message)
        case .partial, .final, .cancelled:
            throw Qwen3ProviderError.preparationFailed("Qwen3 MLX worker returned an unexpected start response.")
        }
    }

    private func streamingUpdate(
        from response: Qwen3MLXWorkerResponse
    ) throws -> Qwen3StreamingUpdate? {
        guard !isCancelled else { return nil }
        switch response {
        case .started:
            throw Qwen3ProviderError.preparationFailed("Qwen3 MLX worker returned an unexpected started response.")
        case .partial(let transcript, let isFinal):
            return Qwen3StreamingUpdate(transcript: transcript, isFinal: isFinal)
        case .final(let transcript):
            return Qwen3StreamingUpdate(transcript: transcript, isFinal: true)
        case .cancelled:
            return nil
        case .failure(let code, let message):
            throw providerError(code: code, message: message)
        }
    }

    private func providerError(code: String, message: String) -> Qwen3ProviderError {
        switch code {
        case "runtime_unsupported":
            return .runtimeUnsupported(message)
        case "hardware_unsupported":
            return .hardwareUnsupported(message)
        default:
            return .preparationFailed(message)
        }
    }
}

public struct Qwen3MLXWorkerStreamingSessionFactory: Qwen3StreamingSessionMaking {
    private let launchCommandProvider: @Sendable () throws -> Qwen3MLXWorkerExecutableResolver.LaunchCommand

    public init(
        launchCommandProvider: @escaping @Sendable () throws -> Qwen3MLXWorkerExecutableResolver.LaunchCommand = {
            try Qwen3MLXWorkerExecutableResolver.launchCommand()
        }
    ) {
        self.launchCommandProvider = launchCommandProvider
    }

    public func makeSession(
        modelURL: URL,
        languageHint: String?
    ) async throws -> any Qwen3StreamingSession {
        let launchCommand = try launchCommandProvider()
        let transport = try Qwen3MLXWorkerProcessTransport(launchCommand: launchCommand)
        return Qwen3MLXWorkerStreamingSession(
            modelURL: modelURL,
            languageHint: languageHint,
            transport: transport
        )
    }
}

public enum Qwen3StreamingSessionFactoryProvider {
    public static func factory(for variant: Qwen3ModelVariant) -> any Qwen3StreamingSessionMaking {
        switch variant {
        case .qwen06CoreMLInt8:
            return FluidAudioQwen3StreamingSessionFactory()
        case .qwen17MLX4Bit:
            return Qwen3MLXWorkerStreamingSessionFactory()
        }
    }
}

public enum Qwen3MLXWorkerExecutableResolver {
    public struct LaunchCommand: Equatable, Sendable {
        public let executableURL: URL
        public let arguments: [String]

        public init(executableURL: URL, arguments: [String]) {
            self.executableURL = executableURL
            self.arguments = arguments
        }
    }

    public static func resolve(
        executableName: String = "voxflow-qwen3-mlx-worker",
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> URL {
        let candidates = [
            bundle.bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS")
                .appendingPathComponent(executableName),
            bundle.bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Resources")
                .appendingPathComponent(executableName),
        ]
        if let executableURL = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return executableURL
        }
        throw Qwen3ProviderError.runtimeUnsupported(
            "Qwen3-ASR 1.7B 需要 MLX 本地 worker：\(executableName)。"
        )
    }

    public static func launchCommand(
        executableName: String = "voxflow-qwen3-mlx-worker",
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        managedRuntime: Qwen3MLXRuntimeLayout? = .current(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LaunchCommand {
        let workerURL = try resolve(
            executableName: executableName,
            bundle: bundle,
            fileManager: fileManager
        )
        if let configuredPython = environment["VOXFLOW_QWEN3_MLX_PYTHON"],
           fileManager.isExecutableFile(atPath: configuredPython) {
            return LaunchCommand(
                executableURL: URL(fileURLWithPath: configuredPython),
                arguments: [workerURL.path]
            )
        }
        if let managedRuntime,
           fileManager.isExecutableFile(atPath: managedRuntime.pythonExecutableURL.path) {
            return LaunchCommand(
                executableURL: managedRuntime.pythonExecutableURL,
                arguments: [workerURL.path]
            )
        }
        for candidate in pythonInterpreterCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return LaunchCommand(
                executableURL: URL(fileURLWithPath: candidate),
                arguments: [workerURL.path]
            )
        }
        return LaunchCommand(executableURL: workerURL, arguments: [])
    }

    private static let pythonInterpreterCandidates = [
        "/opt/homebrew/bin/python3.12",
        "/opt/homebrew/bin/python3.11",
        "/usr/local/bin/python3.12",
        "/usr/local/bin/python3.11",
        "/usr/bin/python3",
    ]
}

public actor Qwen3MLXWorkerProcessTransport: Qwen3MLXWorkerTransport {
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private var readBuffer = Data()

    public init(executableURL: URL) throws {
        try self.init(
            launchCommand: Qwen3MLXWorkerExecutableResolver.LaunchCommand(
                executableURL: executableURL,
                arguments: []
            )
        )
    }

    public init(launchCommand: Qwen3MLXWorkerExecutableResolver.LaunchCommand) throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = launchCommand.executableURL
        process.arguments = launchCommand.arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        self.process = process
        self.input = inputPipe.fileHandleForWriting
        self.output = outputPipe.fileHandleForReading
    }

    public func send(_ request: Qwen3MLXWorkerRequest) async throws -> Qwen3MLXWorkerResponse {
        let requestData = try Qwen3MLXWorkerLineCodec.encode(request)
        try input.write(contentsOf: requestData)
        let responseData = try readLine()
        return try Qwen3MLXWorkerLineCodec.decodeResponse(responseData)
    }

    public func close() async {
        try? input.close()
        try? output.close()
        if process.isRunning {
            process.terminate()
        }
    }

    private func readLine() throws -> Data {
        while true {
            if let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
                let line = readBuffer[..<newlineIndex]
                readBuffer.removeSubrange(...newlineIndex)
                return Data(line)
            }
            let chunk = try output.read(upToCount: 1) ?? Data()
            guard !chunk.isEmpty else {
                throw Qwen3ProviderError.preparationFailed("Qwen3 MLX worker closed stdout.")
            }
            readBuffer.append(chunk)
        }
    }
}

private struct SerializableRequest: Codable {
    let type: String
    let modelPath: String?
    let languageHint: String?
    let sessionID: String?
    let audio: SerializableAudio?

    init(_ request: Qwen3MLXWorkerRequest) throws {
        switch request {
        case .start(let modelPath, let languageHint):
            self.type = "start"
            self.modelPath = modelPath
            self.languageHint = languageHint
            self.sessionID = nil
            self.audio = nil
        case .addAudio(let sessionID, let audio):
            self.type = "add_audio"
            self.modelPath = nil
            self.languageHint = nil
            self.sessionID = sessionID
            self.audio = try SerializableAudio(audio)
        case .finish(let sessionID):
            self.type = "finish"
            self.modelPath = nil
            self.languageHint = nil
            self.sessionID = sessionID
            self.audio = nil
        case .cancel(let sessionID):
            self.type = "cancel"
            self.modelPath = nil
            self.languageHint = nil
            self.sessionID = sessionID
            self.audio = nil
        }
    }

    var request: Qwen3MLXWorkerRequest {
        get throws {
            switch type {
            case "start":
                return .start(modelPath: modelPath ?? "", languageHint: languageHint)
            case "add_audio":
                guard let sessionID, let audio else {
                    throw Qwen3MLXWorkerCodecError.malformedAudioPayload
                }
                return try .addAudio(sessionID: sessionID, audio: audio.audio)
            case "finish":
                return .finish(sessionID: sessionID ?? "")
            case "cancel":
                return .cancel(sessionID: sessionID ?? "")
            default:
                throw Qwen3MLXWorkerCodecError.invalidMessageType(type)
            }
        }
    }
}

private struct SerializableAudio: Codable, Equatable {
    let samplesBase64: String
    let sampleRate: Int

    init(_ audio: Qwen3MLXWorkerAudio) throws {
        self.samplesBase64 = audio.samples.float32LittleEndianData().base64EncodedString()
        self.sampleRate = audio.sampleRate
    }

    var audio: Qwen3MLXWorkerAudio {
        get throws {
            guard let data = Data(base64Encoded: samplesBase64) else {
                throw Qwen3MLXWorkerCodecError.malformedAudioPayload
            }
            return Qwen3MLXWorkerAudio(
                samples: try data.float32LittleEndianSamples(),
                sampleRate: sampleRate
            )
        }
    }
}

private struct SerializableResponse: Codable {
    let type: String
    let sessionID: String?
    let transcript: String?
    let isFinal: Bool?
    let code: String?
    let message: String?

    var response: Qwen3MLXWorkerResponse {
        get throws {
            switch type {
            case "started":
                return .started(sessionID: sessionID ?? "")
            case "partial":
                return .partial(transcript: transcript ?? "", isFinal: isFinal ?? false)
            case "final":
                return .final(transcript: transcript ?? "")
            case "cancelled":
                return .cancelled
            case "error":
                return .failure(code: code ?? "error", message: message ?? "Qwen3 MLX worker failed.")
            default:
                throw Qwen3MLXWorkerCodecError.invalidMessageType(type)
            }
        }
    }
}

private extension Data {
    func trimmedLineEnding() -> Data {
        guard last == 0x0A else { return self }
        return dropLast()
    }

    func float32LittleEndianSamples() throws -> [Float] {
        guard count.isMultiple(of: MemoryLayout<UInt32>.size) else {
            throw Qwen3MLXWorkerCodecError.malformedAudioPayload
        }
        return stride(from: 0, to: count, by: MemoryLayout<UInt32>.size).map { offset in
            let bits = withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
            return Float(bitPattern: bits)
        }
    }
}

private extension Array where Element == Float {
    func float32LittleEndianData() -> Data {
        var data = Data()
        data.reserveCapacity(count * MemoryLayout<UInt32>.size)
        for sample in self {
            var bits = sample.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }
}
