import Foundation

@MainActor
final class UpdateCheckCoordinator {
    private let currentVersion: String
    private let service: UpdateCheckService
    private let stateStore: UpdateCheckStateStore
    private let presenter: any UpdatePromptPresenting
    private let now: () -> Date
    private var automaticCheckTask: Task<Void, Never>?

    init(
        currentVersion: String,
        service: UpdateCheckService,
        stateStore: UpdateCheckStateStore,
        presenter: any UpdatePromptPresenting = UpdatePromptPresenter(),
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.service = service
        self.stateStore = stateStore
        self.presenter = presenter
        self.now = now
    }

    static func live(
        currentVersion: String,
        presenter: (any UpdatePromptPresenting)? = nil
    ) -> UpdateCheckCoordinator {
        let stateStore = UpdateCheckStateStore()
        let client = makeReleaseClient(currentVersion: currentVersion)
        let service = UpdateCheckService(
            currentVersion: currentVersion,
            client: client,
            stateStore: stateStore
        )
        return UpdateCheckCoordinator(
            currentVersion: currentVersion,
            service: service,
            stateStore: stateStore,
            presenter: presenter ?? UpdatePromptPresenter()
        )
    }

    func scheduleAutomaticCheck(delay: TimeInterval = 30) {
        automaticCheckTask?.cancel()
        automaticCheckTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.run(mode: .automatic)
        }
    }

    func checkForUpdatesManually() {
        Task { @MainActor [weak self] in
            await self?.run(mode: .manual)
        }
    }

    func dismissActivePromptAsNextTime() {
        presenter.dismissActivePromptAsNextTime()
    }

    private func run(mode: UpdateCheckMode) async {
        let result = await service.check(mode: mode)
        switch result {
        case .updateAvailable(let release):
            let action = await presenter.presentUpdateAvailable(release: release, currentVersion: currentVersion)
            if action == .remindNextTime {
                stateStore.lastAutomaticCheckAt = nil
                stateStore.lastAutomaticCheckVersion = nil
            } else if action == .remindTomorrow {
                stateStore.deferredVersion = release.version
                stateStore.deferredUntil = now().addingTimeInterval(24 * 60 * 60)
            } else if action == .ignore {
                stateStore.ignoredVersion = release.version
            }
        case .upToDate:
            if mode == .manual {
                await presenter.presentUpToDate(currentVersion: currentVersion)
            }
        case .failed:
            if mode == .manual {
                await presenter.presentFailure()
            } else {
                AppLogger.general.debug("automatic_update_check_failed")
            }
        case .ignored:
            AppLogger.general.debug("automatic_update_check_ignored_version")
        case .deferred:
            AppLogger.general.debug("automatic_update_check_deferred_version")
        case .throttled:
            AppLogger.general.debug("automatic_update_check_throttled")
        }
    }

    private static func makeReleaseClient(currentVersion: String) -> any ReleaseMetadataClient {
        #if DEBUG
        if let debugClient = makeDebugReleaseClient(currentVersion: currentVersion) {
            return debugClient
        }
        #endif
        return PagesReleaseMetadataClient()
    }

    #if DEBUG
    private static func makeDebugReleaseClient(currentVersion: String) -> (any ReleaseMetadataClient)? {
        let environment = ProcessInfo.processInfo.environment
        if let fixturePath = environment["VOXFLOW_UPDATE_CHECK_FIXTURE"], !fixturePath.isEmpty {
            return FixtureReleaseMetadataClient(path: fixturePath)
        }

        switch environment["VOXFLOW_UPDATE_CHECK_MOCK"] {
        case "newer":
            return StaticReleaseMetadataClient(release: debugRelease(version: nextPatchVersion(after: currentVersion)))
        case "same":
            return StaticReleaseMetadataClient(release: debugRelease(version: currentVersion))
        case "network-error":
            return FailingReleaseMetadataClient()
        default:
            return nil
        }
    }

    private static func debugRelease(version: String) -> RemoteRelease {
        let tag = "v\(version)"
        let pageURL = URL(string: "https://github.com/xingbofeng/VoxFlow/releases/tag/\(tag)")!
        let downloadURL = URL(string: "https://github.com/xingbofeng/VoxFlow/releases/download/\(tag)/VoxFlow-\(version)-macOS.dmg")!
        return RemoteRelease(
            version: version,
            tagName: tag,
            releasePageURL: pageURL,
            downloadURL: downloadURL,
            releaseNotes: L10n.localize("app.update.mock_release_notes", comment: ""),
            isDraft: false,
            isPrerelease: false
        )
    }

    private static func nextPatchVersion(after version: String) -> String {
        guard let semanticVersion = SemanticVersion(version) else {
            return "999.0.0"
        }
        return "\(semanticVersion.major).\(semanticVersion.minor).\(semanticVersion.patch + 1)"
    }
    #endif
}

#if DEBUG
private struct StaticReleaseMetadataClient: ReleaseMetadataClient {
    let release: RemoteRelease

    func fetchLatestRelease() async throws -> RemoteRelease {
        release
    }
}

private struct FailingReleaseMetadataClient: ReleaseMetadataClient {
    func fetchLatestRelease() async throws -> RemoteRelease {
        throw GitHubReleaseClientError.invalidResponse
    }
}

private struct FixtureReleaseMetadataClient: ReleaseMetadataClient {
    let path: String

    func fetchLatestRelease() async throws -> RemoteRelease {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try GitHubReleaseClient.decodeRelease(data: data)
    }
}
#endif
