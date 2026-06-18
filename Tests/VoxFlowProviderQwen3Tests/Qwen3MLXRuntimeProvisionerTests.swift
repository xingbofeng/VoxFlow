@testable import VoxFlowProviderQwen3
import Foundation
import XCTest

final class Qwen3MLXRuntimeProvisionerTests: XCTestCase {
    func testRuntimeLayoutUsesVersionedApplicationSupportDirectory() {
        let applicationSupportURL = URL(
            fileURLWithPath: "/tmp/Application Support",
            isDirectory: true
        )

        let layout = Qwen3MLXRuntimeLayout(applicationSupportURL: applicationSupportURL)

        XCTAssertEqual(
            layout.rootURL.path,
            "/tmp/Application Support/VoxFlow/Runtimes/Qwen3MLX/0.4.4"
        )
        XCTAssertEqual(
            layout.pythonExecutableURL.path,
            "/tmp/Application Support/VoxFlow/Runtimes/Qwen3MLX/0.4.4/bin/python3"
        )
        XCTAssertEqual(layout.packageRequirement, "mlx-audio==0.4.4")
    }

    func testWorkerLaunchCommandPrefersManagedRuntimePython() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qwen3MLXManagedLaunch-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = directory.appendingPathComponent("Test.app", isDirectory: true)
        let resourcesURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let applicationSupportURL = directory.appendingPathComponent("Application Support", isDirectory: true)
        let layout = Qwen3MLXRuntimeLayout(applicationSupportURL: applicationSupportURL)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: layout.pythonExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let workerURL = resourcesURL.appendingPathComponent("voxflow-qwen3-mlx-worker")
        try "#!/bin/sh\n".write(to: workerURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: layout.pythonExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workerURL.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: layout.pythonExecutableURL.path
        )

        let command = try Qwen3MLXWorkerExecutableResolver.launchCommand(
            executableName: "voxflow-qwen3-mlx-worker",
            bundle: Bundle(url: bundleURL)!,
            managedRuntime: layout,
            environment: [:]
        )

        XCTAssertEqual(command.executableURL, layout.pythonExecutableURL)
        XCTAssertEqual(command.arguments, [workerURL.path])
    }

    func testProvisionerCreatesVenvInstallsPinnedPackageAndWritesMetadataAfterHealthPasses() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qwen3MLXProvisioner-\(UUID().uuidString)", isDirectory: true)
        let layout = Qwen3MLXRuntimeLayout(
            applicationSupportURL: directory.appendingPathComponent("Application Support", isDirectory: true)
        )
        let bootstrapPythonURL = directory.appendingPathComponent("python3.12")
        let workerURL = directory.appendingPathComponent("worker.py")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: bootstrapPythonURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: workerURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bootstrapPythonURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workerURL.path)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = CapturingMLXRuntimeCommandRunner(layout: layout)
        let provisioner = Qwen3MLXRuntimeProvisioner(
            layout: layout,
            commandRunner: runner,
            bootstrapPythonProvider: { bootstrapPythonURL },
            workerURLProvider: { workerURL },
            healthChecker: { _ in .healthy },
            now: { Date(timeIntervalSince1970: 1_718_700_000) }
        )

        let pythonURL = try await provisioner.prepare()

        XCTAssertEqual(pythonURL, layout.pythonExecutableURL)
        let commands = await runner.commands
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0].executableURL, bootstrapPythonURL)
        XCTAssertEqual(commands[0].arguments, ["-m", "venv", layout.rootURL.path])
        XCTAssertEqual(commands[1].executableURL, layout.pythonExecutableURL)
        XCTAssertEqual(
            commands[1].arguments,
            [
                "-m", "pip", "install",
                "--disable-pip-version-check",
                "--no-input",
                "--upgrade",
                "mlx-audio==0.4.4",
            ]
        )
        let metadata = try JSONDecoder().decode(
            Qwen3MLXRuntimeMetadata.self,
            from: Data(contentsOf: layout.metadataURL)
        )
        XCTAssertEqual(metadata.mlxAudioVersion, "0.4.4")
        XCTAssertEqual(metadata.installedAt, Date(timeIntervalSince1970: 1_718_700_000))
    }

    func testProvisionerReusesHealthyManagedRuntimeWithoutRunningInstallCommands() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Qwen3MLXReuse-\(UUID().uuidString)", isDirectory: true)
        let layout = Qwen3MLXRuntimeLayout(applicationSupportURL: directory)
        try FileManager.default.createDirectory(
            at: layout.pythonExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: layout.pythonExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: layout.pythonExecutableURL.path
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = CapturingMLXRuntimeCommandRunner(layout: layout)
        let provisioner = Qwen3MLXRuntimeProvisioner(
            layout: layout,
            commandRunner: runner,
            bootstrapPythonProvider: {
                XCTFail("Healthy managed runtime should not resolve bootstrap Python.")
                return nil
            },
            workerURLProvider: { URL(fileURLWithPath: "/tmp/worker.py") },
            healthChecker: { _ in .healthy }
        )

        let pythonURL = try await provisioner.prepare()

        XCTAssertEqual(pythonURL, layout.pythonExecutableURL)
        let commands = await runner.commands
        XCTAssertTrue(commands.isEmpty)
    }
}

private actor CapturingMLXRuntimeCommandRunner: Qwen3MLXRuntimeCommandRunning {
    private let layout: Qwen3MLXRuntimeLayout
    private(set) var commands: [Qwen3MLXRuntimeCommand] = []

    init(layout: Qwen3MLXRuntimeLayout) {
        self.layout = layout
    }

    func run(_ command: Qwen3MLXRuntimeCommand) async throws -> Qwen3MLXRuntimeCommandResult {
        commands.append(command)
        if command.arguments.prefix(2) == ["-m", "venv"] {
            try FileManager.default.createDirectory(
                at: layout.pythonExecutableURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "#!/bin/sh\n".write(
                to: layout.pythonExecutableURL,
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: layout.pythonExecutableURL.path
            )
        }
        return Qwen3MLXRuntimeCommandResult(status: 0, output: "")
    }
}
