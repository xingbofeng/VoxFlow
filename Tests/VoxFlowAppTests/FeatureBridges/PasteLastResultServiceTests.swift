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

    func testClipboardImageOCRUsesOriginalTargetFromStartOfOCR() async {
        let originalTarget = DictationTarget(bundleID: "app.a", appName: "App A", pid: 1)
        let currentTarget = DictationTarget(bundleID: "app.b", appName: "App B", pid: 2)
        let ocr = SuspendingOCRRecognizer()
        let recorder = PasteLastResultRecorder(
            image: PasteLastResultTestImage.make(),
            recognizedText: "image text",
            lastResult: nil,
            imageOCREnabled: true,
            target: originalTarget,
            ocr: ocr
        )
        recorder.output.onDeliver = { _, target, originalTarget in
            DictationTargetChangePolicy.targetChanged(original: originalTarget, current: target)
                ? .targetChanged(reason: "目标窗口已变化，内容已复制到剪贴板")
                : .injected
        }
        let task = Task { @MainActor in
            await recorder.service.pasteClipboardImageOCR()
        }
        await ocr.waitUntilStarted()
        recorder.targetProvider.target = currentTarget
        await ocr.finish(with: "image text")

        let outcome = await task.value

        XCTAssertEqual(outcome, .outputFailed(.targetChanged(reason: "目标窗口已变化，内容已复制到剪贴板")))
        XCTAssertEqual(recorder.output.deliveries.map(\.target), [currentTarget])
        XCTAssertEqual(recorder.output.deliveries.map(\.originalTarget), [originalTarget])
        XCTAssertNil(recorder.store.lastResultText)
    }

    func testCancelledClipboardImageOCRDoesNotDeliverOrRememberText() async {
        let ocr = SuspendingOCRRecognizer()
        let recorder = PasteLastResultRecorder(
            image: PasteLastResultTestImage.make(),
            recognizedText: "ignored",
            lastResult: nil,
            imageOCREnabled: true,
            ocr: ocr
        )

        let task = Task { @MainActor in
            await recorder.service.pasteClipboardImageOCR()
        }
        await ocr.waitUntilStarted()
        task.cancel()
        await ocr.finish(with: "late text")
        _ = await task.value

        XCTAssertTrue(recorder.output.deliveredTexts.isEmpty)
        XCTAssertNil(recorder.store.lastResultText)
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
    let targetProvider: MutableDictationTargetProvider
    let service: PasteLastResultService

    init(
        image: CGImage?,
        recognizedText: String,
        lastResult: String?,
        imageOCREnabled: Bool,
        target: DictationTarget? = nil,
        ocr: (any TextOCRRecognizing)? = nil
    ) {
        store = InMemoryLastResultStore()
        store.setLastResultText(lastResult)
        imageProvider = StubClipboardImageProvider(image: image)
        self.ocr = StubOCRRecognizer(text: recognizedText)
        output = CapturingOutputService()
        targetProvider = MutableDictationTargetProvider(target: target)
        service = PasteLastResultService(
            lastResultStore: store,
            clipboardImageProvider: imageProvider,
            ocrRecognizer: ocr ?? self.ocr,
            outputService: output,
            targetProvider: targetProvider,
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
private final class StubOCRRecognizer: TextOCRRecognizing, @unchecked Sendable {
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
private final class SuspendingOCRRecognizer: TextOCRRecognizing, @unchecked Sendable {
    private var hasStarted = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<String, Never>?
    private(set) var wasCancelled = false

    func recognizeText(in image: CGImage) async throws -> String {
        hasStarted = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                resultContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.wasCancelled = true
            }
        }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            if hasStarted {
                continuation.resume()
            } else {
                startedWaiters.append(continuation)
            }
        }
    }

    func finish(with text: String) async {
        resultContinuation?.resume(returning: text)
        resultContinuation = nil
    }
}

@MainActor
private final class CapturingOutputService: OutputService {
    struct Delivery: Equatable {
        let text: String
        let target: DictationTarget?
        let originalTarget: DictationTarget?
    }

    private(set) var deliveredTexts: [String] = []
    private(set) var deliveries: [Delivery] = []
    var onDeliver: ((String, DictationTarget?, DictationTarget?) -> OutputResult)?

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        deliveredTexts.append(text)
        deliveries.append(Delivery(text: text, target: target, originalTarget: originalTarget))
        return onDeliver?(text, target, originalTarget) ?? .injected
    }
}

@MainActor
private final class MutableDictationTargetProvider: DictationTargetProviding {
    var target: DictationTarget?

    init(target: DictationTarget?) {
        self.target = target
    }

    func currentTarget() -> DictationTarget? {
        target
    }
}
