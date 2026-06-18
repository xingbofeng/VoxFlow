@testable import VoxFlowProviderQwen3
import Foundation
import XCTest

final class Qwen3MLXRuntimeProvisionerLiveTests: XCTestCase {
    func testConfiguredManagedRuntimeCanBeProvisionedAndPassWorkerHealth() async throws {
        guard ProcessInfo.processInfo.environment["VOICEINPUT_TEST_QWEN3_MLX_RUNTIME_PROVISION"] == "1" else {
            throw XCTSkip(
                "Set VOICEINPUT_TEST_QWEN3_MLX_RUNTIME_PROVISION=1 to install and verify the managed MLX runtime."
            )
        }
        let workerURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowProviderQwen3/Workers/voxflow-qwen3-mlx-worker")
        let layout = Qwen3MLXRuntimeLayout.current()
        let provisioner = Qwen3MLXRuntimeProvisioner(
            layout: layout,
            workerURLProvider: { workerURL }
        )

        let pythonURL = try await provisioner.prepare()

        XCTAssertEqual(pythonURL, layout.pythonExecutableURL)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: pythonURL.path))
        XCTAssertEqual(
            Qwen3MLXWorkerHealthChecker.check(
                launchCommand: Qwen3MLXWorkerExecutableResolver.LaunchCommand(
                    executableURL: pythonURL,
                    arguments: [workerURL.path]
                )
            ),
            .healthy
        )
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
            domain: "Qwen3MLXRuntimeProvisionerLiveTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate repository root."]
        )
    }
}
