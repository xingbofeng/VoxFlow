import CoreGraphics
import XCTest
import VoxFlowScreenshotKit
@testable import VoxFlowApp

@MainActor
final class LineMappedTranslationServiceTests: XCTestCase {
    func testStructuredResponseMapsTranslationsBackToOriginalLineIndexes() async {
        let translator = FakeLineMappedTranslator(
            response: """
            [{"index":1,"translated":"年龄"},{"index":0,"translated":"姓名"}]
            """
        )
        let lines = [
            OCRLine(text: "Name", boundingBox: CGRect(x: 0, y: 0, width: 1, height: 20)),
            OCRLine(text: "Age", boundingBox: CGRect(x: 0, y: 20, width: 1, height: 20)),
        ]

        let events = await collect(
            LineMappedTranslationService(translator: translator).events(for: lines)
        )

        XCTAssertEqual(events, [
            LineTransformEvent(
                completedLines: [0: "姓名", 1: "年龄"],
                totalLineCount: 2,
                isFinal: true
            ),
        ])
        XCTAssertEqual(translator.requests.map(\.text), [
            """
            [{"index":0,"text":"Name"},{"index":1,"text":"Age"}]
            """,
        ])
    }

    private func collect(_ stream: AsyncStream<LineTransformEvent>) async -> [LineTransformEvent] {
        var events: [LineTransformEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }
}

private final class FakeLineMappedTranslator: PromptAwareTextRefining, StructuredLineTranslationSupporting, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    var supportsStructuredLineTranslation = true
    private let response: String
    private(set) var requests: [TextRefinementRequest] = []

    init(response: String) {
        self.response = response
    }

    func refine(_ text: String) async throws -> String {
        response
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        requests.append(request)
        return response
    }
}
