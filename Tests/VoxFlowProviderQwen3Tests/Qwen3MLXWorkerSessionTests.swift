@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3MLXWorkerSessionTests: XCTestCase {
    func testBundledMLXWorkerHealthCommandReportsDependencyStateAsJSON() throws {
        let workerURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowProviderQwen3/Workers/voxflow-qwen3-mlx-worker")

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: workerURL.path))

        let process = Process()
        let output = Pipe()
        process.executableURL = workerURL
        process.arguments = ["--health"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let payload = try JSONDecoder().decode(WorkerHealthPayload.self, from: data)
        XCTAssertEqual(payload.type, "health")
        XCTAssertFalse(payload.status.isEmpty)
    }

    func testWorkerLaunchCommandUsesConfiguredPythonInterpreterForScript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qwen3MLXWorkerLaunchTests-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = directory.appendingPathComponent("Test.app", isDirectory: true)
        let resourcesURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workerURL = resourcesURL.appendingPathComponent("voxflow-qwen3-mlx-worker")
        let pythonURL = directory.appendingPathComponent("python3.12")
        try "#!/bin/sh\n".write(to: workerURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: pythonURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workerURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pythonURL.path)

        let command = try Qwen3MLXWorkerExecutableResolver.launchCommand(
            executableName: "voxflow-qwen3-mlx-worker",
            bundle: Bundle(url: bundleURL)!,
            environment: ["VOXFLOW_QWEN3_MLX_PYTHON": pythonURL.path]
        )

        XCTAssertEqual(command.executableURL, pythonURL)
        XCTAssertEqual(command.arguments, [workerURL.path])
    }

    func testLineProtocolEncodesAudioAsBase64Float32AndDecodesPartialResponse() throws {
        let request = Qwen3MLXWorkerRequest.addAudio(
            sessionID: "session-1",
            audio: Qwen3MLXWorkerAudio(samples: [0.25, -0.5], sampleRate: 16_000)
        )

        let data = try Qwen3MLXWorkerLineCodec.encode(request)
        let decoded = try Qwen3MLXWorkerLineCodec.decodeRequest(data)

        XCTAssertEqual(decoded, request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.hasSuffix("\n"))
        XCTAssertTrue(json.contains("\"samplesBase64\""))
        XCTAssertFalse(json.contains("0.25"))

        let response = try Qwen3MLXWorkerLineCodec.decodeResponse(
            Data(#"{"type":"partial","transcript":"你好","isFinal":false}"#.utf8)
        )
        XCTAssertEqual(response, .partial(transcript: "你好", isFinal: false))
    }

    func testSessionStartsAddsAudioFinishesAndCancelsThroughWorkerTransport() async throws {
        let transport = CapturingMLXWorkerTransport(
            responses: [
                .started(sessionID: "session-1"),
                .partial(transcript: "中间文本", isFinal: false),
                .final(transcript: "最终文本"),
                .cancelled,
            ]
        )
        let session = Qwen3MLXWorkerStreamingSession(
            modelURL: URL(fileURLWithPath: "/tmp/qwen17", isDirectory: true),
            languageHint: "zh",
            transport: transport
        )

        let partial = try await session.addAudio([0.25, -0.5])
        let final = try await session.finish()
        await session.cancel()

        XCTAssertEqual(partial, Qwen3StreamingUpdate(transcript: "中间文本", isFinal: false))
        XCTAssertEqual(final, Qwen3StreamingUpdate(transcript: "最终文本", isFinal: true))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0], .start(modelPath: "/tmp/qwen17", languageHint: "zh"))
        XCTAssertEqual(requests[1], .addAudio(
            sessionID: "session-1",
            audio: Qwen3MLXWorkerAudio(samples: [0.25, -0.5], sampleRate: 16_000)
        ))
        XCTAssertEqual(requests[2], .finish(sessionID: "session-1"))
        XCTAssertEqual(requests[3], .cancel(sessionID: "session-1"))
    }

    func testSessionMapsWorkerErrorToProviderError() async throws {
        let transport = CapturingMLXWorkerTransport(
            responses: [
                .started(sessionID: "session-1"),
                .failure(code: "runtime_unsupported", message: "missing mlx")
            ]
        )
        let session = Qwen3MLXWorkerStreamingSession(
            modelURL: URL(fileURLWithPath: "/tmp/qwen17", isDirectory: true),
            languageHint: nil,
            transport: transport
        )

        do {
            _ = try await session.addAudio([0.1])
            XCTFail("Expected worker runtime unsupported error.")
        } catch {
            XCTAssertEqual(error as? Qwen3ProviderError, .runtimeUnsupported("missing mlx"))
        }
    }

    func testProcessTransportTalksToLineDelimitedWorkerExecutable() async throws {
        let executableURL = try makeEchoWorkerExecutable()
        defer { try? FileManager.default.removeItem(at: executableURL.deletingLastPathComponent()) }
        let transport = try Qwen3MLXWorkerProcessTransport(executableURL: executableURL)
        let session = Qwen3MLXWorkerStreamingSession(
            modelURL: URL(fileURLWithPath: "/tmp/qwen17-process", isDirectory: true),
            languageHint: "zh",
            transport: transport
        )

        let partial = try await session.addAudio([0.1, 0.2])
        let final = try await session.finish()
        await session.cancel()

        XCTAssertEqual(partial, Qwen3StreamingUpdate(transcript: "process partial", isFinal: false))
        XCTAssertEqual(final, Qwen3StreamingUpdate(transcript: "process final", isFinal: true))
    }

    func testBundledWorkerUsesMLXAudioAdapterForPartialAndFinalTranscription() throws {
        let fixture = try makeFakeMLXAudioFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let workerURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowProviderQwen3/Workers/voxflow-qwen3-mlx-worker")
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = fixture.pythonURL
        process.arguments = [workerURL.path]
        process.environment = [
            "PYTHONPATH": fixture.pythonPath.path,
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "",
        ]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(
            .start(modelPath: fixture.modelPath.path, languageHint: "zh")
        ))
        let started = try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading))
        guard case .started(let sessionID) = started else {
            return XCTFail("Expected worker started response, got \(started).")
        }

        try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(
            .addAudio(
                sessionID: sessionID,
                audio: Qwen3MLXWorkerAudio(samples: Array(repeating: 0.1, count: 32_000), sampleRate: 16_000)
            )
        ))
        XCTAssertEqual(
            try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading)),
            .partial(transcript: "partial zh", isFinal: false)
        )

        try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(.finish(sessionID: sessionID)))
        XCTAssertEqual(
            try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading)),
            .final(transcript: "final zh")
        )

        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testBundledWorkerMapsMLXAudioModelLoadFailureToModelLoadError() throws {
        let fixture = try makeFakeMLXAudioFixture(loadModelBody: #"raise RuntimeError("bad model")"#)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let workerURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowProviderQwen3/Workers/voxflow-qwen3-mlx-worker")
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = fixture.pythonURL
        process.arguments = [workerURL.path]
        process.environment = [
            "PYTHONPATH": fixture.pythonPath.path,
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "",
        ]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(
            .start(modelPath: fixture.modelPath.path, languageHint: "zh")
        ))

        XCTAssertEqual(
            try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading)),
            .failure(code: "model_load_failed", message: "bad model")
        )
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    func testBundledWorkerReturnsEmptyPartialAndFinalForSilentAudio() throws {
        let fixture = try makeFakeMLXAudioFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let workerURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowProviderQwen3/Workers/voxflow-qwen3-mlx-worker")
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = fixture.pythonURL
        process.arguments = [workerURL.path]
        process.environment = [
            "PYTHONPATH": fixture.pythonPath.path,
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "",
        ]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(
            .start(modelPath: fixture.modelPath.path, languageHint: "zh")
        ))
        let started = try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading))
        guard case .started(let sessionID) = started else {
            return XCTFail("Expected worker started response, got \(started).")
        }
        try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(
            .addAudio(
                sessionID: sessionID,
                audio: Qwen3MLXWorkerAudio(samples: Array(repeating: 0, count: 16_000), sampleRate: 16_000)
            )
        ))
        XCTAssertEqual(
            try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading)),
            .partial(transcript: "", isFinal: false)
        )
        try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(.finish(sessionID: sessionID)))
        XCTAssertEqual(
            try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading)),
            .final(transcript: "")
        )

        try input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    func testBundledWorkerDoesNotRunMLXTranscriptionForHighFrequencyShortAudioChunks() throws {
        let fixture = try makeFakeMLXAudioFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let workerURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowProviderQwen3/Workers/voxflow-qwen3-mlx-worker")
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = fixture.pythonURL
        process.arguments = [workerURL.path]
        process.environment = [
            "PYTHONPATH": fixture.pythonPath.path,
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "",
        ]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(
            .start(modelPath: fixture.modelPath.path, languageHint: "zh")
        ))
        let started = try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading))
        guard case .started(let sessionID) = started else {
            return XCTFail("Expected worker started response, got \(started).")
        }

        for _ in 0..<3 {
            try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(
                .addAudio(
                    sessionID: sessionID,
                    audio: Qwen3MLXWorkerAudio(samples: Array(repeating: 0.1, count: 1_600), sampleRate: 16_000)
                )
            ))
            XCTAssertEqual(
                try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading)),
                .partial(transcript: "", isFinal: false)
            )
        }

        try input.fileHandleForWriting.write(contentsOf: Qwen3MLXWorkerLineCodec.encode(.finish(sessionID: sessionID)))
        XCTAssertEqual(
            try Qwen3MLXWorkerLineCodec.decodeResponse(readLine(from: output.fileHandleForReading)),
            .final(transcript: "partial zh")
        )

        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func makeEchoWorkerExecutable() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qwen3MLXWorkerSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executableURL = directory.appendingPathComponent("worker.py")
        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        for line in sys.stdin:
            request = json.loads(line)
            if request["type"] == "start":
                print(json.dumps({"type": "started", "sessionID": "process-session"}), flush=True)
            elif request["type"] == "add_audio":
                print(json.dumps({"type": "partial", "transcript": "process partial", "isFinal": False}), flush=True)
            elif request["type"] == "finish":
                print(json.dumps({"type": "final", "transcript": "process final"}), flush=True)
            elif request["type"] == "cancel":
                print(json.dumps({"type": "cancelled"}), flush=True)
                break
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        return executableURL
    }

    private func makeFakeMLXAudioFixture(
        loadModelBody: String = #"return {"path": path}"#
    ) throws -> FakeMLXAudioFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qwen3FakeMLXAudio-\(UUID().uuidString)", isDirectory: true)
        let packageURL = directory
            .appendingPathComponent("python", isDirectory: true)
            .appendingPathComponent("mlx_audio", isDirectory: true)
            .appendingPathComponent("stt", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let pythonURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3.12")
        let modelPath = directory.appendingPathComponent("model", isDirectory: true)
        try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)
        try "".write(to: packageURL.deletingLastPathComponent().appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
        try "".write(to: packageURL.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
        try """
        def load_model(path):
            \(loadModelBody)
        """.write(to: packageURL.appendingPathComponent("utils.py"), atomically: true, encoding: .utf8)
        try """
        class Result:
            def __init__(self, text):
                self.text = text

        CALLS = 0

        def generate_transcription(model, audio_path, output_path=None, format="txt", verbose=False, language=None, **kwargs):
            global CALLS
            CALLS += 1
            assert audio_path.endswith(".wav")
            assert output_path is not None
            assert output_path.endswith(".txt")
            assert model["path"].endswith("model")
            suffix = language or "auto"
            if CALLS == 1:
                return Result("partial " + suffix)
            return Result("final " + suffix)
        """.write(to: packageURL.appendingPathComponent("generate.py"), atomically: true, encoding: .utf8)
        return FakeMLXAudioFixture(
            directory: directory,
            pythonURL: pythonURL,
            pythonPath: directory.appendingPathComponent("python", isDirectory: true),
            modelPath: modelPath
        )
    }

    private func readLine(from fileHandle: FileHandle) throws -> Data {
        var data = Data()
        while true {
            let chunk = try fileHandle.read(upToCount: 1) ?? Data()
            if chunk.isEmpty || chunk == Data([0x0A]) {
                return data
            }
            data.append(chunk)
        }
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "Qwen3MLXWorkerSessionTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate repository root."]
        )
    }
}

private struct FakeMLXAudioFixture {
    let directory: URL
    let pythonURL: URL
    let pythonPath: URL
    let modelPath: URL
}

private struct WorkerHealthPayload: Decodable {
    let type: String
    let status: String
}

private actor CapturingMLXWorkerTransport: Qwen3MLXWorkerTransport {
    private(set) var requests: [Qwen3MLXWorkerRequest] = []
    private var responses: [Qwen3MLXWorkerResponse]

    init(responses: [Qwen3MLXWorkerResponse]) {
        self.responses = responses
    }

    func send(_ request: Qwen3MLXWorkerRequest) async throws -> Qwen3MLXWorkerResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw Qwen3ProviderError.preparationFailed("No worker response queued.")
        }
        return responses.removeFirst()
    }

    func close() async {}
}
