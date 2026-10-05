import XCTest
@testable import VoxFlowR2T2Core

/// `canonicalLanguageName` is what turns a host's language hint into the prompt's
/// `language X<asr_text>` header. The list is the checkpoint's own `support_languages`.
final class LanguageTests: XCTestCase {
    private let supported = [
        "Chinese", "English", "Cantonese", "Arabic", "German", "French", "Spanish", "Portuguese",
        "Indonesian", "Italian", "Korean", "Russian", "Thai", "Vietnamese", "Japanese", "Turkish",
        "Hindi", "Malay", "Dutch", "Swedish", "Danish", "Finnish", "Polish", "Czech", "Filipino",
        "Persian", "Greek", "Romanian", "Hungarian", "Macedonian",
    ]
    private func name(_ raw: String) -> String? { Qwen3ASRModel.canonicalLanguageName(raw, supported: supported) }

    func testNamesAndAliasesResolve() {
        XCTAssertEqual(name("English"), "English")
        XCTAssertEqual(name("chinese"), "Chinese")
        XCTAssertEqual(name("Mandarin"), "Chinese")
        XCTAssertEqual(name(" cantonese "), "Cantonese")
    }

    func testISOCodesResolve() {
        XCTAssertEqual(name("en"), "English")
        XCTAssertEqual(name("zh"), "Chinese")
        XCTAssertEqual(name("yue"), "Cantonese")
        XCTAssertEqual(name("fil"), "Filipino")   // outside the alias table: Foundation's English name
        XCTAssertEqual(name("fa"), "Persian")
        XCTAssertEqual(name("el"), "Greek")
    }

    func testBCP47LocalesResolveByTheirPrimarySubtag() {
        // What a macOS host holds (Locale.preferredLanguages, a Dictate setting) — before 0.1.1
        // "en-US" became "En-us", a language the model has never seen.
        XCTAssertEqual(name("en-US"), "English")
        XCTAssertEqual(name("zh-Hans-CN"), "Chinese")
        XCTAssertEqual(name("zh_CN"), "Chinese")
        XCTAssertEqual(name("yue-Hant-HK"), "Cantonese")
        XCTAssertEqual(name("pt-BR"), "Portuguese")
    }

    func testUnsupportedLanguageMeansAutoDetect() {
        XCTAssertNil(name("sw"))          // Swahili: not in this checkpoint's list
        XCTAssertNil(name("Klingon"))
        XCTAssertNil(name(""))
    }

    func testWithoutASupportListTheBestGuessPasses() {
        XCTAssertEqual(Qwen3ASRModel.canonicalLanguageName("en-US", supported: []), "English")
    }
}
