import VoxFlowASRCore
import VoxFlowProviderXASR
import XCTest
@testable import VoxFlowApp

final class XASRErrorPresentationTests: XCTestCase {
    func testRuntimeFailureUsesReadableLocalizedCopy() {
        let error = XASRErrorPresentation.localizedError(XASRRuntimeError.busy)
        XCTAssertEqual(error.localizedDescription, L10n.localize("asr.xasr.busy", comment: "X-ASR busy"))
    }

    func testCoreFailureKeepsCategoryAndLocalizesMessage() {
        let source = ASRCoreBackedASREngineError.failure(.init(category: .audioDropped, message: "audioDropped"))
        let error = XASRErrorPresentation.localizedError(source)
        guard case .failure(let core) = error as? ASRCoreBackedASREngineError else { return XCTFail("lost error classification") }
        XCTAssertEqual(core.category, .audioDropped)
        XCTAssertEqual(core.message, L10n.localize("asr.xasr.invalid_audio", comment: "X-ASR invalid audio"))
    }
}
