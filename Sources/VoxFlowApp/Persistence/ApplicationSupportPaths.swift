import Foundation

struct ApplicationSupportPaths: Equatable {
    let rootDirectory: URL

    init(
        applicationSupportDirectory: URL,
        appDirectoryName: String = "VoxFlow"
    ) {
        AppLogger.general.debug("ApplicationSupportPaths init dir=\(appDirectoryName)")
        rootDirectory = applicationSupportDirectory
            .appendingPathComponent(appDirectoryName, isDirectory: true)
    }

    static func live(fileManager: FileManager = .default) throws -> ApplicationSupportPaths {
        guard let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            AppLogger.general.warning("ApplicationSupportPaths live failed: applicationSupportDirectory not found")
            throw ApplicationSupportPathsError.applicationSupportDirectoryUnavailable
        }
        AppLogger.general.debug("ApplicationSupportPaths live path=\(applicationSupportDirectory.path)")

        return ApplicationSupportPaths(applicationSupportDirectory: applicationSupportDirectory)
    }

    var databaseURL: URL {
        rootDirectory.appendingPathComponent("voxflow.sqlite", isDirectory: false)
    }

    var exportsDirectory: URL {
        rootDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    var modelsDirectory: URL {
        rootDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    var voiceTaskAudioDirectory: URL {
        rootDirectory.appendingPathComponent("voice-task-audio", isDirectory: true)
    }

    var screenshotsDirectory: URL {
        rootDirectory.appendingPathComponent("Screenshots", isDirectory: true)
    }

    var llmTraceDiagnosticsDirectory: URL {
        rootDirectory.appendingPathComponent("LLMTraceDiagnostics", isDirectory: true)
    }

    var credentialsURL: URL {
        rootDirectory.appendingPathComponent("credentials.json", isDirectory: false)
    }

    func voiceTaskAudioURL(forTaskID taskID: String) -> URL {
        voiceTaskAudioDirectory.appendingPathComponent("\(taskID).m4a", isDirectory: false)
    }

    func ensureDirectories(fileManager: FileManager = .default) throws {
        AppLogger.general.debug("Ensure app directories root=\(rootDirectory.path)")
        for directory in [
            rootDirectory,
            exportsDirectory,
            modelsDirectory,
            voiceTaskAudioDirectory,
            screenshotsDirectory,
            agentRouterDirectory,
            cliBinDirectory,
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }
}

enum ApplicationSupportPathsError: Error, LocalizedError {
    case applicationSupportDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "无法定位 Application Support 目录。"
        }
    }
}
