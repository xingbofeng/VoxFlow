import XCTest
@testable import VoxFlowApp

final class TextTransformServiceTests: XCTestCase {
    func testTranslationUsesStreamingRefinerAndEmitsPartialSnapshots() async {
        let refiner = FakeStreamingTextRefiner(snapshots: ["人", "人工智能"])
        let service = TextTransformService(refiner: refiner)

        let events = await collect(
            service.events(
                for: TextTransformRequest(
                    text: "Artificial intelligence",
                    operation: .translation
                )
            )
        )

        XCTAssertEqual(events, [
            .started(totalUnits: nil),
            .partialText("人"),
            .partialText("人工智能"),
            .completed("人工智能"),
        ])
        XCTAssertEqual(refiner.requests.map(\.text), ["Artificial intelligence"])
        XCTAssertTrue(refiner.requests[0].systemPrompt.contains("翻译"))
        XCTAssertEqual(refiner.requests[0].temperature, 0.2)
    }

    func testBlockingRefinerTransformsChunksAndEmitsUnitProgress() async {
        let first = String(repeating: "第一段。", count: 8)
        let second = String(repeating: "第二段。", count: 8)
        let refiner = FakeBlockingTextRefiner(outputs: ["译文一", "译文二"])
        let service = TextTransformService(refiner: refiner, maxCharactersPerChunk: 40)

        let events = await collect(
            service.events(
                for: TextTransformRequest(
                    text: "\(first)\n\n\(second)",
                    operation: .translation
                )
            )
        )

        XCTAssertEqual(events, [
            .started(totalUnits: 2),
            .unitCompleted(index: 0, text: "译文一"),
            .partialText("译文一"),
            .unitCompleted(index: 1, text: "译文二"),
            .partialText("译文一\n\n译文二"),
            .completed("译文一\n\n译文二"),
        ])
        XCTAssertEqual(refiner.requests.map(\.text), [first, second])
    }

    func testUnavailableRefinerCanProvideOperationSpecificFailureMessage() async {
        let refiner = UnavailableMessagingTextRefiner(message: "Apple 系统翻译在当前系统版本不可用")
        let service = TextTransformService(refiner: refiner)

        let events = await collect(
            service.events(
                for: TextTransformRequest(
                    text: "Artificial intelligence",
                    operation: .translation
                )
            )
        )

        XCTAssertEqual(events, [
            .failed(message: "Apple 系统翻译在当前系统版本不可用", partialText: ""),
        ])
    }

    private func collect(_ stream: AsyncStream<TextTransformEvent>) async -> [TextTransformEvent] {
        var events: [TextTransformEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }
}

private final class FakeStreamingTextRefiner: StreamingPromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    private let snapshots: [String]
    private(set) var requests: [TextRefinementRequest] = []

    init(snapshots: [String]) {
        self.snapshots = snapshots
    }

    func refine(_ text: String) async throws -> String {
        snapshots.last ?? text
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        requests.append(request)
        return snapshots.last ?? request.text
    }

    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        let snapshots = snapshots
        return AsyncThrowingStream { continuation in
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
    }
}

private final class FakeBlockingTextRefiner: PromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    private let outputs: [String]
    private(set) var requests: [TextRefinementRequest] = []

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func refine(_ text: String) async throws -> String {
        outputs.first ?? text
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        let index = requests.count
        requests.append(request)
        return outputs.indices.contains(index) ? outputs[index] : request.text
    }
}

private final class UnavailableMessagingTextRefiner: PromptAwareTextRefining, TextTransformAvailabilityMessaging, @unchecked Sendable {
    var isEnabled = false
    var isConfigured = false
    private let message: String

    init(message: String) {
        self.message = message
    }

    func unavailableMessage(for operation: TextTransformOperation) -> String {
        message
    }

    func refine(_ text: String) async throws -> String {
        text
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        request.text
    }
}
