import XCTest
@testable import VoxFlowApp

@MainActor
final class UpdateCheckCoordinatorTests: XCTestCase {
    func testAutomaticReminderNextTimeClearsAutomaticThrottle() async {
        let now = Date(timeIntervalSince1970: 1_800_086_400)
        let store = UpdateCheckStateStore(defaults: makeDefaults())
        let presenter = FakeUpdatePromptPresenter(action: .remindNextTime)
        let service = UpdateCheckService(
            currentVersion: "1.6.2",
            client: StaticCoordinatorReleaseClient(release: release(version: "1.7.0")),
            stateStore: store,
            now: { now }
        )
        let coordinator = UpdateCheckCoordinator(
            currentVersion: "1.6.2",
            service: service,
            stateStore: store,
            presenter: presenter,
            now: { now }
        )

        coordinator.scheduleAutomaticCheck(delay: 0)
        await presenter.waitForUpdatePrompt()

        XCTAssertNil(store.lastAutomaticCheckAt)
        XCTAssertNil(store.deferredVersion)
        XCTAssertNil(store.deferredUntil)
        XCTAssertNil(store.ignoredVersion)
    }

    private func release(version: String) -> RemoteRelease {
        let tag = "v\(version)"
        let pageURL = URL(string: "https://github.com/xingbofeng/VoxFlow/releases/tag/\(tag)")!
        return RemoteRelease(
            version: version,
            tagName: tag,
            releasePageURL: pageURL,
            downloadURL: pageURL,
            releaseNotes: "",
            isDraft: false,
            isPrerelease: false
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UpdateCheckCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class FakeUpdatePromptPresenter: UpdatePromptPresenting {
    private let action: UpdatePromptAction
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var updatePromptCount = 0

    init(action: UpdatePromptAction) {
        self.action = action
    }

    func presentUpdateAvailable(release: RemoteRelease, currentVersion: String) async -> UpdatePromptAction {
        updatePromptCount += 1
        continuation?.resume()
        continuation = nil
        return action
    }

    func presentUpToDate(currentVersion: String) async {}

    func presentFailure() async {}

    func dismissActivePromptAsNextTime() {}

    func waitForUpdatePrompt() async {
        if updatePromptCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

private struct StaticCoordinatorReleaseClient: ReleaseMetadataClient {
    let release: RemoteRelease

    func fetchLatestRelease() async throws -> RemoteRelease {
        release
    }
}
