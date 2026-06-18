import XCTest
import VoxFlowTextInsertion

final class InputSourceClassifierTests: XCTestCase {
    func testChineseJapaneseAndKoreanSourcesAreCJK() {
        XCTAssertTrue(
            InputSourceClassifier.isCJK(
                sourceID: "com.apple.inputmethod.SCIM.ITABC",
                languages: ["zh-Hans"]
            )
        )
        XCTAssertTrue(
            InputSourceClassifier.isCJK(
                sourceID: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                languages: ["ja"]
            )
        )
        XCTAssertTrue(
            InputSourceClassifier.isCJK(
                sourceID: "com.apple.inputmethod.Korean.2SetKorean",
                languages: ["ko"]
            )
        )
    }

    func testASCIIAndUnrelatedInputMethodsAreNotCJK() {
        XCTAssertFalse(
            InputSourceClassifier.isCJK(
                sourceID: "com.apple.keylayout.ABC",
                languages: ["en"]
            )
        )
        XCTAssertFalse(
            InputSourceClassifier.isCJK(
                sourceID: "com.apple.inputmethod.Vietnamese",
                languages: ["vi"]
            )
        )
    }

    func testThirdPartyChineseSourceIsDetectedByLanguage() {
        XCTAssertTrue(
            InputSourceClassifier.isCJK(
                sourceID: "com.example.inputmethod",
                languages: ["zh-Hant"]
            )
        )
    }
}
