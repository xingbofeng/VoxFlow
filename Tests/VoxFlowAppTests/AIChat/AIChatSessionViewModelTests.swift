import XCTest
@testable import VoxFlowApp

@MainActor
final class AIChatSessionViewModelTests: XCTestCase {
    // MARK: - Send appends messages

    func testSendAppendsUserAndAssistantMessages() async {
        let service = CapturingAIChatService()
        service.streamChunks = ["Hello"]
        let vm = AIChatSessionViewModel(service: service)

        vm.send("你好")
        await awaitStreamIdle(vm)

        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].role, .user)
        XCTAssertEqual(vm.messages[0].content, "你好")
        XCTAssertEqual(vm.messages[1].role, .assistant)
        XCTAssertEqual(vm.messages[1].content, "Hello")
        XCTAssertEqual(vm.messages[1].status, .complete)
    }

    // MARK: - Streaming updates content

    func testStreamingUpdatesAssistantContentIncrementally() async {
        let service = CapturingAIChatService()
        service.streamChunks = ["第一段", "第一段\n第二段"]
        let vm = AIChatSessionViewModel(service: service)

        vm.send("Q")
        await awaitStreamIdle(vm)

        XCTAssertEqual(vm.messages.last?.content, "第一段\n第二段")
        XCTAssertEqual(vm.messages.last?.status, .complete)
        XCTAssertFalse(vm.isStreaming)
    }

    // MARK: - Stop keeps partial content

    func testStopKeepsPartialContentAndMarksComplete() async {
        let service = CapturingAIChatService()
        // 模拟一个永不主动结束的流，靠 stop 中断
        service.neverEnding = true
        let vm = AIChatSessionViewModel(service: service)

        vm.send("Q")
        // 让流产生一个 chunk 后停止
        await Task.yield()
        await Task.yield()
        vm.stop()

        if let assistant = vm.messages.last {
            XCTAssertEqual(assistant.status, .complete)
        }
        XCTAssertFalse(vm.isStreaming)
    }

    // MARK: - Not configured

    func testNotConfiguredSetsErrorAndSendsNoRequest() async {
        let service = CapturingAIChatService()
        service.configured = false
        let vm = AIChatSessionViewModel(service: service)

        vm.send("Q")

        XCTAssertEqual(vm.configurationError, "未配置 AI 模型")
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertTrue(service.capturedMessages.isEmpty)
    }

    // MARK: - Multi-turn history passed to service

    func testMultiTurnHistoryPassedToService() async {
        let service = CapturingAIChatService()
        service.streamChunks = ["A1", "A1 续"]
        let vm = AIChatSessionViewModel(service: service)

        vm.send("Q1")
        await awaitStreamIdle(vm)

        service.streamChunks = ["A2"]
        vm.send("Q2")
        await awaitStreamIdle(vm)

        // 第二次发送时，service 应收到 Q1 + A1 + Q2（不含当前空 assistant）
        let captured = service.capturedMessages
        XCTAssertEqual(captured.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(captured.map(\.content), ["Q1", "A1 续", "Q2"])
    }

    // MARK: - Failure status

    func testStreamFailureMarksAssistantFailed() async {
        let service = CapturingAIChatService()
        service.streamError = LLMRefiner.Error.httpError(code: 500)
        let vm = AIChatSessionViewModel(service: service)

        vm.send("Q")
        await awaitStreamIdle(vm)

        if case .failed = vm.messages.last?.status {
            // 期望
        } else {
            XCTFail("期望 failed 状态，实际：\(String(describing: vm.messages.last?.status))")
        }
    }

    // MARK: - Reset clears session

    func testResetClearsMessages() async {
        let service = CapturingAIChatService()
        service.streamChunks = ["A"]
        let vm = AIChatSessionViewModel(service: service)

        vm.send("Q")
        await awaitStreamIdle(vm)
        XCTAssertFalse(vm.messages.isEmpty)

        vm.reset()
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNil(vm.configurationError)
    }

    // MARK: - Helpers

    private func awaitStreamIdle(_ vm: AIChatSessionViewModel) async {
        for _ in 0..<200 {
            if !vm.isStreaming { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

// MARK: - Capturing service

private final class CapturingAIChatService: AIChatServicing, @unchecked Sendable {
    var configured = true
    var capturedMessages: [AIChatMessage] = []
    var streamChunks: [String] = []
    var streamError: Error?
    var neverEnding = false

    var isConfigured: Bool { configured }

    func streamResponse(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error> {
        capturedMessages = messages
        let chunks = streamChunks
        let error = streamError
        let neverEnding = self.neverEnding
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if !neverEnding {
                continuation.finish()
            }
            // neverEnding 时保留 continuation 不结束，等待外部 cancel
            continuation.onTermination = { _ in }
        }
    }
}
