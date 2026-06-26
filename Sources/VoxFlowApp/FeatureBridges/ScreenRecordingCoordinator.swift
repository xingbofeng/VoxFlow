import Foundation

@MainActor
final class ScreenRecordingCoordinator {
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case recording(id: String, temporaryURL: URL)
    }

    typealias CountdownSleep = (TimeInterval) async throws -> Void

    private let service: any ScreenRecordingServicing
    private let fileStorage: ScreenRecordingFileStorage
    private let committer: ScreenRecordingCompletionCommitter
    private let countdownSleep: CountdownSleep

    var onPhaseChange: ((Phase) -> Void)?
    private(set) var phase: Phase = .idle {
        didSet { onPhaseChange?(phase) }
    }

    init(
        service: any ScreenRecordingServicing,
        fileStorage: ScreenRecordingFileStorage,
        committer: ScreenRecordingCompletionCommitter,
        countdownSleep: @escaping CountdownSleep = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.service = service
        self.fileStorage = fileStorage
        self.committer = committer
        self.countdownSleep = countdownSleep
    }

    func start(
        id: String,
        request: ScreenRecordingRequest,
        onCountdown: (@MainActor (Int) -> Void)? = nil,
        beforeStartCapture: (@MainActor () -> Void)? = nil,
        afterStartCapture: (@MainActor () -> Void)? = nil
    ) async throws {
        guard phase == .idle else { return }
        let temporaryURL = fileStorage.temporaryURL(for: id)
        do {
            for value in [3, 2, 1] {
                phase = .countdown(value)
                onCountdown?(value)
                try await countdownSleep(1)
            }
            beforeStartCapture?()
            try await service.start(request, outputURL: temporaryURL)
            phase = .recording(id: id, temporaryURL: temporaryURL)
            afterStartCapture?()
        } catch {
            fileStorage.removeTemporary(at: temporaryURL)
            phase = .idle
            throw error
        }
    }

    @discardableResult
    func stop() async throws -> MediaRecord {
        guard case .recording(let id, let temporaryURL) = phase else {
            throw ScreenRecordingServiceError.notRunning
        }
        do {
            let completion = try await service.stop()
            let record = try committer.commitSuccessfulRecording(
                id: id,
                temporaryURL: temporaryURL,
                completion: completion
            )
            phase = .idle
            return record
        } catch {
            committer.discardFailedRecording(temporaryURL: temporaryURL)
            phase = .idle
            throw error
        }
    }

    func cancel() async {
        let temporaryURL: URL?
        if case .recording(_, let url) = phase {
            temporaryURL = url
        } else {
            temporaryURL = nil
        }
        await service.cancel()
        if let temporaryURL {
            committer.discardCancelledRecording(temporaryURL: temporaryURL)
        }
        phase = .idle
    }
}
