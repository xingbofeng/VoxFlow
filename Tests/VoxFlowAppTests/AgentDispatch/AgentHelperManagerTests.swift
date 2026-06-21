import XCTest
@testable import VoxFlowApp

@MainActor
final class AgentHelperManagerTests: XCTestCase {
    func testHealthDecisionStartsMissingRouterAndKeepsHealthyRouter() {
        XCTAssertEqual(AgentHelperManager.healthDecision(processRunning: false, socketReachable: false), .start)
        XCTAssertEqual(AgentHelperManager.healthDecision(processRunning: false, socketReachable: true), .keep)
        XCTAssertEqual(AgentHelperManager.healthDecision(processRunning: true, socketReachable: true), .keep)
        XCTAssertEqual(AgentHelperManager.healthDecision(processRunning: true, socketReachable: false), .restart)
    }

    func testCLIRegistrationPlanContainsThreeDocumentedCommands() {
        let plan = AgentHelperManager.registrationPlan(
            helperURL: URL(fileURLWithPath: "/Applications/VoxFlow.app/Contents/Helpers/voxflow"),
            binDirectory: URL(fileURLWithPath: "/tmp/VoxFlow/bin")
        )
        XCTAssertEqual(plan.examples, ["vox flow codex", "vox flow --claude", "vox flow --codebuddy"])
        XCTAssertEqual(plan.voxflowDestination.lastPathComponent, "voxflow")
        XCTAssertEqual(plan.voxDestination.lastPathComponent, "vox")
    }

    func testCLIRegistrationPreviewShowsProfilePathAndManagedPathBlock() {
        let home = URL(fileURLWithPath: "/Users/example")
        let preview = AgentHelperManager.registrationPreview(
            homeDirectory: home,
            shellURL: URL(fileURLWithPath: "/bin/zsh")
        )

        XCTAssertEqual(preview.profileURL.path, "/Users/example/.zprofile")
        XCTAssertEqual(preview.shellBlock, "# VoxFlow CLI\nexport PATH=\"$HOME/.local/bin:$PATH\"")
    }

    func testRegisterCLIInstallsExecutableAndShimIntoApplicationSupportBin() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let bundleURL = temporaryRoot.appendingPathComponent("VoxFlow.app", isDirectory: true)
        let helpersURL = bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(
            at: helpersURL,
            withIntermediateDirectories: true
        )
        let helperURL = helpersURL.appendingPathComponent("voxflow")
        try Data("helper".utf8).write(to: helperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: helperURL.path
        )
        try FileManager.default.createSymbolicLink(
            atPath: helpersURL.appendingPathComponent("vox").path,
            withDestinationPath: "voxflow"
        )
        let paths = ApplicationSupportPaths(
            applicationSupportDirectory: temporaryRoot.appendingPathComponent("Support")
        )
        let manager = AgentHelperManager(
            paths: paths,
            bundleURL: bundleURL,
            homeDirectory: temporaryRoot.appendingPathComponent("Home", isDirectory: true)
        )

        let status = try manager.registerCLI()

        XCTAssertTrue(FileManager.default.isExecutableFile(
            atPath: paths.cliBinDirectory.appendingPathComponent("voxflow").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: paths.cliBinDirectory.appendingPathComponent("vox").path
        ))
        XCTAssertEqual(status.examples, [
            "vox flow codex",
            "vox flow --claude",
            "vox flow --codebuddy",
        ])
    }

    func testRegisterCLIExposesCommandsInUserLocalBinAndConfiguresZshPathIdempotently() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let bundleURL = temporaryRoot.appendingPathComponent("VoxFlow.app", isDirectory: true)
        let helpersURL = bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpersURL, withIntermediateDirectories: true)
        let helperURL = helpersURL.appendingPathComponent("voxflow")
        try Data("helper".utf8).write(to: helperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: helperURL.path
        )
        try FileManager.default.createSymbolicLink(
            atPath: helpersURL.appendingPathComponent("vox").path,
            withDestinationPath: "voxflow"
        )
        let homeDirectory = temporaryRoot.appendingPathComponent("Home", isDirectory: true)
        let paths = ApplicationSupportPaths(
            applicationSupportDirectory: temporaryRoot.appendingPathComponent("Support")
        )
        let manager = AgentHelperManager(
            paths: paths,
            bundleURL: bundleURL,
            homeDirectory: homeDirectory,
            shellURL: URL(fileURLWithPath: "/bin/zsh")
        )

        let firstStatus = try manager.registerCLI()
        let secondStatus = try manager.registerCLI()

        let commandDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        XCTAssertEqual(firstStatus.binDirectory, commandDirectory)
        XCTAssertEqual(secondStatus.binDirectory, commandDirectory)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: commandDirectory.appendingPathComponent("voxflow").path
            ),
            paths.cliBinDirectory.appendingPathComponent("voxflow").path
        )
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: commandDirectory.appendingPathComponent("vox").path
            ),
            paths.cliBinDirectory.appendingPathComponent("vox").path
        )
        let profile = try String(
            contentsOf: homeDirectory.appendingPathComponent(".zprofile"),
            encoding: .utf8
        )
        XCTAssertEqual(profile.components(separatedBy: "# VoxFlow CLI").count - 1, 1)
        XCTAssertTrue(profile.contains("export PATH=\"$HOME/.local/bin:$PATH\""))
    }

    func testRegisterCLIBacksUpProfileBeforeWritingPathBlock() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let bundleURL = try makeBundleWithAgentHelpers(at: temporaryRoot)
        let homeDirectory = temporaryRoot.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        let profileURL = homeDirectory.appendingPathComponent(".zprofile")
        try "export EXISTING=1\n".write(to: profileURL, atomically: true, encoding: .utf8)
        let paths = ApplicationSupportPaths(
            applicationSupportDirectory: temporaryRoot.appendingPathComponent("Support")
        )
        let manager = AgentHelperManager(
            paths: paths,
            bundleURL: bundleURL,
            homeDirectory: homeDirectory,
            shellURL: URL(fileURLWithPath: "/bin/zsh")
        )

        try manager.registerCLI()

        let backup = homeDirectory.appendingPathComponent(".zprofile.voxflow.bak")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "export EXISTING=1\n")
    }

    func testUnregisterCLIRemovesManagedLinksAndPathBlockButKeepsUserContent() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let bundleURL = try makeBundleWithAgentHelpers(at: temporaryRoot)
        let homeDirectory = temporaryRoot.appendingPathComponent("Home", isDirectory: true)
        let paths = ApplicationSupportPaths(
            applicationSupportDirectory: temporaryRoot.appendingPathComponent("Support")
        )
        let manager = AgentHelperManager(
            paths: paths,
            bundleURL: bundleURL,
            homeDirectory: homeDirectory,
            shellURL: URL(fileURLWithPath: "/bin/zsh")
        )
        try manager.registerCLI()
        let commandDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        let userCommand = commandDirectory.appendingPathComponent("vf-user")
        try "custom".write(to: userCommand, atomically: true, encoding: .utf8)

        try manager.unregisterCLI()

        XCTAssertFalse(FileManager.default.fileExists(atPath: commandDirectory.appendingPathComponent("voxflow").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: commandDirectory.appendingPathComponent("vox").path))
        XCTAssertEqual(try String(contentsOf: userCommand, encoding: .utf8), "custom")
        let profile = try String(contentsOf: homeDirectory.appendingPathComponent(".zprofile"), encoding: .utf8)
        XCTAssertFalse(profile.contains("# VoxFlow CLI"))
        XCTAssertFalse(profile.contains(".local/bin"))
    }

    func testRegisterCLIReplacesBrokenCommandLinksWithoutOverwritingExistingCommands() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let bundleURL = temporaryRoot.appendingPathComponent("VoxFlow.app", isDirectory: true)
        let helpersURL = bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpersURL, withIntermediateDirectories: true)
        let helperURL = helpersURL.appendingPathComponent("voxflow")
        try Data("helper".utf8).write(to: helperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: helperURL.path
        )
        try FileManager.default.createSymbolicLink(
            atPath: helpersURL.appendingPathComponent("vox").path,
            withDestinationPath: "voxflow"
        )
        let homeDirectory = temporaryRoot.appendingPathComponent("Home", isDirectory: true)
        let commandDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: commandDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: commandDirectory.appendingPathComponent("voxflow").path,
            withDestinationPath: temporaryRoot.appendingPathComponent("missing/voxflow").path
        )
        let existingVox = commandDirectory.appendingPathComponent("vox")
        try Data("existing".utf8).write(to: existingVox)
        let paths = ApplicationSupportPaths(
            applicationSupportDirectory: temporaryRoot.appendingPathComponent("Support")
        )
        let manager = AgentHelperManager(
            paths: paths,
            bundleURL: bundleURL,
            homeDirectory: homeDirectory
        )

        XCTAssertThrowsError(try manager.registerCLI()) { error in
            XCTAssertEqual(error as? AgentHelperManagerError, .commandConflict(existingVox.path))
        }
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: commandDirectory.appendingPathComponent("voxflow").path
            ),
            paths.cliBinDirectory.appendingPathComponent("voxflow").path
        )
        XCTAssertEqual(try Data(contentsOf: existingVox), Data("existing".utf8))
    }

    func testExistingRouterFromOlderVersionHasPermissionsTightenedBeforeReuse() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let paths = ApplicationSupportPaths(applicationSupportDirectory: temporaryRoot)
        try paths.ensureDirectories()
        _ = FileManager.default.createFile(
            atPath: paths.agentRouterSocketURL.path,
            contents: Data()
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: paths.agentRouterDirectory.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644))],
            ofItemAtPath: paths.agentRouterSocketURL.path
        )
        let manager = AgentHelperManager(paths: paths, bundleURL: temporaryRoot)

        try manager.secureExistingRouterPaths()

        let directoryMode = try FileManager.default.attributesOfItem(
            atPath: paths.agentRouterDirectory.path
        )[.posixPermissions] as? NSNumber
        let socketMode = try FileManager.default.attributesOfItem(
            atPath: paths.agentRouterSocketURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryMode?.intValue, 0o700)
        XCTAssertEqual(socketMode?.intValue, 0o600)
    }

    private func makeBundleWithAgentHelpers(at root: URL) throws -> URL {
        let bundleURL = root.appendingPathComponent("VoxFlow.app", isDirectory: true)
        let helpersURL = bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpersURL, withIntermediateDirectories: true)
        let helperURL = helpersURL.appendingPathComponent("voxflow")
        try Data("helper".utf8).write(to: helperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: helperURL.path
        )
        try FileManager.default.createSymbolicLink(
            atPath: helpersURL.appendingPathComponent("vox").path,
            withDestinationPath: "voxflow"
        )
        return bundleURL
    }
}
