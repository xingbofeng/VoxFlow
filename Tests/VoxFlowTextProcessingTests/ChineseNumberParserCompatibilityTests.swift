import XCTest
@testable import VoxFlowTextProcessing

// Compatibility tests for `ChineseNumberParser` derived from official
// `Ailln/cn2an` `cn2an_test.py`.
// Source: https://github.com/Ailln/cn2an
//
// Applicable scope:
//   - Strict mode: basic numbers, large numbers with 零, uppercase (大写),
//     decimals, negatives, classical (廿二).
//   - Normal mode: colloquial quantities (一百二, 两千六, 三万五), repeated
//     digits (一一, 一一一), traditional (兩千六).
//   - Direct mode: digit-by-digit (二〇〇二, 幺八九).
//
// Excluded upstream test categories (not applicable to VoxFlow pipe scope):
//   - Financial/currency format (`壹拾壹元整`, `玖仟陆佰陆拾伍圆壹角捌分`) —
//     VoxFlow's `ChineseNumberParser` is a pure numeral parser. Currency
//     suffix stripping (`元整`, `圆正`, `角`, `分`) is not part of the
//     voice-input pipe. Financial numeral digits (壹贰叁...) ARE supported
//     by the digit map; only the currency suffix handling is excluded.
//   - Smart mode (`100万`, `10.1万`, `200亿零四千230`) — VoxFlow does not
//     handle mixed Arabic/Chinese notation in the parser. Mixed-notation
//     conversion requires sentence-level context analysis which is handled
//     by `ChineseITNNormalizer`, not the parser.
//   - `an2cn` (Arabic to Chinese) — VoxFlow only does Chinese-to-Arabic.
//   - `transform_test.py` — Tests cn2an's full sentence transform function,
//     not isolated parser behavior. Applicable sentence-level cases are
//     covered by `ChineseITNCompatibilityTests`.
//   - Error cases that expect `ValueError` — Swift's `ChineseNumberParser`
//     returns nil instead of raising. nil-return behavior is tested.

final class ChineseNumberParserCompatibilityTests: XCTestCase {
    private struct OfficialFixture: Decodable {
        struct Case: Decodable {
            let source: String
            let input: String
            let expected: String
        }

        struct Exclusion: Decodable {
            let source: String
            let input: String
            let reason: String
        }

        let source: String
        let license: String
        let caseCount: Int
        let cases: [Case]
        let exclusions: [Exclusion]
    }

    func testOfficialCn2anParserFixtures() throws {
        let fixture = try loadOfficialCn2anFixture()
        XCTAssertEqual(fixture.source, "Ailln/cn2an cn2an/cn2an_test.py")
        XCTAssertEqual(fixture.license, "MIT")
        XCTAssertEqual(fixture.caseCount, 116)
        XCTAssertEqual(fixture.cases.count, fixture.caseCount)
        XCTAssertEqual(fixture.exclusions.count, 23)

        for testCase in fixture.cases {
            let actual = testCase.source == "direct_data_dict"
                ? ChineseNumberParser.parseDirect(testCase.input)
                : ChineseNumberParser.parse(testCase.input)
            XCTAssertEqual(
                actual,
                testCase.expected,
                "source: \(testCase.source), input: \(testCase.input)"
            )
        }
    }

    private func loadOfficialCn2anFixture() throws -> OfficialFixture {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "cn2an_official_parser", withExtension: "json"),
            "Missing official cn2an parser fixture resource"
        )
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(OfficialFixture.self, from: data)
    }

    // MARK: - Strict mode: basic numbers
    // Source: `cn2an_test.py` → `strict_data_dict`

    func testCn2anBasicNumbers() {
        let cases: [(String, String)] = [
            ("零", "0"),
            ("一", "1"),
            ("十", "10"),
            ("十一", "11"),
            ("一十一", "11"),
            ("二十", "20"),
            ("二十一", "21"),
            ("一百", "100"),
            ("一百零一", "101"),
            ("一百一十", "110"),
            ("一百一十一", "111"),
            ("一千", "1000"),
            ("一千一百", "1100"),
            ("一千一百一十", "1110"),
            ("一千一百一十一", "1111"),
            ("一千零一十", "1010"),
            ("一千零十一", "1011"),
            ("一千零一", "1001"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Strict mode: large numbers with 零

    func testCn2anLargeNumbersWithZero() {
        let cases: [(String, String)] = [
            ("十万", "100000"),
            ("十万零一", "100001"),
            ("一万零一", "10001"),
            ("一万零一十一", "10011"),
            ("一万零一百一十一", "10111"),
            ("一百万零一", "1000001"),
            ("一千万零一", "10000001"),
            ("一亿零一", "100000001"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Strict mode: section units (万/亿)

    func testCn2anSectionUnits() {
        let cases: [(String, String)] = [
            ("一万一千一百一十一", "11111"),
            ("一十一万一千一百一十一", "111111"),
            ("一百一十一万一千一百一十一", "1111111"),
            ("一千一百一十一万一千一百一十一", "11111111"),
            ("一亿一千一百一十一万一千一百一十一", "111111111"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Strict mode: uppercase (大写) numbers

    func testCn2anUppercaseNumbers() {
        let cases: [(String, String)] = [
            ("壹", "1"),
            ("拾", "10"),
            ("拾壹", "11"),
            ("壹拾壹", "11"),
            ("壹佰壹拾壹", "111"),
            ("壹仟壹佰壹拾壹", "1111"),
            ("壹万壹仟壹佰壹拾壹", "11111"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Strict mode: decimals

    func testCn2anDecimals() {
        let cases: [(String, String)] = [
            ("零点一", "0.1"),
            ("零点零一", "0.01"),
            ("零点零零一", "0.001"),
            ("零点零零零一", "0.0001"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Strict mode: negatives

    func testCn2anNegatives() {
        let cases: [(String, String)] = [
            ("负一", "-1"),
            ("负二", "-2"),
            ("负十", "-10"),
            ("负十一", "-11"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Strict mode: classical (古语)

    func testCn2anClassical() {
        XCTAssertEqual(ChineseNumberParser.parse("廿二"), "22")
    }

    // MARK: - Normal mode: colloquial quantities
    // Source: `cn2an_test.py` → `normal_data_dict`

    func testCn2anColloquialQuantities() {
        let cases: [(String, String)] = [
            ("一百二", "120"),
            ("两千六", "2600"),
            ("三万五", "35000"),
            ("十三万五", "135000"),
            ("一百十一", "111"),
            ("一百十六", "116"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Normal mode: repeated digits

    func testCn2anRepeatedDigits() {
        let cases: [(String, String)] = [
            ("一一", "11"),
            ("一一一", "111"),
            ("一七二零", "1720"),
            ("一二三", "123"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Normal mode: traditional Chinese

    func testCn2anTraditionalChinese() {
        XCTAssertEqual(ChineseNumberParser.parse("兩千六"), "2600")
    }

    // MARK: - Normal mode: decimal with repeated digits

    func testCn2anDecimalWithRepeatedDigits() {
        let cases: [(String, String)] = [
            ("一七二零点一", "1720.1"),
            ("一七二零点一三四", "1720.134"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Direct mode: digit-by-digit
    // Source: `cn2an_test.py` → `direct_data_dict`

    func testCn2anDirectModeDigits() {
        let cases: [(String, String)] = [
            ("零一", "01"),
            ("零零三", "003"),
            ("二〇〇二", "2002"),
            ("幺八九", "189"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChineseNumberParser.parse(input), expected, "input: \(input)")
        }
    }

    // MARK: - Invalid inputs return nil

    func testCn2anInvalidInputsReturnNil() {
        // Inputs that cn2an rejects with ValueError; VoxFlow returns nil.
        XCTAssertNil(ChineseNumberParser.parse(""))
        XCTAssertNil(ChineseNumberParser.parse("点零"))
        XCTAssertNil(ChineseNumberParser.parse("零点点"))
        XCTAssertNil(ChineseNumberParser.parse("十十"))
    }

    // MARK: - Exclusion documentation
    //
    // The following cn2an test categories are intentionally NOT imported:
    //
    // 1. Financial/currency format (`壹拾壹元整` → `11`, `玖仟陆佰陆拾伍圆
    //    壹角捌分` → `9665.18`) — VoxFlow's parser is a pure numeral parser.
    //    Currency suffix stripping is not part of the voice-input pipe.
    //    Financial numeral DIGITS (壹贰叁...) are supported; only the
    //    currency suffix handling (元/圆/角/分/整/正) is excluded.
    //
    // 2. Smart mode (`100万` → `1000000`, `10.1万` → `101000`) — Mixed
    //    Arabic/Chinese notation requires sentence-level context analysis.
    //    VoxFlow's parser only handles pure Chinese numeral strings.
    //
    // 3. `an2cn` (Arabic to Chinese) — VoxFlow only does Chinese-to-Arabic.
    //
    // 4. `transform_test.py` — Tests cn2an's full sentence transform, not
    //    isolated parser behavior. Applicable sentence-level cases are
    //    covered by `ChineseITNCompatibilityTests`.
    //
    // 5. Strict mode error cases that expect `ValueError` — Swift returns
    //    nil instead of raising. nil-return behavior is tested above.
}
