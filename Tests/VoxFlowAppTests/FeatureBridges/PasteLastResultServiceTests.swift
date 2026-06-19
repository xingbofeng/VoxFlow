import CoreGraphics
import XCTest
@testable import VoxFlowApp

@MainActor
final class PasteLastResultServiceTests: XCTestCase {
    func testPasteLastResultIgnoresClipboardImage() async {
        let recorder = PasteLastResultRecorder(
            image: PasteLastResultTestImage.make(),
            recognizedText: "image text",
            lastResult: "previous text",
            imageOCREnabled: true
        )

        let outcome = await recorder.service.pasteLastResult()

        XCTAssertEqual(outcome, .pastedLastResult)
        XCTAssertEqual(recorder.output.deliveredTexts, ["previous text"])
        XCTAssertEqual(recorder.ocr.requestCount, 0)
    }

    func testClipboardImageOCRPastesRecognizedImageTextThroughOutputService() async {
        let recorder = PasteLastResultRecorder(
            image: PasteLastResultTestImage.make(),
            recognizedText: "  image text  ",
            lastResult: "previous text",
            imageOCREnabled: true
        )

        let outcome = await recorder.service.pasteClipboardImageOCR()

        XCTAssertEqual(outcome, .pastedOCRText)
        XCTAssertEqual(recorder.output.deliveredTexts, ["image text"])
        XCTAssertEqual(recorder.store.lastResultText, "image text")
    }

    func testClipboardImageOCRDoesNotFallBackToPreviousResultWhenClipboardHasNoImage() async {
        let recorder = PasteLastResultRecorder(
            image: nil,
            recognizedText: "image text",
            lastResult: "previous text",
            imageOCREnabled: true
        )

        let outcome = await recorder.service.pasteClipboardImageOCR()

        XCTAssertEqual(outcome, .ocrFailed("剪贴板里没有可识别的图片"))
        XCTAssertTrue(recorder.output.deliveredTexts.isEmpty)
        XCTAssertEqual(recorder.ocr.requestCount, 0)
    }

    func testOCRFailureDoesNotOverwritePreviousResultOrPasteFallbackText() async {
        let recorder = PasteLastResultRecorder(
            image: PasteLastResultTestImage.make(),
            recognizedText: "ignored",
            lastResult: "previous text",
            imageOCREnabled: true
        )
        recorder.ocr.error = PasteLastResultTestError.ocrFailed

        let outcome = await recorder.service.pasteClipboardImageOCR()

        XCTAssertEqual(outcome, .ocrFailed("ocr failed"))
        XCTAssertTrue(recorder.output.deliveredTexts.isEmpty)
        XCTAssertEqual(recorder.store.lastResultText, "previous text")
    }

    func testDisabledClipboardImageOCRDoesNotPastePreviousResult() async {
        let recorder = PasteLastResultRecorder(
            image: PasteLastResultTestImage.make(),
            recognizedText: "image text",
            lastResult: "previous text",
            imageOCREnabled: false
        )

        let outcome = await recorder.service.pasteClipboardImageOCR()

        XCTAssertEqual(outcome, .ocrFailed("剪贴板图片 OCR 未启用"))
        XCTAssertTrue(recorder.output.deliveredTexts.isEmpty)
        XCTAssertEqual(recorder.ocr.requestCount, 0)
    }
}

@MainActor
private final class PasteLastResultRecorder {
    let store: InMemoryLastResultStore
    let imageProvider: StubClipboardImageProvider
    let ocr: StubOCRRecognizer
    let output: CapturingOutputService
    let service: PasteLastResultService

    init(
        image: CGImage?,
        recognizedText: String,
        lastResult: String?,
        imageOCREnabled: Bool
    ) {
        store = InMemoryLastResultStore()
        store.setLastResultText(lastResult)
        imageProvider = StubClipboardImageProvider(image: image)
        ocr = StubOCRRecognizer(text: recognizedText)
        output = CapturingOutputService()
        service = PasteLastResultService(
            lastResultStore: store,
            clipboardImageProvider: imageProvider,
            ocrRecognizer: ocr,
            outputService: output,
            targetProvider: StaticDictationTargetProvider(target: nil),
            isImageOCREnabled: { imageOCREnabled }
        )
    }
}

private enum PasteLastResultTestImage {
    static func make() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}

private enum PasteLastResultTestError: LocalizedError {
    case ocrFailed

    var errorDescription: String? {
        "ocr failed"
    }
}

@MainActor
private final class StubClipboardImageProvider: ClipboardImageProviding {
    let image: CGImage?

    init(image: CGImage?) {
        self.image = image
    }

    func currentImage() -> CGImage? {
        image
    }
}

@MainActor
private final class StubOCRRecognizer: TextOCRRecognizing {
    private let text: String
    var error: Error?
    private(set) var requestCount = 0

    init(text: String) {
        self.text = text
    }

    func recognizeText(in image: CGImage) async throws -> String {
        requestCount += 1
        if let error {
            throw error
        }
        return text
    }
}

@MainActor
private final class CapturingOutputService: OutputService {
    private(set) var deliveredTexts: [String] = []

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        deliveredTexts.append(text)
        return .injected
    }
}

private struct StaticDictationTargetProvider: DictationTargetProviding {
    let target: DictationTarget?

    func currentTarget() -> DictationTarget? {
        target
    }
}
