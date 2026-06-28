import Foundation
import VoxFlowProviderAliyunDashScope
import XCTest
@testable import VoxFlowApp

final class AliyunDashScopeRealtimeASRLiveTests: XCTestCase {
    func testConfiguredAliyunDashScopeRealtimeASREmitsFinalResult() async throws {
        guard ProcessInfo.processInfo.environment["VOICEINPUT_TEST_ALIYUN_DASHSCOPE_LIVE"] == "1" else {
            throw XCTSkip("Set VOICEINPUT_TEST_ALIYUN_DASHSCOPE_LIVE=1 to run Aliyun DashScope realtime ASR live smoke test.")
        }
        let configuration: AliyunDashScopeRealtimeASRConfiguration
        if let apiKey = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_ALIYUN_DASHSCOPE_API_KEY"],
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configuration = AliyunDashScopeRealtimeASRConfiguration(
                apiKey: apiKey,
                vocabularyID: ProcessInfo.processInfo.environment["VOICEINPUT_TEST_ALIYUN_DASHSCOPE_VOCABULARY_ID"]
            )
        } else {
            let environment = AppEnvironment(container: try DependencyContainer.live())
            let manager = ASRManager(settingsRepository: environment.settingsRepository)
            configuration = try manager.aliyunDashScopeConfiguration()
        }
        let client = AliyunDashScopeRealtimeASRClient()
        let finalText = LockedAliyunDashScopeLiveTranscript()
        let pcm = try Self.pcmPayload(
            from: Self.repositoryRoot()
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
            if message.isFinalResult, !message.transcript.isEmpty {
                finalText.append(message.transcript)
            }
        }

        XCTAssertFalse(finalText.value.isEmpty)
    }

    private static func pcmPayload(from wavURL: URL) throws -> Data {
        let data = try Data(contentsOf: wavURL)
        guard data.count > 44 else {
            throw AliyunDashScopeRealtimeASRError.invalidMessage
        }
        return data.subdata(in: 44..<data.count)
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

private final class LockedAliyunDashScopeLiveTranscript: @unchecked Sendable {
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
