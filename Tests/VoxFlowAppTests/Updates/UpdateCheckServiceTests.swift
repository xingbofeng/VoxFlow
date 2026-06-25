import XCTest
@testable import VoxFlowApp

@MainActor
final class UpdateCheckServiceTests: XCTestCase {
    func testNewerRemoteVersionReturnsUpdateAvailable() async {
        let service = makeService(currentVersion: "1.6.1", release: release(version: "1.6.2"))

        let result = await service.check(mode: .manual)

        guard case .updateAvailable(let remote) = result else {
            return XCTFail("Expected updateAvailable, got \(result)")
        }
        XCTAssertEqual(remote.version, "1.6.2")
    }

    func testSameRemoteVersionReturnsUpToDate() async {
        let service = makeService(currentVersion: "1.6.1", release: release(version: "1.6.1"))

        let result = await service.check(mode: .manual)

        XCTAssertEqual(result, .upToDate)
    }

    func testOlderRemoteVersionReturnsUpToDate() async {
        let service = makeService(currentVersion: "1.6.10", release: release(version: "1.6.2"))

        let result = await service.check(mode: .manual)

        XCTAssertEqual(result, .upToDate)
    }

    func testAutomaticCheckIgnoresIgnoredRemoteVersion() async {
        let store = UpdateCheckStateStore(defaults: makeDefaults())
        store.ignoredVersion = "1.6.2"
        let service = makeService(currentVersion: "1.6.1", release: release(version: "1.6.2"), store: store)

        let result = await service.check(mode: .automatic)

        guard case .ignored(let remote) = result else {
            return XCTFail("Expected ignored, got \(result)")
        }
        XCTAssertEqual(remote.version, "1.6.2")
    }

    func testManualCheckBypassesIgnoredRemoteVersion() async {
        let store = UpdateCheckStateStore(defaults: makeDefaults())
        store.ignoredVersion = "1.6.2"
        let service = makeService(currentVersion: "1.6.1", release: release(version: "1.6.2"), store: store)

        let result = await service.check(mode: .manual)

        guard case .updateAvailable = result else {
            return XCTFail("Expected updateAvailable, got \(result)")
        }
    }

    func testAutomaticCheckDefersRemoteVersionUntilDeferredDate() async {
        let now = Date(timeIntervalSince1970: 1_800_086_400)
        let store = UpdateCheckStateStore(defaults: makeDefaults())
        store.deferredVersion = "1.6.2"
        store.deferredUntil = now.addingTimeInterval(60)
        let service = makeService(
            currentVersion: "1.6.1",
            release: release(version: "1.6.2"),
            store: store,
            now: { now }
        )

        let result = await service.check(mode: .automatic)

        guard case .deferred(let remote) = result else {
            return XCTFail("Expected deferred, got \(result)")
        }
        XCTAssertEqual(remote.version, "1.6.2")
    }

    func testAutomaticCheckShowsDeferredVersionAfterDeferredDate() async {
        let now = Date(timeIntervalSince1970: 1_800_086_400)
        let store = UpdateCheckStateStore(defaults: makeDefaults())
        store.deferredVersion = "1.6.2"
        store.deferredUntil = now.addingTimeInterval(-60)
        let service = makeService(
            currentVersion: "1.6.1",
            release: release(version: "1.6.2"),
            store: store,
            now: { now }
        )

        let result = await service.check(mode: .automatic)

        guard case .updateAvailable = result else {
            return XCTFail("Expected updateAvailable, got \(result)")
        }
    }

    func testManualCheckBypassesDeferredVersion() async {
        let now = Date(timeIntervalSince1970: 1_800_086_400)
        let store = UpdateCheckStateStore(defaults: makeDefaults())
        store.deferredVersion = "1.6.2"
        store.deferredUntil = now.addingTimeInterval(60 * 60 * 24)
        let service = makeService(
            currentVersion: "1.6.1",
            release: release(version: "1.6.2"),
            store: store,
            now: { now }
        )

        let result = await service.check(mode: .manual)

        guard case .updateAvailable = result else {
            return XCTFail("Expected updateAvailable, got \(result)")
        }
    }

    func testAutomaticCheckWithinThrottleWindowReturnsThrottled() async {
        let now = Date(timeIntervalSince1970: 1_800_086_400)
        let store = UpdateCheckStateStore(defaults: makeDefaults())
        store.lastAutomaticCheckAt = now.addingTimeInterval(-60)
        let service = makeService(
            currentVersion: "1.6.1",
            release: release(version: "1.6.2"),
            store: store,
            now: { now }
        )

        let result = await service.check(mode: .automatic)

        XCTAssertEqual(result, .throttled)
    }

    func testManualCheckBypassesThrottleWindow() async {
        let now = Date(timeIntervalSince1970: 1_800_086_400)
        let store = UpdateCheckStateStore(defaults: makeDefaults())
        store.lastAutomaticCheckAt = now.addingTimeInterval(-60)
        let service = makeService(
            currentVersion: "1.6.1",
            release: release(version: "1.6.2"),
            store: store,
            now: { now }
        )

        let result = await service.check(mode: .manual)

        guard case .updateAvailable = result else {
            return XCTFail("Expected updateAvailable, got \(result)")
        }
    }

    func testFailedFetchReturnsFailed() async {
        let service = UpdateCheckService(
            currentVersion: "1.6.1",
            client: FailingReleaseClient(),
            stateStore: UpdateCheckStateStore(defaults: makeDefaults())
        )

        let result = await service.check(mode: .manual)

        XCTAssertEqual(result, .failed(.fetchFailed))
    }

    private func makeService(
        currentVersion: String,
        release: RemoteRelease,
        store: UpdateCheckStateStore? = nil,
        now: @escaping () -> Date = Date.init
    ) -> UpdateCheckService {
        UpdateCheckService(
            currentVersion: currentVersion,
            client: StaticReleaseClient(release: release),
            stateStore: store ?? UpdateCheckStateStore(defaults: makeDefaults()),
            now: now
        )
    }

    private func release(version: String, isDraft: Bool = false, isPrerelease: Bool = false) -> RemoteRelease {
        let tag = "v\(version)"
        let pageURL = URL(string: "https://github.com/xingbofeng/VoxFlow/releases/tag/\(tag)")!
        return RemoteRelease(
            version: version,
            tagName: tag,
            releasePageURL: pageURL,
            downloadURL: pageURL,
            releaseNotes: "",
            isDraft: isDraft,
            isPrerelease: isPrerelease
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UpdateCheckServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct StaticReleaseClient: ReleaseMetadataClient {
    let release: RemoteRelease

    func fetchLatestRelease() async throws -> RemoteRelease {
        release
    }
}

private struct FailingReleaseClient: ReleaseMetadataClient {
    func fetchLatestRelease() async throws -> RemoteRelease {
        throw GitHubReleaseClientError.invalidResponse
    }
}
