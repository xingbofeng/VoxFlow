@testable import VoxFlowProviderQwen3
import Foundation
import XCTest

final class Qwen3ModelReadinessRunnerLiveTests: XCTestCase {
    func testConfiguredQwen17ModelPassesManagedRuntimePrewarmAndCanary() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["VOICEINPUT_TEST_QWEN3_17_READINESS"] == "1" else {
            throw XCTSkip(
                "Set VOICEINPUT_TEST_QWEN3_17_READINESS=1 and VOICEINPUT_TEST_QWEN3_MODEL_PATH to run the 1.7B readiness smoke."
            )
        }
        guard let modelPath = environment["VOICEINPUT_TEST_QWEN3_MODEL_PATH"],
              !modelPath.isEmpty else {
            throw XCTSkip("Set VOICEINPUT_TEST_QWEN3_MODEL_PATH to the Qwen3-ASR 1.7B ModelStore directory.")
        }
        let workerURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowProviderQwen3/Workers/voxflow-qwen3-mlx-worker")
        let layout = Qwen3MLXRuntimeLayout.current()
        let sessionFactory = Qwen3MLXWorkerStreamingSessionFactory(
            launchCommandProvider: {
                Qwen3MLXWorkerExecutableResolver.LaunchCommand(
                    executableURL: layout.pythonExecutableURL,
                    arguments: [workerURL.path]
                )
            }
        )
        let runner = Qwen3ModelReadinessRunner(
            runtimeFactory: { _, variant in
                XCTAssertEqual(variant, .qwen17MLX4Bit)
                return Qwen3ModelRuntimePreparer(
                    sessionFactory: sessionFactory,
                    languageHint: "zh"
                )
            }
        )

        let report = try await runner.prepare(
            modelURL: URL(fileURLWithPath: modelPath, isDirectory: true),
            variant: .qwen17MLX4Bit
        )

        XCTAssertTrue(report.isReady)
        XCTAssertFalse(report.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("Package.swift").path
            ) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "Qwen3ModelReadinessRunnerLiveTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate repository root."]
        )
    }
}
