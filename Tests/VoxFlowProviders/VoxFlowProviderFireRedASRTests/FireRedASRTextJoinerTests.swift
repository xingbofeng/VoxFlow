import Foundation
@testable import VoxFlowProviderFireRedASR
import XCTest

final class FireRedASRTextJoinerTests: XCTestCase {
    func testEnglishPartsAreSeparatedByASpace() {
        XCTAssertEqual(FireRedASRTextJoiner.join(["hello", "world"]), "hello world")
    }

    func testChinesePartsAreJoinedWithoutASpace() {
        XCTAssertEqual(FireRedASRTextJoiner.join(["第一句", "第二句"]), "第一句第二句")
    }

    func testMixedPartsFollowTheBoundaryCharacters() {
        XCTAssertEqual(FireRedASRTextJoiner.join(["嗯", "ON TIME", "叫准时"]), "嗯ON TIME叫准时")
    }

    func testEmptyPartsAreSkippedWithoutLeavingStraySpaces() {
        XCTAssertEqual(FireRedASRTextJoiner.join(["", "hello", "", "world", ""]), "hello world")
        XCTAssertEqual(FireRedASRTextJoiner.join(["", "  ", ""]), "")
    }

    func testSinglePartIsReturnedUnchanged() {
        XCTAssertEqual(FireRedASRTextJoiner.join(["昨天是 MONDAY TODAY"]), "昨天是 MONDAY TODAY")
    }

    func testPunctuationBoundariesDoNotGetASpace() {
        XCTAssertEqual(FireRedASRTextJoiner.join(["第一句。", "Second"]), "第一句。Second")
    }
}
