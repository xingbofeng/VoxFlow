import VoxFlowProviderVolcengine
import XCTest
@testable import VoxFlowApp

final class VolcengineRealtimeASRLiveTests: XCTestCase {
    func testConfiguredVolcengineRealtimeASRConnection() async throws {
        guard ProcessInfo.processInfo.environment["VOICEINPUT_TEST_VOLCENGINE_LIVE"] == "1" else {
            throw XCTSkip("Set VOICEINPUT_TEST_VOLCENGINE_LIVE=1 to run Volcengine realtime ASR live smoke test.")
        }

        let configuration = try Self.configuration()
        let result = try await VolcengineRealtimeASRClient().testConnection(configuration: configuration)

        XCTAssertEqual(result.status, .ok)
    }

    private static func configuration() throws -> VolcengineRealtimeASRConfiguration {
        let environment = ProcessInfo.processInfo.environment
        if let appID = environment["VOICEINPUT_TEST_VOLCENGINE_APP_ID"],
           let accessToken = environment["VOICEINPUT_TEST_VOLCENGINE_ACCESS_TOKEN"],
           let secretKey = environment["VOICEINPUT_TEST_VOLCENGINE_SECRET_KEY"] {
            return VolcengineRealtimeASRConfiguration(
                appID: appID,
                accessToken: accessToken,
                secretKey: secretKey
            )
        }

        let appEnvironment = AppEnvironment(container: try DependencyContainer.live())
        let manager = ASRManager(settingsRepository: appEnvironment.settingsRepository)
        return try manager.volcengineConfiguration()
    }
}
