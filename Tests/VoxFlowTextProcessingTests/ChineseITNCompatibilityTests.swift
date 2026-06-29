import XCTest
@testable import VoxFlowTextProcessing

// Compatibility tests for `ChineseITNNormalizer` and `SmartNumberRecognizer`
// driven by official `wenet-e2e/WeTextProcessing` Chinese ITN fixtures.
// Source: https://github.com/wenet-e2e/WeTextProcessing
//
// The JSON fixture imports every line from `itn/chinese/test/data/*.txt`.
// Cases inside VoxFlow's lightweight pipe scope are executable; cases that
// require WeText's full FST runtime, config flags, or UX choices that conflict
// with VoxFlow are recorded as explicit exclusions with reasons.

final class ChineseITNCompatibilityTests: XCTestCase {
    private struct OfficialFixture: Decodable {
        struct TestCase: Decodable {
            let file: String
            let line: Int
            let input: String
            let expected: String
            let processor: String
        }

        struct Exclusion: Decodable {
            let file: String
            let line: Int
            let input: String
            let expected: String
            let reason: String
        }

        let source: String
        let license: String
        let upstreamPath: String
        let totalCaseCount: Int
        let includedCaseCount: Int
        let excludedCaseCount: Int
        let cases: [TestCase]
        let exclusions: [Exclusion]
    }

    func testOfficialWeTextChineseITNFixtures() throws {
        let fixture = try loadOfficialWeTextFixture()
        XCTAssertEqual(fixture.source, "wenet-e2e/WeTextProcessing itn/chinese/test/data/*.txt")
        XCTAssertEqual(fixture.license, "Apache-2.0")
        XCTAssertEqual(fixture.upstreamPath, "itn/chinese/test/data")
        XCTAssertEqual(fixture.totalCaseCount, 292)
        XCTAssertEqual(fixture.includedCaseCount, 81)
        XCTAssertEqual(fixture.excludedCaseCount, 211)
        XCTAssertEqual(fixture.cases.count, fixture.includedCaseCount)
        XCTAssertEqual(fixture.exclusions.count, fixture.excludedCaseCount)
        XCTAssertEqual(fixture.cases.count + fixture.exclusions.count, fixture.totalCaseCount)
        XCTAssertTrue(fixture.exclusions.allSatisfy { !$0.reason.isEmpty })

        for testCase in fixture.cases {
            XCTAssertEqual(
                output(for: testCase),
                testCase.expected,
                "source: \(testCase.file):\(testCase.line), input: \(testCase.input)"
            )
        }
    }

    private func output(for testCase: OfficialFixture.TestCase) -> String {
        switch testCase.processor {
        case "smartNumberRecognizer":
            return SmartNumberRecognizer.process(testCase.input)
        default:
            XCTFail("Unsupported processor in fixture: \(testCase.processor)")
            return testCase.input
        }
    }

    private func loadOfficialWeTextFixture() throws -> OfficialFixture {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "wetext_official_chinese_itn", withExtension: "json"),
            "Missing official WeText Chinese ITN fixture resource"
        )
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(OfficialFixture.self, from: data)
    }

    func testProtectedRegionsPreserved() {
        let result1 = SmartNumberRecognizer.process("访问 https://example.com 查看三秒钟")
        XCTAssertTrue(result1.contains("https://example.com"))
        XCTAssertTrue(result1.contains("3秒"))

        let result2 = SmartNumberRecognizer.process("版本 1.2.3 修复了三个问题")
        XCTAssertTrue(result2.contains("1.2.3"))
        XCTAssertTrue(result2.contains("3个"))

        let result3 = SmartNumberRecognizer.process("使用 `var x = 三` 代码")
        XCTAssertTrue(result3.contains("`var x = 三`"))
    }

    func testConservativeNoConversion() {
        XCTAssertEqual(SmartNumberRecognizer.process("三十而立属于固定短语"), "三十而立属于固定短语")
        XCTAssertEqual(SmartNumberRecognizer.process("一定要一起讨论一下"), "一定要一起讨论一下")
    }
}
