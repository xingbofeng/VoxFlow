import XCTest
@testable import VoiceInputApp

final class AppDelegateASRMenuTests: XCTestCase {
    @MainActor
    func testASRMenuOptionsExposeEverySelectableLocalVariant() {
        let options = AppDelegate.makeASRMenuOptions()

        XCTAssertEqual(
            options.map(\.title),
            [
                "系统自带",
                "FunASR Nano INT8",
                "FunASR Nano FP32",
                "Whisper Turbo",
                "Whisper Large V3",
                "Qwen3-ASR 0.6B",
                "Qwen3-ASR 1.7B",
                "Paraformer 中文",
                "Paraformer English",
                "SenseVoice Small",
            ]
        )
    }
}
