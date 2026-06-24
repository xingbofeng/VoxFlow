import Foundation
import VoxFlowScreenshotKit

@MainActor
struct LineMappedTranslationService {
    private let translator: any PromptAwareTextRefining

    init(translator: any PromptAwareTextRefining) {
        self.translator = translator
    }

    func translate(_ lines: [OCRLine]) async -> [String] {
        await ScreenshotOCRService.translateLines(lines, translator: translator)
    }

    func events(for lines: [OCRLine]) -> AsyncStream<LineTransformEvent> {
        ScreenshotOCRService.lineTranslationEvents(lines, translator: translator)
    }
}
