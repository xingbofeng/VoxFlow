import XCTest
@testable import VoxFlowApp

final class AppLoggerTests: XCTestCase {
    func testRedactsAuthorizationBearerToken() {
        let secret = "secret-token-\(UUID().uuidString)"
        let message = "Authorization: Bearer \(secret)"

        let redacted = AppLogger.redact(message)

        XCTAssertFalse(redacted.contains(secret))
        XCTAssertTrue(redacted.contains("Bearer [REDACTED]"))
    }

    func testRedactsAPIKeyInKeyValueText() {
        let secret = "plain-secret-\(UUID().uuidString)"
        let message = "LLM request failed api_key=\(secret)"

        let redacted = AppLogger.redact(message)

        XCTAssertFalse(redacted.contains(secret))
        XCTAssertTrue(redacted.contains("api_key=[REDACTED]"))
    }

    func testRedactsJSONAPIKeyField() {
        let secret = "json-secret-\(UUID().uuidString)"
        let message = #"{"api_key":"\#(secret)","model":"test"}"#

        let redacted = AppLogger.redact(message)

        XCTAssertFalse(redacted.contains(secret))
        XCTAssertTrue(redacted.contains(#""api_key":"[REDACTED]""#))
    }

    func testRedactsURLQueryAPIKey() {
        let secret = "query-secret-\(UUID().uuidString)"
        let message = "https://api.example.test/v1/models?api_key=\(secret)&limit=10"

        let redacted = AppLogger.redact(message)

        XCTAssertFalse(redacted.contains(secret))
        XCTAssertTrue(redacted.contains("api_key=[REDACTED]&limit=10"))
    }

    func testLeavesNonSensitiveMessageUnchanged() {
        let message = "AudioPreprocessor resample failed with status -50"

        XCTAssertEqual(AppLogger.redact(message), message)
    }
}
