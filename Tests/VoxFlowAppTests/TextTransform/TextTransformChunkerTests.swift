import XCTest
@testable import VoxFlowApp

final class TextTransformChunkerTests: XCTestCase {
    func testShortTextReturnsSingleChunk() {
        let input = "Artificial intelligence is changing how we write."

        let chunks = TextTransformChunker.chunks(
            for: input,
            maxCharactersPerChunk: 1_200
        )

        XCTAssertEqual(chunks, [
            TextTransformChunk(index: 0, text: input, sourceRange: 0..<input.count)
        ])
    }

    func testLongTextSplitsOnParagraphBoundaries() {
        let first = String(repeating: "第一段内容很长。", count: 90)
        let second = String(repeating: "第二段内容也很长。", count: 90)
        let input = "\(first)\n\n\(second)"

        let chunks = TextTransformChunker.chunks(
            for: input,
            maxCharactersPerChunk: 900
        )

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].index, 0)
        XCTAssertEqual(chunks[0].text, first)
        XCTAssertEqual(chunks[1].index, 1)
        XCTAssertEqual(chunks[1].text, second)
    }

    func testLongSingleParagraphSplitsIntoBoundedChunks() {
        let input = String(repeating: "这是一句很长的内容，用来模拟用户选中一整段没有空行的文章。", count: 24)

        let chunks = TextTransformChunker.chunks(
            for: input,
            maxCharactersPerChunk: 120
        )

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 120 })
        XCTAssertEqual(chunks.map(\.text).joined(), input)
        XCTAssertEqual(chunks.map(\.index), Array(chunks.indices))
    }

    func testMarkdownCodeFenceStaysInOneChunk() {
        let input = """
        这段文字解释下面的命令。

        ```swift
        let message = "hello"
        print(message)
        ```

        结束段落。
        """

        let chunks = TextTransformChunker.chunks(
            for: input,
            maxCharactersPerChunk: 20
        )

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[1].text, """
        ```swift
        let message = "hello"
        print(message)
        ```
        """)
    }

    func testTextTransformEventCanRepresentPartialFailure() {
        let event = TextTransformEvent.failed(
            message: "网络超时",
            partialText: "已完成的译文"
        )

        XCTAssertEqual(event, .failed(message: "网络超时", partialText: "已完成的译文"))
    }
}
