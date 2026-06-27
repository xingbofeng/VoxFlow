import XCTest
import Speech
@testable import VoxFlowApp

final class RecordingSubtitleTranscriberTests: XCTestCase {
    // MARK: - 3.1 无麦克风音轨不启动生成

    func testNoMicrophoneAudioThrowsBeforeAnyWork() async throws {
        let recognizer = FakeSpeechRecognizer()
        let extractor = FakeAudioExtractor()
        let transcriber = LiveSystemRecordingSubtitleTranscriber(
            recognizer: recognizer,
            extractor: extractor
        )

        do {
            _ = try await transcriber.transcribe(
                videoURL: URL(fileURLWithPath: "/tmp/rec.mp4"),
                audioMode: .none
            )
            XCTFail("无声录屏不应进入字幕生成")
        } catch let error as RecordingSubtitleTranscriptionError {
            XCTAssertEqual(error, .noMicrophoneAudio)
        }

        XCTAssertFalse(recognizer.authorizationChecked, "无声录屏不应检查 Speech 权限")
        XCTAssertEqual(extractor.extractCallCount, 0, "无声录屏不应抽取音轨")
    }

    // MARK: - 3.2 Speech 权限缺失

    func testSpeechPermissionDeniedThrowsAndKeepsOriginalUsable() async throws {
        let recognizer = FakeSpeechRecognizer(authorizationStatus: .denied)
        let extractor = FakeAudioExtractor()
        let transcriber = LiveSystemRecordingSubtitleTranscriber(
            recognizer: recognizer,
            extractor: extractor
        )
        let videoURL = URL(fileURLWithPath: "/tmp/rec.mp4")

        do {
            _ = try await transcriber.transcribe(videoURL: videoURL, audioMode: .microphone)
            XCTFail("权限缺失应抛错")
        } catch let error as RecordingSubtitleTranscriptionError {
            XCTAssertEqual(error, .speechPermissionDenied)
        }

        // 原视频路径保持不变，未被改动。
        XCTAssertEqual(videoURL.path, "/tmp/rec.mp4")
        XCTAssertEqual(extractor.extractCallCount, 0, "权限缺失不应抽取音轨")
    }

    func testSpeechPermissionNotDeterminedRequestsThenFailsIfStillDenied() async throws {
        let recognizer = FakeSpeechRecognizer(
            authorizationStatus: .notDetermined,
            authorizationAfterRequest: .denied
        )
        let extractor = FakeAudioExtractor()
        let transcriber = LiveSystemRecordingSubtitleTranscriber(
            recognizer: recognizer,
            extractor: extractor
        )

        do {
            _ = try await transcriber.transcribe(
                videoURL: URL(fileURLWithPath: "/tmp/rec.mp4"),
                audioMode: .microphone
            )
            XCTFail("请求后仍被拒应抛错")
        } catch let error as RecordingSubtitleTranscriptionError {
            XCTAssertEqual(error, .speechPermissionDenied)
        }
        XCTAssertTrue(recognizer.requestAuthorizationCalled)
    }

    // MARK: - 3.3 / 3.5 成功映射 timed segments

    func testSuccessfulTranscriptionMapsTimedSegments() async throws {
        let recognizer = FakeSpeechRecognizer(
            authorizationStatus: .authorized,
            timedSegments: [
                TimedSpeechSegment(startMS: 400, durationMS: 1_700, text: "第一句"),
                TimedSpeechSegment(startMS: 2_100, durationMS: 2_720, text: "第二句")
            ]
        )
        let extractor = FakeAudioExtractor(tempAudioURL: URL(fileURLWithPath: "/tmp/audio.m4a"))
        let transcriber = LiveSystemRecordingSubtitleTranscriber(
            recognizer: recognizer,
            extractor: extractor
        )

        let result = try await transcriber.transcribe(
            videoURL: URL(fileURLWithPath: "/tmp/rec.mp4"),
            audioMode: .microphone
        )

        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].startMS, 400)
        XCTAssertEqual(result.segments[0].endMS, 2_100)
        XCTAssertEqual(result.segments[0].text, "第一句")
        XCTAssertEqual(result.segments[1].startMS, 2_100)
        XCTAssertEqual(result.segments[1].endMS, 4_820)
        XCTAssertEqual(result.segments[1].text, "第二句")
        XCTAssertEqual(extractor.removeCallCount, 1, "成功后应清理临时音轨")
    }

    // MARK: - 3.4 / 3.7 抽取失败抛错并清理

    func testAudioExtractionFailureThrows() async throws {
        let recognizer = FakeSpeechRecognizer(authorizationStatus: .authorized)
        let extractor = FakeAudioExtractor(
            extractError: .audioExtractionFailed("无法抽取音轨")
        )
        let transcriber = LiveSystemRecordingSubtitleTranscriber(
            recognizer: recognizer,
            extractor: extractor
        )

        do {
            _ = try await transcriber.transcribe(
                videoURL: URL(fileURLWithPath: "/tmp/rec.mp4"),
                audioMode: .microphone
            )
            XCTFail("抽取失败应抛错")
        } catch let error as RecordingSubtitleTranscriptionError {
            XCTAssertEqual(error, .audioExtractionFailed("无法抽取音轨"))
        }
        XCTAssertEqual(recognizer.transcribeCallCount, 0, "抽取失败不应调用识别")
    }

    func testRecognitionFailureThrowsAndCleansTemp() async throws {
        let recognizer = FakeSpeechRecognizer(
            authorizationStatus: .authorized,
            transcribeError: .recognitionFailed("识别失败")
        )
        let extractor = FakeAudioExtractor(tempAudioURL: URL(fileURLWithPath: "/tmp/audio.m4a"))
        let transcriber = LiveSystemRecordingSubtitleTranscriber(
            recognizer: recognizer,
            extractor: extractor
        )

        do {
            _ = try await transcriber.transcribe(
                videoURL: URL(fileURLWithPath: "/tmp/rec.mp4"),
                audioMode: .microphone
            )
            XCTFail("识别失败应抛错")
        } catch let error as RecordingSubtitleTranscriptionError {
            XCTAssertEqual(error, .recognitionFailed("识别失败"))
        }
        XCTAssertEqual(extractor.removeCallCount, 1, "识别失败也应清理临时音轨")
    }

    // MARK: - 段映射纯函数

    func testSegmentMappingUsesTimestampAndDuration() {
        let segment = LiveSystemRecordingSubtitleTranscriber.map(
            TimedSpeechSegment(startMS: 1_500, durationMS: 800, text: "hi")
        )
        XCTAssertEqual(segment.startMS, 1_500)
        XCTAssertEqual(segment.endMS, 2_300)
        XCTAssertEqual(segment.text, "hi")
        XCTAssertFalse(segment.id.isEmpty)
    }
}

// MARK: - Fakes

private final class FakeSpeechRecognizer: RecordingSpeechRecognizerPort, @unchecked Sendable {
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus
    var authorizationAfterRequest: SFSpeechRecognizerAuthorizationStatus
    var timedSegments: [TimedSpeechSegment]
    var transcribeError: RecordingSubtitleTranscriptionError?

    private(set) var authorizationChecked = false
    private(set) var requestAuthorizationCalled = false
    private(set) var transcribeCallCount = 0

    init(
        authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized,
        authorizationAfterRequest: SFSpeechRecognizerAuthorizationStatus? = nil,
        timedSegments: [TimedSpeechSegment] = [],
        transcribeError: RecordingSubtitleTranscriptionError? = nil
    ) {
        self.authorizationStatus = authorizationStatus
        self.authorizationAfterRequest = authorizationAfterRequest ?? authorizationStatus
        self.timedSegments = timedSegments
        self.transcribeError = transcribeError
    }

    func currentAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        authorizationChecked = true
        return authorizationStatus
    }

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        requestAuthorizationCalled = true
        return authorizationAfterRequest
    }

    func transcribeAudioFile(at url: URL) async throws -> [TimedSpeechSegment] {
        transcribeCallCount += 1
        if let transcribeError { throw transcribeError }
        return timedSegments
    }
}

private final class FakeAudioExtractor: RecordingAudioTrackExtractorPort, @unchecked Sendable {
    var tempAudioURL: URL?
    var extractError: RecordingSubtitleTranscriptionError?

    private(set) var extractCallCount = 0
    private(set) var removeCallCount = 0
    private(set) var removedURLs: [URL] = []

    init(tempAudioURL: URL? = nil, extractError: RecordingSubtitleTranscriptionError? = nil) {
        self.tempAudioURL = tempAudioURL
        self.extractError = extractError
    }

    func extractAudio(from videoURL: URL) async throws -> URL {
        extractCallCount += 1
        if let extractError { throw extractError }
        return tempAudioURL ?? URL(fileURLWithPath: "/tmp/default-audio.m4a")
    }

    func removeTempAudio(_ url: URL) {
        removeCallCount += 1
        removedURLs.append(url)
    }
}
