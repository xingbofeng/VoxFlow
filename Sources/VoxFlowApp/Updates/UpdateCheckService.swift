import Foundation

enum UpdateCheckMode {
    case automatic
    case manual
}

enum UpdateCheckError: Error, Equatable {
    case fetchFailed
}

enum UpdateCheckResult: Equatable {
    case updateAvailable(RemoteRelease)
    case upToDate
    case ignored(RemoteRelease)
    case deferred(RemoteRelease)
    case failed(UpdateCheckError)
    case throttled
}

@MainActor
final class UpdateCheckService {
    private let currentVersion: String
    private let client: any ReleaseMetadataClient
    private let stateStore: UpdateCheckStateStore
    private let now: () -> Date
    private let automaticCheckInterval: TimeInterval

    init(
        currentVersion: String,
        client: any ReleaseMetadataClient,
        stateStore: UpdateCheckStateStore,
        now: @escaping () -> Date = Date.init,
        automaticCheckInterval: TimeInterval = 24 * 60 * 60
    ) {
        self.currentVersion = currentVersion
        self.client = client
        self.stateStore = stateStore
        self.now = now
        self.automaticCheckInterval = automaticCheckInterval
    }

    func check(mode: UpdateCheckMode) async -> UpdateCheckResult {
        if mode == .automatic, isAutomaticCheckThrottled() {
            return .throttled
        }

        if mode == .automatic {
            stateStore.lastAutomaticCheckAt = now()
        }

        let release: RemoteRelease
        do {
            release = try await client.fetchLatestRelease()
        } catch {
            return .failed(.fetchFailed)
        }

        guard release.isStableCandidate,
              let localVersion = SemanticVersion(currentVersion),
              let remoteVersion = SemanticVersion(release.version),
              remoteVersion > localVersion else {
            return .upToDate
        }

        if mode == .automatic, stateStore.ignoredVersion == release.version {
            return .ignored(release)
        }

        if mode == .automatic, isDeferred(release: release) {
            return .deferred(release)
        }

        return .updateAvailable(release)
    }

    private func isAutomaticCheckThrottled() -> Bool {
        guard let lastAutomaticCheckAt = stateStore.lastAutomaticCheckAt else {
            return false
        }
        return now().timeIntervalSince(lastAutomaticCheckAt) < automaticCheckInterval
    }

    private func isDeferred(release: RemoteRelease) -> Bool {
        guard stateStore.deferredVersion == release.version,
              let deferredUntil = stateStore.deferredUntil else {
            return false
        }
        return now() < deferredUntil
    }
}
