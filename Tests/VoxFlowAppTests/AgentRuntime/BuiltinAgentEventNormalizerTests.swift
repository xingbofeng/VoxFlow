import XCTest
@testable import VoxFlowApp

final class BuiltinAgentEventNormalizerTests: XCTestCase {
    func testToolRequestedEventMapsToAgentActionEvent() throws {
        let normalizer = BuiltinAgentEventNormalizer(
            now: { Date(timeIntervalSince1970: 1_800_000_001) }
        )
        let raw = try decodeEvent(
            #"{"event":"toolRequested","toolCall":{"id":"replace-1","name":"replace_selection","arguments":{"text":"正式版本"}}}"#
        )

        let event = try XCTUnwrap(
            normalizer.normalize(raw, startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        )

        XCTAssertEqual(event.kind, .toolRequested)
        XCTAssertEqual(event.toolName, "replace_selection")
        XCTAssertEqual(event.title, "调用工具 replace_selection")
        XCTAssertEqual(event.elapsedMS, 1_000)
    }

    func testErrorEventMapsToFailedAgentActionEvent() throws {
        let normalizer = BuiltinAgentEventNormalizer(
            now: { Date(timeIntervalSince1970: 1_800_000_002) }
        )
        let raw = try decodeEvent(#"{"event":"error","reason":"repeated_failed_tool_result"}"#)

        let event = try XCTUnwrap(
            normalizer.normalize(raw, startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        )

        XCTAssertEqual(event.kind, .error)
        XCTAssertEqual(event.title, "任务失败")
        XCTAssertEqual(event.detail, "repeated_failed_tool_result")
        XCTAssertTrue(event.isFailure)
        XCTAssertEqual(CodexEventNormalizer().status(after: event), .failed)
    }

    func testToolFailureEventMapsToRecoverableWarning() throws {
        let normalizer = BuiltinAgentEventNormalizer(
            now: { Date(timeIntervalSince1970: 1_800_000_002) }
        )
        let raw = try decodeEvent(
            #"{"event":"toolResolved","toolName":"write_file","result":{"ok":false,"toolName":"write_file","result":null,"error":{"code":"file_writes_not_enabled"}}}"#
        )

        let event = try XCTUnwrap(
            normalizer.normalize(raw, startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        )

        XCTAssertEqual(event.kind, .warning)
        XCTAssertEqual(event.title, "工具未执行")
        XCTAssertEqual(event.detail, "file_writes_not_enabled")
        XCTAssertEqual(event.toolName, "write_file")
        XCTAssertFalse(event.isFailure)
        XCTAssertEqual(CodexEventNormalizer().status(after: event), .running)
    }

    func testTurnCompletedEventMapsToCompletionHUDStage() throws {
        let normalizer = BuiltinAgentEventNormalizer(
            now: { Date(timeIntervalSince1970: 1_800_000_003) }
        )
        let raw = try decodeEvent(#"{"event":"turnCompleted","summary":"已替换选区。"}"#)

        let event = try XCTUnwrap(
            normalizer.normalize(raw, startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        )

        XCTAssertEqual(event.kind, .turnCompleted)
        XCTAssertEqual(event.detail, "已替换选区。")
        XCTAssertEqual(CodexEventNormalizer().hudStage(after: event), .runtimeCompleted(summary: "已替换选区。"))
    }
}

private func decodeEvent(_ json: String) throws -> BuiltinAgentRuntimeEvent {
    try JSONDecoder().decode(BuiltinAgentRuntimeEvent.self, from: Data(json.utf8))
}
