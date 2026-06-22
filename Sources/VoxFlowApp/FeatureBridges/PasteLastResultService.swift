import CoreGraphics
import Foundation

@MainActor
protocol LastResultStoring: AnyObject {
    var lastResultText: String? { get }
    func setLastResultText(_ text: String?)
}

@MainActor
final class InMemoryLastResultStore: LastResultStoring {
    private(set) var lastResultText: String?

    func setLastResultText(_ text: String?) {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        lastResultText = trimmedText?.isEmpty == false ? trimmedText : nil
    }
}

@MainActor
protocol ClipboardImageProviding: AnyObject {
    func currentImage() -> CGImage?
}

protocol TextOCRRecognizing: AnyObject, Sendable {
    func recognizeText(in image: CGImage) async throws -> String
    /// 识别图像中的文字，返回每行的文本和 bounding box（image 坐标，top-left origin，points）。
    func recognizeTextLines(in image: CGImage) async throws -> [OCRLine]
}

/// 一行 OCR 识别结果。boundingBox 使用 image 像素坐标，原点在左上角（top-left）。
public struct OCRLine: Equatable, Sendable {
    public let text: String
    public let boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

enum PasteLastResultOutcome: Equatable {
    case pastedLastResult
    case pastedOCRText
    case noTextAvailable
    case ocrFailed(String)
    case outputFailed(OutputResult)
}

@MainActor
final class PasteLastResultService {
    private let lastResultStore: any LastResultStoring
    private let clipboardImageProvider: any ClipboardImageProviding
    private let ocrRecognizer: any TextOCRRecognizing
    private let outputService: any OutputService
    private let targetProvider: any DictationTargetProviding
    private let isImageOCREnabled: () -> Bool

    init(
        lastResultStore: any LastResultStoring,
        clipboardImageProvider: any ClipboardImageProviding,
        ocrRecognizer: any TextOCRRecognizing,
        outputService: any OutputService,
        targetProvider: any DictationTargetProviding,
        isImageOCREnabled: @escaping () -> Bool
    ) {
        self.lastResultStore = lastResultStore
        self.clipboardImageProvider = clipboardImageProvider
        self.ocrRecognizer = ocrRecognizer
        self.outputService = outputService
        self.targetProvider = targetProvider
        self.isImageOCREnabled = isImageOCREnabled
    }

    func paste() async -> PasteLastResultOutcome {
        await pasteLastResult()
    }

    func pasteLastResult() async -> PasteLastResultOutcome {
        guard let text = lastResultStore.lastResultText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            AppLogger.dictation.debug("paste_last_result no cached text")
            return .noTextAvailable
        }
        AppLogger.dictation.debug("paste_last_result using cached text length=\(text.count)")
        do {
            return try await pasteText(text, success: .pastedLastResult, shouldRemember: false)
        } catch is CancellationError {
            AppLogger.general.debug("paste_last_result cancelled")
            return .outputFailed(.cancelled)
        } catch {
            AppLogger.general.error("paste_last_result failed: \(error.localizedDescription)")
            return .outputFailed(.injectionFailed(reason: error.localizedDescription))
        }
    }

    func pasteClipboardImageOCR() async -> PasteLastResultOutcome {
        guard isImageOCREnabled() else {
            AppLogger.dictation.warning("paste_clipboard_image_ocr disabled")
            return .ocrFailed("剪贴板图片识别未启用")
        }
        guard let image = clipboardImageProvider.currentImage() else {
            AppLogger.dictation.warning("paste_clipboard_image_ocr no image")
            return .ocrFailed("剪贴板里没有可识别的图片")
        }
        let originalTarget = targetProvider.currentTarget()
        return await pasteOCRText(from: image, originalTarget: originalTarget)
    }

    private func pasteOCRText(
        from image: CGImage,
        originalTarget: DictationTarget?
    ) async -> PasteLastResultOutcome {
        do {
            AppLogger.dictation.debug("paste_clipboard_image_ocr start")
            try Task.checkCancellation()
            let text = try await ocrRecognizer
                .recognizeText(in: image)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !text.isEmpty else {
                AppLogger.dictation.warning("paste_clipboard_image_ocr empty text")
                return .ocrFailed("未识别到图片文字")
            }
            AppLogger.general.debug("paste_clipboard_image_ocr recognized length=\(text.count)")
            return try await pasteText(
                text,
                success: .pastedOCRText,
                shouldRemember: true,
                originalTarget: originalTarget
            )
        } catch is CancellationError {
            AppLogger.general.debug("paste_clipboard_image_ocr cancelled")
            return .ocrFailed("已取消")
        } catch {
            AppLogger.general.error("paste_clipboard_image_ocr failed: \(error.localizedDescription)")
            return .ocrFailed(error.localizedDescription)
        }
    }

    private func pasteText(
        _ text: String,
        success: PasteLastResultOutcome,
        shouldRemember: Bool,
        originalTarget: DictationTarget? = nil
    ) async throws -> PasteLastResultOutcome {
        try Task.checkCancellation()
        let target = targetProvider.currentTarget()
        AppLogger.dictation.debug("paste_text start len=\(text.count) target=\(target?.bundleID ?? "nil")")
        let result = await outputService.deliver(
            text: text,
            mode: .dictation,
            target: target,
            originalTarget: originalTarget ?? target
        )
        try Task.checkCancellation()
        guard result.isPasteLastResultSuccess else {
            AppLogger.general.warning("paste_text failed kind=\(result.kind.rawValue)")
            return .outputFailed(result)
        }
        if shouldRemember {
            lastResultStore.setLastResultText(text)
        }
        AppLogger.dictation.info("paste_text success outcome=\(success)")
        return success
    }
}

private extension OutputResult {
    var isPasteLastResultSuccess: Bool {
        switch self {
        case .injected, .copied:
            return true
        case .targetChanged, .permissionDenied, .injectionFailed, .copyFailed, .cancelled:
            return false
        }
    }
}
