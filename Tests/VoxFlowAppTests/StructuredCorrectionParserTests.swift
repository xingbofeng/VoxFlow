import Foundation
import XCTest
@testable import VoxFlowApp

/// Tests for StructuredCorrectionParser — covers all Light-Whisper
/// `parse_structured_response` tolerant parsing scenarios.
///
/// Covers tasks 8.1-8.9 from redesign-vocabulary-hotwords-learning.
final class StructuredCorrectionParserTests: XCTestCase {

    // MARK: - Task 8.2: Bare JSON

    func testParsesBareJSONObject() {
        let response = #"{"polished":"修正后的文本","corrections":[],"key_terms":[]}"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(output.polished, "修正后的文本")
        XCTAssertEqual(output.corrections.count, 0)
        XCTAssertEqual(output.keyTerms.count, 0)
    }

    func testParsesBareJSONWithCorrectionsAndKeyTerms() {
        let response = """
        {"polished":"跟陈睿过一下 PR","corrections":[{"original":"陈瑞","corrected":"陈睿","type":"term"}],"key_terms":["陈睿","PR"]}
        """
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(output.polished, "跟陈睿过一下 PR")
        XCTAssertEqual(output.corrections.count, 1)
        XCTAssertEqual(output.corrections.first?.original, "陈瑞")
        XCTAssertEqual(output.corrections.first?.corrected, "陈睿")
        XCTAssertEqual(output.keyTerms, ["陈睿", "PR"])
    }

    // MARK: - Task 8.3: Array wrapper

    func testParsesArrayWrapper() {
        let response = #" [{"polished":"文本","corrections":[],"key_terms":[]}]"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success for array wrapper")
            return
        }
        XCTAssertEqual(output.polished, "文本")
    }

    // MARK: - Task 8.4: CDATA wrapper

    func testParsesCDATAWrapper() {
        let response = #"<![CDATA[{"polished":"文本","corrections":[],"key_terms":[]}]]>"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success for CDATA")
            return
        }
        XCTAssertEqual(output.polished, "文本")
    }

    // MARK: - Task 8.5: XML <output> wrapper

    func testParsesXMLOutputWrapper() {
        let response = #"<output>{"polished":"文本","corrections":[],"key_terms":[]}</output>"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success for XML output wrapper")
            return
        }
        XCTAssertEqual(output.polished, "文本")
    }

    // MARK: - Task 8.6: JSON extraction from explanatory text

    func testExtractsJSONFromExplanatoryText() {
        let response = """
        Here is the corrected text:
        {"polished":"修正后","corrections":[],"key_terms":[]}
        Hope this helps!
        """
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success for text-extracted JSON")
            return
        }
        XCTAssertEqual(output.polished, "修正后")
    }

    func testExtractsJSONFromMarkdownCodeBlock() {
        let response = """
        ```json
        {"polished":"修正后","corrections":[],"key_terms":[]}
        ```
        """
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success for markdown code block")
            return
        }
        XCTAssertEqual(output.polished, "修正后")
    }

    // MARK: - Task 8.7: Parse failure fallback

    func testParseFailureFallsBackToRawText() {
        let response = "This is just plain text with no JSON at all."
        let result = StructuredCorrectionParser.parse(response)
        guard case .fallback(let rawText, let reason) = result else {
            XCTFail("Expected fallback, got \(result)")
            return
        }
        XCTAssertEqual(rawText, "This is just plain text with no JSON at all.")
        XCTAssertEqual(reason, "llm_structured_parse_failed")
    }

    func testEmptyResponseFallsBack() {
        let result = StructuredCorrectionParser.parse("")
        guard case .fallback(let rawText, let reason) = result else {
            XCTFail("Expected fallback for empty")
            return
        }
        XCTAssertEqual(rawText, "")
        XCTAssertEqual(reason, "empty_response")
    }

    // MARK: - Task 8.8: Corrections validation

    func testFiltersEmptyCorrections() {
        let response = #"{"polished":"文本","corrections":[{"original":"","corrected":"X","type":"term"}],"key_terms":[]}"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(output.corrections.count, 0)
    }

    func testFiltersSameValueCorrections() {
        let response = #"{"polished":"文本","corrections":[{"original":"相同","corrected":"相同","type":"term"}],"key_terms":[]}"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(output.corrections.count, 0)
    }

    func testFiltersTooLongCorrections() {
        let longText = String(repeating: "A", count: 101)
        let response = #"{"polished":"文本","corrections":[{"original":"\#(longText)","corrected":"X","type":"term"}],"key_terms":[]}"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(output.corrections.count, 0)
    }

    // MARK: - Task 8.9: Key terms validation

    func testFiltersFillerWordsFromKeyTerms() {
        let response = #"{"polished":"文本","corrections":[],"key_terms":["嗯","VoxFlow","啊"]}"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(output.keyTerms, ["VoxFlow"])
    }

    func testFiltersActionCommandsFromKeyTerms() {
        let response = #"{"polished":"文本","corrections":[],"key_terms":["删除","PostgreSQL","保存"]}"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(output.keyTerms, ["PostgreSQL"])
    }

    func testFiltersTooLongKeyTerms() {
        let longTerm = String(repeating: "B", count: 51)
        let response = #"{"polished":"文本","corrections":[],"key_terms":["\#(longTerm)","OK"]}"#
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(output.keyTerms, ["OK"])
    }

    // MARK: - Task 87: Parse failure doesn't lose text

    func testFallbackPreservesOriginalTextForUser() {
        let response = "用户说的原始文本，没有 JSON 结构"
        let result = StructuredCorrectionParser.parse(response)
        guard case .fallback(let rawText, _) = result else {
            XCTFail("Expected fallback")
            return
        }
        // The fallback text should be usable as the final output — user doesn't lose text
        XCTAssertEqual(rawText, "用户说的原始文本，没有 JSON 结构")
    }

    // MARK: - Task 86: All Light-Whisper scenarios covered

    func testNestedJSONInText() {
        let response = """
        The result is:
        {"polished":"final text","corrections":[{"original":"a","corrected":"b","type":"homophone"}],"key_terms":["term1"]}
        Done.
        """
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(output.polished, "final text")
        XCTAssertEqual(output.corrections.count, 1)
        XCTAssertEqual(output.keyTerms, ["term1"])
    }

    func testJSONWithExtraWhitespace() {
        let response = """
        {
          "polished": "文本",
          "corrections": [],
          "key_terms": []
        }
        """
        let result = StructuredCorrectionParser.parse(response)
        guard case .success(let output) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(output.polished, "文本")
    }
}
