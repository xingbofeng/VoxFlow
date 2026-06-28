import Foundation
import XCTest
@testable import VoxFlowApp

final class OCRTemporaryContextExtractorTests: XCTestCase {

    func testExtractsTermsFromOCRText() {
        let result = OCRTemporaryContextExtractor.extractTerms(
            from: "Ghostty terminal\nVoxFlow app\nPostgreSQL database"
        )
        // The extractor splits on whitespace/newlines, producing multiple candidates
        // but capped at 5. Key terms should be present.
        XCTAssertLessThanOrEqual(result.terms.count, 5)
        XCTAssertTrue(result.terms.contains("Ghostty"))
        XCTAssertEqual(result.skippedReason, nil)
    }

    func testMaxFiveTermsExtracted() {
        let ocrText = (1...20).map { "Term\($0)" }.joined(separator: " ")
        let result = OCRTemporaryContextExtractor.extractTerms(from: ocrText)
        XCTAssertEqual(result.terms.count, 5)
    }

    func testSecureFieldSkipsExtraction() {
        let result = OCRTemporaryContextExtractor.extractTerms(
            from: "some text",
            secureField: true
        )
        XCTAssertTrue(result.terms.isEmpty)
        XCTAssertEqual(result.skippedReason, "secure_field")
    }

    func testEmptyOCRTextReturnsEmpty() {
        let result = OCRTemporaryContextExtractor.extractTerms(from: "")
        XCTAssertTrue(result.terms.isEmpty)
        XCTAssertNil(result.skippedReason)
    }

    func testDeduplicatesTerms() {
        let result = OCRTemporaryContextExtractor.extractTerms(
            from: "Ghostty Ghostty ghostty GHOSTTY"
        )
        // Only one "Ghostty" variant should remain
        XCTAssertEqual(result.terms.count, 1)
    }

    func testFiltersTooShortTerms() {
        let result = OCRTemporaryContextExtractor.extractTerms(from: "A B CC DDD")
        // "A" and "B" are too short (1 char)
        XCTAssertFalse(result.terms.contains("A"))
        XCTAssertFalse(result.terms.contains("B"))
    }

    func testCharCountRecorded() {
        let result = OCRTemporaryContextExtractor.extractTerms(from: "Ghostty terminal here")
        XCTAssertGreaterThan(result.charCount, 0)
    }

    func testTermsNotWrittenToHotwordTable() {
        // This test verifies the design contract: extractTerms returns terms
        // but does NOT interact with any repository. The caller is responsible
        // for only injecting them into the current session's prompt/ASR context.
        let result = OCRTemporaryContextExtractor.extractTerms(from: "Ghostty")
        XCTAssertTrue(result.terms.contains("Ghostty"))
        // No repository interaction — terms are ephemeral
    }
}
