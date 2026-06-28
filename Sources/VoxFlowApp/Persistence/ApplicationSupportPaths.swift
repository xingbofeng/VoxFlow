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

    var screenRecordingsDirectory: URL {
        rootDirectory.appendingPathComponent("ScreenRecordings", isDirectory: true)
    }

    var screenRecordingTemporaryDirectory: URL {
        rootDirectory.appendingPathComponent("ScreenRecordings", isDirectory: true)
            .appendingPathComponent("Temporary", isDirectory: true)
    }

    /// 字幕产物目录：草稿 JSON、SRT、带字幕视频统一存放于此。
    var recordingSubtitleArtifactsDirectory: URL {
        screenRecordingsDirectory.appendingPathComponent("Subtitles", isDirectory: true)
    }

    func screenRecordingURL(forID id: String) -> URL {
        screenRecordingsDirectory.appendingPathComponent("\(id).mp4", isDirectory: false)
    }

    func screenRecordingTemporaryURL(forID id: String) -> URL {
        screenRecordingTemporaryDirectory.appendingPathComponent("\(id).tmp.mp4", isDirectory: false)
    }

    /// 字幕草稿 JSON 路径。
    func recordingSubtitleDraftURL(forID id: String) -> URL {
        recordingSubtitleArtifactsDirectory.appendingPathComponent("\(id).subtitle.json", isDirectory: false)
    }

    /// 导出 SRT 路径。
    func recordingSubtitleSRTURL(forID id: String) -> URL {
        recordingSubtitleArtifactsDirectory.appendingPathComponent("\(id).srt", isDirectory: false)
    }

    /// 带字幕视频路径（独立于原视频，永不覆盖原录屏）。
    func recordingSubtitledVideoURL(forID id: String) -> URL {
        recordingSubtitleArtifactsDirectory.appendingPathComponent("\(id).subtitled.mp4", isDirectory: false)
    }

    var clipboardAssetsDirectory: URL {
        rootDirectory.appendingPathComponent("ClipboardAssets", isDirectory: true)
    }

    var llmTraceDiagnosticsDirectory: URL {
        rootDirectory.appendingPathComponent("LLMTraceDiagnostics", isDirectory: true)
    }

    var credentialsURL: URL {
        rootDirectory.appendingPathComponent("credentials.json", isDirectory: false)
    }

    /// Hotword text file: one hotword per line, # comments and empty lines ignored.
    var hotwordsFileURL: URL {
        rootDirectory.appendingPathComponent("hotwords.txt", isDirectory: false)
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
            screenRecordingsDirectory,
            screenRecordingTemporaryDirectory,
            recordingSubtitleArtifactsDirectory,
            clipboardAssetsDirectory,
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
            return L10n.localize("app.paths.application_support_unavailable", comment: "")
        }
    }
}
