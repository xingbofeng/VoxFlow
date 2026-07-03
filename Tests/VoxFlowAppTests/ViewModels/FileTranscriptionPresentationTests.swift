import XCTest
@testable import VoxFlowApp

final class FileTranscriptionPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testStatusIconAndColorCoverAllStates() {
        for status in [
            TranscriptionJobStatus.queued,
            .running,
            .completed,
            .failed,
            .cancelled,
            .partiallyFailed,
            .interrupted
        ] {
            let job = makeJob(status: status.rawValue)
            XCTAssertFalse(FileTranscriptionPresentation.statusIcon(for: job).isEmpty)
            _ = FileTranscriptionPresentation.statusColor(for: job)
        }
    }

    func testMetadataLineIncludesDurationFormatAndSegmentCount() {
        let job = TranscriptionJobRecord(
            id: "job",
            sourceFilePath: "/tmp/audio.m4a",
            sourceFileName: "audio.m4a",
            status: TranscriptionJobStatus.completed.rawValue,
            progress: 1,
            rawText: nil,
            finalText: nil,
            asrProviderID: nil,
            styleID: nil,
            errorMessage: nil,
            durationMS: 95_000,
            createdAt: now,
            updatedAt: now,
            completedAt: now,
            segmentCount: 4,
            segmentCompleted: 4
        )

        let line = FileTranscriptionPresentation.metadataLine(for: job)
        XCTAssertTrue(line.contains("M4A"))
        XCTAssertTrue(line.contains("1:35"))
        XCTAssertTrue(line.contains("4"))
    }

    func testMetadataLineOmitsDurationAndSegmentsWhenZero() {
        let job = makeJob(status: TranscriptionJobStatus.queued.rawValue)
        let line = FileTranscriptionPresentation.metadataLine(for: job)
        XCTAssertTrue(line.contains("WAV"))
        XCTAssertFalse(line.contains(":"))
    }

    func testProviderModeLabels() {
        XCTAssertEqual(
            FileTranscriptionPresentation.providerModeLabel(TranscriptionProviderMode.nativeFile.rawValue),
            FileTranscriptionPresentation.providerModeLabel(TranscriptionProviderMode.nativeFile.rawValue)
        )
        // 不同 mode 应产出不同 label（即便文案未本地化，也不应相等）。
        let native = FileTranscriptionPresentation.providerModeLabel(TranscriptionProviderMode.nativeFile.rawValue)
        let segmented = FileTranscriptionPresentation.providerModeLabel(TranscriptionProviderMode.segmentedCompatible.rawValue)
        let notRecommended = FileTranscriptionPresentation.providerModeLabel(TranscriptionProviderMode.notRecommendedForLongFiles.rawValue)
        XCTAssertNotEqual(native, segmented)
        XCTAssertNotEqual(native, notRecommended)
        XCTAssertNotEqual(segmented, notRecommended)
    }

    func testDurationLabelFormatting() {
        XCTAssertEqual(FileTranscriptionPresentation.durationLabel(0), "0s")
        XCTAssertEqual(FileTranscriptionPresentation.durationLabel(45_000), "45s")
        XCTAssertEqual(FileTranscriptionPresentation.durationLabel(90_000), "1:30")
        XCTAssertEqual(FileTranscriptionPresentation.durationLabel(3_661_000), "61:01")
    }

    func testFileExtension() {
        XCTAssertEqual(FileTranscriptionPresentation.fileExtension(from: "audio.m4a"), "m4a")
        XCTAssertEqual(FileTranscriptionPresentation.fileExtension(from: "video.MP4"), "mp4")
        XCTAssertEqual(FileTranscriptionPresentation.fileExtension(from: "noext"), "")
    }

    private func makeJob(status: String) -> TranscriptionJobRecord {
        TranscriptionJobRecord(
            id: UUID().uuidString,
            sourceFilePath: "/tmp/audio.wav",
            sourceFileName: "audio.wav",
            status: status,
            progress: 0,
            rawText: nil,
            finalText: nil,
            asrProviderID: nil,
            styleID: nil,
            errorMessage: nil,
            durationMS: 0,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
    }
}
