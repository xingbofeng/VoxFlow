import XCTest
@testable import VoxFlowApp

final class SSEParserTests: XCTestCase {
    /// Helper: creates a byte stream from raw SSE text.
    private func byteStream(from sseText: String) -> AsyncThrowingStream<UInt8, Error> {
        var result: AsyncThrowingStream<UInt8, Error>!
        result = AsyncThrowingStream<UInt8, Error> { continuation in
            for byte in sseText.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        return result
    }

    func testParsesMultiDeltaStream() async throws {
        let sseText = """
        data: {"id":"1","choices":[{"delta":{"content":"He"}}]}

        data: {"id":"1","choices":[{"delta":{"content":"llo"}}]}

        data: {"id":"1","choices":[{"delta":{"content":" world"}}]}

        data: [DONE]

        """
        let stream = SSEParser.parse(byteStream: byteStream(from: sseText))
        var results: [String] = []
        for try await text in stream {
            results.append(text)
        }
        XCTAssertEqual(results, ["He", "Hello", "Hello world"])
    }

    func testParsesUTF8ChineseDeltaWithoutMojibake() async throws {
        let sseText = """
        data: {"id":"1","choices":[{"delta":{"content":"帮我搜一下"}}]}

        data: {"id":"1","choices":[{"delta":{"content":"最近的 AI 新闻"}}]}

        data: [DONE]

        """
        let stream = SSEParser.parse(byteStream: byteStream(from: sseText))
        var results: [String] = []
        for try await text in stream {
            results.append(text)
        }
        XCTAssertEqual(results, ["帮我搜一下", "帮我搜一下最近的 AI 新闻"])
    }

    func testSkipsEmptyDelta() async throws {
        let sseText = """
        data: {"id":"1","choices":[{"delta":{"role":"assistant"}}]}

        data: {"id":"1","choices":[{"delta":{"content":"Hi"}}]}

        data: {"id":"1","choices":[{"delta":{"content":"!"}}]}

        data: [DONE]

        """
        let stream = SSEParser.parse(byteStream: byteStream(from: sseText))
        var results: [String] = []
        for try await text in stream {
            results.append(text)
        }
        XCTAssertEqual(results, ["Hi", "Hi!"])
    }

    func testSkipsInvalidJSONLines() async throws {
        let sseText = """
        data: {broken json}

        data: {"id":"1","choices":[{"delta":{"content":"OK"}}]}

        data: [DONE]

        """
        let stream = SSEParser.parse(byteStream: byteStream(from: sseText))
        var results: [String] = []
        for try await text in stream {
            results.append(text)
        }
        XCTAssertEqual(results, ["OK"])
    }

    func testStreamEndsWithoutDoneMarker() async throws {
        // Stream that ends normally without a [DONE] sentinel — SSE events are still processed
        // if they have proper \n\n delimiters.
        let sseText = """
        data: {"id":"1","choices":[{"delta":{"content":"Done"}}]}

        """
        let stream = SSEParser.parse(byteStream: byteStream(from: sseText))
        var results: [String] = []
        for try await text in stream {
            results.append(text)
        }
        XCTAssertEqual(results, ["Done"])
    }

    func testIgnoresCommentLines() async throws {
        let sseText = """
        : this is a comment

        data: {"id":"1","choices":[{"delta":{"content":"Text"}}]}

        event: ping

        data: [DONE]

        """
        let stream = SSEParser.parse(byteStream: byteStream(from: sseText))
        var results: [String] = []
        for try await text in stream {
            results.append(text)
        }
        XCTAssertEqual(results, ["Text"])
    }

    func testSingleCharacterDeltas() async throws {
        let sseText = """
        data: {"id":"1","choices":[{"delta":{"content":"A"}}]}

        data: {"id":"1","choices":[{"delta":{"content":"B"}}]}

        data: {"id":"1","choices":[{"delta":{"content":"C"}}]}

        data: [DONE]

        """
        let stream = SSEParser.parse(byteStream: byteStream(from: sseText))
        var results: [String] = []
        for try await text in stream {
            results.append(text)
        }
        XCTAssertEqual(results, ["A", "AB", "ABC"])
    }
}
