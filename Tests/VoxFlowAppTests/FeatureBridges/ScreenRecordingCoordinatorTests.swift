import CoreGraphics
import XCTest
@testable import VoxFlowApp

@MainActor
final class ScreenRecordingCoordinatorTests: XCTestCase {
    func testStartWaitsThreeCountdownTicksBeforeStartingService() async throws {
        let subject = try makeSubject()
        var countdownTicks: [Int] = []

        subject.coordinator.onPhaseChange = { phase in
            if case .countdown(let value) = phase {
                countdownTicks.append(value)
            }
        }

        try await subject.coordinator.start(
            id: "recording",
            request: makeRequest()
        )

        XCTAssertEqual(countdownTicks, [3, 2, 1])
        XCTAssertEqual(subject.service.startedRequests.count, 1)
        XCTAssertEqual(subject.service.startedOutputURLs.first, subject.storage.temporaryURL(for: "recording"))
        XCTAssertEqual(subject.coordinator.phase, .recording(id: "recording", temporaryURL: subject.storage.temporaryURL(for: "recording")))
    }

    func testStartShowsCountdownAndActivatesOverlayBeforeStartingService() async throws {
        let subject = try makeSubject()
        var events: [String] = []
        subject.service.onStart = {
            events.append("service.start")
        }

        try await subject.coordinator.start(
            id: "recording",
            request: makeRequest(),
            onCountdown: { remaining in
                events.append("countdown.\(remaining)")
            },
            beforeStartCapture: {
                events.append("overlay.recordingFrame")
            },
            afterStartCapture: {
                events.append("hud.start")
            }
        )

        XCTAssertEqual(events, [
            "countdown.3",
            "countdown.2",
            "countdown.1",
            "overlay.recordingFrame",
            "service.start",
            "hud.start"
        ])
    }

    func testStopCommitsFinalRecordingAndReturnsToIdle() async throws {
        let subject = try makeSubject()
        try await subject.coordinator.start(id: "recording", request: makeRequest())
        let temporaryURL = subject.storage.temporaryURL(for: "recording")
        try Data("mp4".utf8).write(to: temporaryURL)
        subject.service.stopCompletion = ScreenRecordingCompletion(
            url: temporaryURL,
            durationMs: 1_000,
            width: 640,
            height: 360,
            fileSizeBytes: 3,
            audioMode: .none,
            thumbnailPath: nil
        )

        let record = try await subject.coordinator.stop()

        XCTAssertEqual(record.videoPath, subject.storage.finalURL(for: "recording").path)
        XCTAssertEqual(subject.repository.savedRecords.map(\.id), ["recording"])
        XCTAssertEqual(subject.coordinator.phase, .idle)
    }

    private func makeSubject() throws -> (
        coordinator: ScreenRecordingCoordinator,
        service: CapturingScreenRecordingService,
        repository: CapturingCoordinatorMediaRecordRepository,
        storage: ScreenRecordingFileStorage,
        root: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowCoordinator-\(UUID().uuidString)", isDirectory: true)
        let paths = ApplicationSupportPaths(applicationSupportDirectory: root)
        try paths.ensureDirectories()
        let storage = ScreenRecordingFileStorage(paths: paths)
        let service = CapturingScreenRecordingService()
        let repository = CapturingCoordinatorMediaRecordRepository()
        let committer = ScreenRecordingCompletionCommitter(
            fileStorage: storage,
            repository: repository,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let coordinator = ScreenRecordingCoordinator(
            service: service,
            fileStorage: storage,
            committer: committer,
            countdownSleep: { _ in }
        )
        return (coordinator, service, repository, storage, root)
    }

    private func makeRequest() -> ScreenRecordingRequest {
        ScreenRecordingRequest(
            displayID: 1,
            displayFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            selectionRect: CGRect(x: 10, y: 10, width: 320, height: 240),
            scale: 2
        )
    }
}

private final class CapturingScreenRecordingService: ScreenRecordingServicing, @unchecked Sendable {
    var startedRequests: [ScreenRecordingRequest] = []
    var startedOutputURLs: [URL] = []
    var onStart: (@MainActor () -> Void)?
    var stopCompletion = ScreenRecordingCompletion(
        url: URL(fileURLWithPath: "/tmp/missing.mp4"),
        durationMs: 0,
        width: 0,
        height: 0,
        fileSizeBytes: 0,
        audioMode: .none,
        thumbnailPath: nil
    )
    var isRunning = false

    func start(_ request: ScreenRecordingRequest, outputURL: URL) async throws {
        await onStart?()
        startedRequests.append(request)
        startedOutputURLs.append(outputURL)
        isRunning = true
    }

    func stop() async throws -> ScreenRecordingCompletion {
        isRunning = false
        return stopCompletion
    }

    func cancel() async {
        isRunning = false
    }
}

private final class CapturingCoordinatorMediaRecordRepository: MediaRecordRepository {
    private(set) var savedRecords: [MediaRecord] = []

    func save(_ record: MediaRecord) throws {
        savedRecords.append(record)
    }

    func record(id: String) throws -> MediaRecord? { savedRecords.first { $0.id == id } }

    func page(limit: Int, offset: Int, filter: MediaRecordFilter, search: String?) throws -> MediaRecordPage {
        MediaRecordPage(records: savedRecords, totalCount: savedRecords.count)
    }

    func toggleFavorite(id: String, isFavorited: Bool, updatedAt: Date) throws {}

    func softDelete(id: String, deletedAt: Date) throws {}

    func stats() throws -> MediaRecordStats {
        MediaRecordStats(totalMedia: savedRecords.count, todayMedia: savedRecords.count, screenshotCount: 0, recordingCount: savedRecords.count)
    }
}
