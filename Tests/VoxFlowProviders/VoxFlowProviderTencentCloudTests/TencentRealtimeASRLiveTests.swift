import Foundation
import VoxFlowProviderTencentCloud
import XCTest
@testable import VoxFlowApp

final class TencentRealtimeASRLiveTests: XCTestCase {
    func testConfiguredTencentRealtimeASREmitsFinalResult() async throws {
        guard ProcessInfo.processInfo.environment["VOICEINPUT_TEST_TENCENT_LIVE"] == "1" else {
            throw XCTSkip("Set VOICEINPUT_TEST_TENCENT_LIVE=1 to run Tencent Cloud realtime ASR live smoke test.")
        }
        let environment = AppEnvironment(container: try DependencyContainer.live())
        let manager = ASRManager(settingsRepository: environment.settingsRepository)
        let configuration = try manager.tencentCloudConfiguration()

        let text = try await Self.transcribe(configuration: configuration)

        XCTAssertFalse(text.isEmpty)
    }

    func testConfiguredTencentRealtimeASRAcceptsHotwordList() async throws {
        guard ProcessInfo.processInfo.environment["VOICEINPUT_TEST_TENCENT_LIVE"] == "1" else {
            throw XCTSkip("Set VOICEINPUT_TEST_TENCENT_LIVE=1 to run Tencent Cloud realtime ASR live smoke test.")
        }
        let environment = AppEnvironment(container: try DependencyContainer.live())
        let manager = ASRManager(settingsRepository: environment.settingsRepository)
        let base = try manager.tencentCloudConfiguration()
        let configuration = TencentRealtimeASRConfiguration(
            appID: base.appID,
            secretID: base.secretID,
            secretKey: base.secretKey,
            engineModelType: base.engineModelType,
            voiceFormat: base.voiceFormat,
            needVAD: base.needVAD,
            timeoutSeconds: base.timeoutSeconds,
            hotwordList: "随声写|11,语音输入|10,VoxFlow|9"
        )

        let text = try await Self.transcribe(configuration: configuration)

        XCTAssertFalse(text.isEmpty)
    }

    private static func pcmPayload(from wavURL: URL) throws -> Data {
        let data = try Data(contentsOf: wavURL)
        guard data.count > 44 else {
            throw TencentRealtimeASRError.invalidMessage
        }
        return data.subdata(in: 44..<data.count)
    }

    private static func transcribe(configuration: TencentRealtimeASRConfiguration) async throws -> String {
        let client = TencentRealtimeASRClient()
        let finalText = LockedTencentLiveTranscript()
        let pcm = try pcmPayload(
            from: repositoryRoot()
                .appendingPathComponent("TestResources/ASRSmoke/Audio/zh_short.wav")
        )
        let stream = AsyncStream<Data> { continuation in
            Task {
                for offset in stride(from: 0, to: pcm.count, by: 6_400) {
                    continuation.yield(pcm.subdata(in: offset..<min(offset + 6_400, pcm.count)))
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                continuation.finish()
            }
        }

        try await client.transcribe(configuration: configuration, audioChunks: stream) { message in
            if message.isStable, !message.transcript.isEmpty {
                finalText.append(message.transcript)
            }
        }
        return finalText.value
    }

    private static func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private final class LockedTencentLiveTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.withLock { storage }
    }

    func append(_ text: String) {
        lock.withLock {
            storage += text
        }
    }
}
