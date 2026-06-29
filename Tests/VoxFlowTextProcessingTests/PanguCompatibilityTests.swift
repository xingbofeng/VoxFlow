import XCTest
@testable import VoxFlowTextProcessing

// Compatibility tests derived from official `vinta/pangu.js` `tests/shared/*.test.ts`.
// Source: https://github.com/vinta/pangu.js
//
// Applicable scope:
//   - `cjk-alphabets-numbers.test.ts` — CJK + Latin/digit spacing (core behavior).
//   - Selected file-extension, path, and version protection cases from
//     `symbol-period.test.ts` and `symbol-slash.test.ts`.
//   - Date/time compact-unit preservation cases.
//
// Excluded upstream test categories (not applicable to VoxFlow pipe scope):
//   - `api.test.ts` — Tests Pangu's Node/browser API surface, not spacing behavior.
//   - `symbol-*.test.ts` (symbol spacing: comma, colon, exclamation, question,
//     semicolon, brackets, quotes, etc.) — VoxFlow's `PunctuationOptimizer`
//     converts half-width punctuation to full-width in CJK context instead of
//     adding spaces around symbols. These two approaches are mutually exclusive;
//     importing the symbol spacing cases would conflict with Section 5.
//   - Hiragana, Katakana, Bopomofo, CJK Radicals Supplement, Kangxi Radicals,
//     Enclosed CJK Letters And Months, CJK Unified Ideographs Extension-A,
//     CJK Compatibility Ideographs, Number Forms — These scripts are outside
//     VoxFlow's Chinese voice input scope. VoxFlow's `CJKLatinSpacer` targets
//     Han (CJK Unified Ideographs) + ASCII/Latin/Greek boundaries, which covers
//     the realistic voice-input character set.
//   - Browser, DOM, CLI, package import, and extension integration tests —
//     Not applicable to a native macOS text processing pipe.
//   - `symbol-at.test.ts` — `@` handling is covered by `ProtectedRegions.email`
//     pattern; standalone `@username` mentions are not a voice-input priority.
//   - `symbol-percent-sign.test.ts` — `%` handling is covered by
//     `SmartNumberRecognizer` percent conversion; standalone `%` spacing is not
//     part of the CJK-Latin spacing processor.
//   - `symbol-slash.test.ts` operator cases (e.g. `A/B`) — VoxFlow treats `/`
//     as a path separator in `ProtectedRegions.path`, not as a math operator
//     that needs spacing. Operator spacing conflicts with path protection.

final class PanguCompatibilityTests: XCTestCase {
    private struct OfficialFixture: Decodable {
        struct Case: Decodable {
            let source: String
            let input: String
            let expected: String
        }

        let source: String
        let license: String
        let caseCount: Int
        let cases: [Case]
    }

    func testOfficialPanguSharedSpacingFixtures() throws {
        let fixture = try loadOfficialPanguFixture()
        XCTAssertEqual(fixture.source, "vinta/pangu.js tests/shared/*.test.ts")
        XCTAssertEqual(fixture.license, "MIT")
        XCTAssertEqual(fixture.caseCount, 420)
        XCTAssertEqual(fixture.cases.count, fixture.caseCount)

        for testCase in fixture.cases {
            XCTAssertEqual(
                CJKLatinSpacer.process(testCase.input),
                testCase.expected,
                "source: \(testCase.source), input: \(testCase.input)"
            )
        }
    }

    private func loadOfficialPanguFixture() throws -> OfficialFixture {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "pangu_official_spacing", withExtension: "json"),
            "Missing official Pangu fixture resource"
        )
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(OfficialFixture.self, from: data)
    }

    // MARK: - CJK + Alphabets (core spacing)
    // Source: `cjk-alphabets-numbers.test.ts` → "CJK A N 兩邊都加空格"

    func testPanguCJKAndAlphabetShortTextSpacing() {
        let cases: [(String, String)] = [
            ("中a", "中 a"),
            ("a中", "a 中"),
            ("中a1", "中 a1"),
            ("a1中", "a1 中"),
            ("a中1", "a 中 1"),
            ("1中a", "1 中 a"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CJKLatinSpacer.process(input), expected, "input: \(input)")
        }
    }

    func testPanguCJKAndAlphabetWordSpacing() {
        let cases: [(String, String)] = [
            ("中文abc", "中文 abc"),
            ("abc中文", "abc 中文"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CJKLatinSpacer.process(input), expected, "input: \(input)")
        }
    }

    func testPanguCJKAndDigitSpacing() {
        let cases: [(String, String)] = [
            ("中文123", "中文 123"),
            ("123中文", "123 中文"),
            ("1中", "1 中"),
            ("中1", "中 1"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CJKLatinSpacer.process(input), expected, "input: \(input)")
        }
    }

    // MARK: - CJK + Latin-1 Supplement / Greek
    // Source: `cjk-alphabets-numbers.test.ts` → Latin-1 Supplement, Greek and Coptic

    func testPanguCJKAndLatin1SupplementSpacing() {
        XCTAssertEqual(CJKLatinSpacer.process("中文Ø漢字"), "中文 Ø 漢字")
        XCTAssertEqual(CJKLatinSpacer.process("中文 Ø 漢字"), "中文 Ø 漢字")
    }

    func testPanguCJKAndGreekSpacing() {
        XCTAssertEqual(CJKLatinSpacer.process("中文β漢字"), "中文 β 漢字")
        XCTAssertEqual(CJKLatinSpacer.process("中文 β 漢字"), "中文 β 漢字")
        XCTAssertEqual(CJKLatinSpacer.process("我是α，我是Ω"), "我是 α，我是 Ω")
    }

    // MARK: - Date and time unit preservation
    // Source: `cjk-alphabets-numbers.test.ts` + VoxFlow-specific date preservation

    func testPanguCompactChineseDatePreserved() {
        XCTAssertEqual(CJKLatinSpacer.process("我在2021年1月生日"), "我在2021年1月生日")
        XCTAssertEqual(CJKLatinSpacer.process("在1月1日提醒我"), "在1月1日提醒我")
    }

    // MARK: - File extension and version protection
    // Source: `symbol-period.test.ts` → "handle . symbol as file path"

    func testPanguFileExtensionPreservedWithSpacing() {
        let cases: [(String, String)] = [
            ("使用Python.py檔案", "使用 Python.py 檔案"),
            ("設定檔.env很重要", "設定檔.env 很重要"),
            ("編輯器.vscode目錄", "編輯器.vscode 目錄"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CJKLatinSpacer.process(input), expected, "input: \(input)")
        }
    }

    func testPanguVersionStringPreservedWithSpacing() {
        let cases: [(String, String)] = [
            ("版本v1.2.3發布了", "版本 v1.2.3 發布了"),
            ("pangu.js v1.2.3橫空出世", "pangu.js v1.2.3 橫空出世"),
            ("pangu.js 1.2.3橫空出世", "pangu.js 1.2.3 橫空出世"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CJKLatinSpacer.process(input), expected, "input: \(input)")
        }
    }

    func testPanguFileNameWithMultipleDotsPreserved() {
        let cases: [(String, String)] = [
            ("檔案package.lock.json存在", "檔案 package.lock.json 存在"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CJKLatinSpacer.process(input), expected, "input: \(input)")
        }
    }

    // MARK: - Unix path protection
    // Source: `symbol-slash.test.ts` → "Unix absolute/relative file path"

    func testPanguUnixAbsolutePathPreservedWithSpacing() {
        let cases: [(String, String)] = [
            ("/home和/root是Linux中的頂級目錄", "/home 和 /root 是 Linux 中的頂級目錄"),
            ("在/home目錄", "在 /home 目錄"),
            ("查看/etc/passwd文件", "查看 /etc/passwd 文件"),
            ("進入/usr/local/bin目錄", "進入 /usr/local/bin 目錄"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CJKLatinSpacer.process(input), expected, "input: \(input)")
        }
    }

    func testPanguUnixRelativePathPreservedWithSpacing() {
        let cases: [(String, String)] = [
            ("檢查src/main.py文件", "檢查 src/main.py 文件"),
            ("構建dist/index.js完成", "構建 dist/index.js 完成"),
            ("編輯docs/README.md文檔", "編輯 docs/README.md 文檔"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CJKLatinSpacer.process(input), expected, "input: \(input)")
        }
    }

    // MARK: - URL and email protection
    // Source: VoxFlow protected region behavior + Pangu-inspired

    func testPanguURLPreserved() {
        let result = CJKLatinSpacer.process("访问https://example.com查看")
        XCTAssertTrue(result.contains("https://example.com"))
        XCTAssertFalse(result.contains("https ://"))
    }

    func testPanguEmailPreserved() {
        let result = CJKLatinSpacer.process("发给test@example.com好了")
        XCTAssertTrue(result.contains("test@example.com"))
    }

    // MARK: - Mixed text
    // Source: `cjk-alphabets-numbers.test.ts` + mixed scenarios

    func testPanguMixedCJKLatinDigitSpacing() {
        XCTAssertEqual(CJKLatinSpacer.process("Hello世界"), "Hello 世界")
        XCTAssertEqual(CJKLatinSpacer.process("共3个文件"), "共 3 个文件")
    }

    func testPanguAlreadySpacedTextUnchanged() {
        let cases: [(String, String)] = [
            ("中文 abc", "中文 abc"),
            ("abc 中文", "abc 中文"),
            ("中文 123", "中文 123"),
            ("123 中文", "123 中文"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(CJKLatinSpacer.process(input), expected, "input: \(input)")
        }
    }

    // MARK: - Exclusion documentation
    // The following Pangu test categories are intentionally NOT imported:
    //
    // 1. `symbol-period.test.ts` (most cases) — Pangu adds right-space after `.`:
    //    `前面.後面` → `前面. 後面`. VoxFlow's `PunctuationOptimizer` converts
    //    `.` to `。` in CJK context. These approaches conflict; only file-path
    //    and version-string cases are imported above.
    //
    // 2. `symbol-comma.test.ts` — Pangu adds right-space after `,`. VoxFlow
    //    converts `,` to `，` in CJK context.
    //
    // 3. `symbol-colon.test.ts` — Pangu adds right-space after `:`. VoxFlow
    //    converts `:` to `：` in CJK context.
    //
    // 4. `symbol-round-brackets.test.ts`, `symbol-square-brackets.test.ts`,
    //    `symbol-curly-brackets.test.ts`, `symbol-angle-brackets.test.ts` —
    //    Pangu adds spaces around brackets. VoxFlow converts `()` to `（）`
    //    in CJK context.
    //
    // 5. `symbol-double-quotes.test.ts`, `symbol-single-quotes.test.ts` —
    //    Pangu adds spaces around quotes. VoxFlow preserves quote style.
    //
    // 6. `symbol-exclamation-mark.test.ts`, `symbol-question-mark.test.ts`,
    //    `symbol-semicolon.test.ts` — Same conflict: VoxFlow converts to
    //    full-width `！？；` in CJK context.
    //
    // 7. `symbol-ampersand.test.ts`, `symbol-asterisk.test.ts`,
    //    `symbol-backslash.test.ts`, `symbol-backtick.test.ts`,
    //    `symbol-caret.test.ts`, `symbol-dollar-sign.test.ts`,
    //    `symbol-equals-sign.test.ts`, `symbol-greater-than-sign.test.ts`,
    //    `symbol-hashtag.test.ts`, `symbol-less-than-sign.test.ts`,
    //    `symbol-minus-signs.test.ts`, `symbol-others.test.ts`,
    //    `symbol-pipe.test.ts`, `symbol-plus-sign.test.ts`,
    //    `symbol-tilde.test.ts`, `symbol-underscore.test.ts` —
    //    Symbol spacing around CJK is handled by PunctuationOptimizer or
    //    not applicable to voice input.
    //
    // 8. `symbol-slash.test.ts` operator cases — `A/B` → `A / B` conflicts
    //    with VoxFlow's path protection. Only path cases are imported.
    //
    // 9. `symbol-at.test.ts` — `@username` handling is covered by
    //    `ProtectedRegions.email` for emails; standalone mentions are not
    //    a voice-input priority.
    //
    // 10. `symbol-percent-sign.test.ts` — `%` handling is covered by
    //     `SmartNumberRecognizer` percent conversion.
    //
    // 11. Exotic script cases from `cjk-alphabets-numbers.test.ts`:
    //     - Number Forms (Ⅶ), CJK Radicals Supplement (⻤), Kangxi Radicals (⾗),
    //       Hiragana (あ), Katakana (ア), Bopomofo (ㄅ), Enclosed CJK (㈱),
    //       CJK Extension-A (㐂), CJK Compatibility (車)
    //     — These scripts are outside VoxFlow's Chinese voice input scope.
    //       VoxFlow targets Han + ASCII/Latin/Greek, which covers the
    //       realistic voice-input character set.
}
