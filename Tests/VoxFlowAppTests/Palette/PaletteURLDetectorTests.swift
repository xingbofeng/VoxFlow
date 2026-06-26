import XCTest
@testable import VoxFlowApp

@MainActor
final class PaletteURLDetectorTests: XCTestCase {
    // MARK: - Scheme URLs are preserved

    func testHttpsURLPreserved() {
        XCTAssertEqual(
            PaletteURLDetector.normalizedURL(for: "https://example.com/path"),
            "https://example.com/path"
        )
    }

    func testHttpURLPreserved() {
        XCTAssertEqual(
            PaletteURLDetector.normalizedURL(for: "http://example.com"),
            "http://example.com"
        )
    }

    func testHttpLocalhostWithPortAndPathPreserved() {
        XCTAssertEqual(
            PaletteURLDetector.normalizedURL(for: "http://localhost:3000/docs"),
            "http://localhost:3000/docs"
        )
    }

    // MARK: - Bare domains normalized to https

    func testBareDomainWithPathNormalizedToHTTPS() {
        XCTAssertEqual(
            PaletteURLDetector.normalizedURL(for: "github.com/openai/codex"),
            "https://github.com/openai/codex"
        )
    }

    func testWWWDomainNormalizedToHTTPS() {
        XCTAssertEqual(
            PaletteURLDetector.normalizedURL(for: "www.google.com"),
            "https://www.google.com"
        )
    }

    func testBareDomainWithPortNormalizedToHTTPS() {
        XCTAssertEqual(
            PaletteURLDetector.normalizedURL(for: "example.com:8080"),
            "https://example.com:8080"
        )
    }

    // MARK: - localhost / IP normalized to http

    func testLocalhostWithPortNormalizedToHTTP() {
        XCTAssertEqual(
            PaletteURLDetector.normalizedURL(for: "localhost:3000"),
            "http://localhost:3000"
        )
    }

    func testIPv4WithPortNormalizedToHTTP() {
        XCTAssertEqual(
            PaletteURLDetector.normalizedURL(for: "127.0.0.1:8080"),
            "http://127.0.0.1:8080"
        )
    }

    func testBareLocalhostNormalizedToHTTP() {
        XCTAssertEqual(
            PaletteURLDetector.normalizedURL(for: "localhost"),
            "http://localhost"
        )
    }

    // MARK: - Non-URLs return nil

    func testPlainEnglishWordsRejected() {
        XCTAssertNil(PaletteURLDetector.normalizedURL(for: "swift concurrency"))
    }

    func testSingleWordRejected() {
        XCTAssertNil(PaletteURLDetector.normalizedURL(for: "swift"))
        XCTAssertNil(PaletteURLDetector.normalizedURL(for: "github"))
    }

    func testChineseTextRejected() {
        XCTAssertNil(PaletteURLDetector.normalizedURL(for: "解释 SwiftUI StateObject"))
    }

    func testQuicklinkQueryWithSpaceRejected() {
        XCTAssertNil(PaletteURLDetector.normalizedURL(for: "taobao macbook stand"))
    }

    func testEmptyInputRejected() {
        XCTAssertNil(PaletteURLDetector.normalizedURL(for: ""))
        XCTAssertNil(PaletteURLDetector.normalizedURL(for: "   "))
    }

    func testWordWithDotButNoTLDRejected() {
        // "swift.concurrency" 不是合法域名（无 TLD），应被拒绝
        XCTAssertNil(PaletteURLDetector.normalizedURL(for: "swift.concurrency"))
    }
}
