import XCTest
import ChineseInput

@MainActor
final class KeyboardVoiceEntryCoordinatorTests: XCTestCase {
    override func tearDown() {
        ChineseKeyboardModeStore.active = .chineseQwerty
        super.tearDown()
    }

    func testVoiceEntryFromChineseQwertyPreparesCompositionBeforeRecording() async {
        await verifyVoiceEntryOrder(from: .chineseQwerty)
    }

    func testVoiceEntryFromChineseNineGridPreparesCompositionBeforeRecording() async {
        await verifyVoiceEntryOrder(from: .chineseNineGrid)
    }

    private func verifyVoiceEntryOrder(from mode: ChineseInputMode) async {
        ChineseKeyboardModeStore.active = mode
        var events: [String] = []

        await KeyboardVoiceEntryCoordinator.prepareChineseCompositionAndStartRecording(
            prepareChineseComposition: {
                events.append("prepare")
            },
            startRecording: {
                events.append("startRecording")
            }
        )

        XCTAssertEqual(ChineseKeyboardModeStore.active, mode)
        XCTAssertEqual(events, ["prepare", "startRecording"])
    }
}
